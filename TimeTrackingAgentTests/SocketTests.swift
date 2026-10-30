// The socket: pushed events and rewrite commands (spec_activity_tracking.md
// §3.1, §7.3).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct SocketTests {
    /// Sends `line` from another thread (the server answers on the main actor).
    private func send(_ line: String, to url: URL) async -> TrackerReply {
        await Task.detached { TrackerSocketClient(socketURL: url, timeout: 5).send(line: line) }.value
    }

    @Test("TRK-21 a tracker-event line advances the tick within 1 second; an unknown command gets error and changes nothing")
    func socketEvents() async throws {
        let harness = try AgentHarness()
        await harness.engine.tick()
        let url = harness.root.appending(path: "Group/tracker.sock", directoryHint: .notDirectory)
        let server = SocketServer(url: url) { line in await harness.engine.handle(line: line) }
        try server.start()
        defer { server.stop() }

        // The line runs the tick before the reply (no timer: the manual
        // clock only moves by advance). The 1-second bound must hold for
        // the fastest of three round trips, so one delayed by a loaded
        // machine does not fail it.
        let clock = ContinuousClock()
        var latencies: [Duration] = []
        for attempt in 1 ... 3 {
            harness.advance(7)
            let started = clock.now
            let reply = await send("tmux after-select-pane", to: url)
            latencies.append(clock.now - started)
            #expect(reply == .success)
            #expect(harness.samples().count == 1 + attempt)
            #expect(harness.samples().last?.time == harness.time(TimeInterval(7 * attempt)))
        }
        #expect(try #require(latencies.min()) < .seconds(1), "\(latencies)")
        #expect(harness.health("tmux_events")?.status == .active)
        #expect(await send(TrackerCommand.agentEvent(hook: "Stop", arguments: []).line, to: url) == .success)
        #expect(harness.health("agent_events")?.status == .active)

        let before = harness.currentStateText
        let count = harness.samples().count
        harness.advance(5)
        let unknown = await send("frobnicate now", to: url)
        guard case let .error(reason) = unknown else {
            Issue.record("expected an error, got \(unknown)")
            return
        }
        #expect(reason.contains("unknown command"))
        #expect(harness.samples().count == count)
        #expect(harness.currentStateText == before)
        #expect(await send("forget-day yesterday", to: url) != .success)
    }

    /// Two days of blocks: Safari on a domain to exclude, then TextEdit, on 2024-03-13 and 2024-03-14.
    private func twoDays() async throws -> AgentHarness {
        let harness = try AgentHarness()
        for day in ["2024-03-13", "2024-03-14"] {
            let start = try #require(ActivityTimestamp.date("\(day)T09:00:00", timeZone: AgentHarness.zone))
            harness.clock.set(start)
            harness.schedule = TickSchedule(start: start)
            harness.engine.handle(.unlock, at: start)
            let url = "https://news.example.com/story/42"
            harness.frontmost("com.apple.Safari", name: "Safari")
            harness.scripts.results["com.apple.Safari"] = .value("normal\n\(url)\nStory")
            harness.history.safari.append((HistoryVisit(time: start, browser: "safari", url: url, title: "Story"), 0))
            await harness.run(for: 300)
            harness.engine.handle(.lock, at: harness.clock.now)
            harness.engine.handle(.unlock, at: harness.clock.now)
            harness.frontmost("com.apple.TextEdit", name: "TextEdit", title: "Notes \(day)")
            await harness.run(for: 300)
            harness.engine.handle(.lock, at: harness.clock.now)
        }
        return harness
    }

    private func lines(_: AgentHarness, _ folder: URL) throws -> [String] {
        try String(contentsOf: folder.appending(path: "2024-03.jsonl"), encoding: .utf8).split(separator: "\n").map(String.init)
    }

    @Test("TRK-22 reapply-exclusions removes a newly excluded domain from both logs and the samples, other lines byte-identical")
    func reapplyExclusions() async throws {
        let harness = try await twoDays()
        let blocksBefore = try lines(harness, harness.engine.logs.blocksFolder)
        let detailBefore = try lines(harness, harness.engine.logs.detailFolder)
        #expect(harness.blockLogText.contains("news.example.com"))
        let settings = harness.folders.shared.appending(path: "settings.toml")
        try "[privacy]\nexclude_domains = [\"news.example.com\"]\n".write(to: settings, atomically: true, encoding: .utf8)
        #expect(harness.engine.rewrite(.reapplyExclusions(from: "2024-03-14", to: "2024-03-14")) == .success)
        let blocksAfter = try lines(harness, harness.engine.logs.blocksFolder)
        let detailAfter = try lines(harness, harness.engine.logs.detailFolder)
        #expect(blocksAfter.count == blocksBefore.count)
        let changedBlocks = zip(blocksBefore, blocksAfter).filter { $0 != $1 }
        #expect(changedBlocks.count == 1)
        #expect(changedBlocks.first?.0.contains("2024-03-14T09:0") == true)
        #expect(changedBlocks.allSatisfy { !$0.1.contains("news.example.com") })
        let changedDetails = zip(detailBefore, detailAfter).filter { $0 != $1 }
        #expect(changedDetails.count == 1)
        #expect(changedDetails.allSatisfy { !$0.1.contains("news.example.com") })
        // The other day keeps its lines and samples as they were.
        #expect(blocksAfter.contains { $0.contains("2024-03-13T09:0") && $0.contains("news.example.com") })
        let day = try #require(ActivityTimestamp.date("2024-03-14T00:00:00", timeZone: AgentHarness.zone))
        let samplesOfDay = try harness.engine.store.lines(from: day, to: day.addingTimeInterval(86_400))
        #expect(!samplesOfDay.isEmpty)
        #expect(samplesOfDay.allSatisfy { !$0.contains("news.example.com") })
        let samplesBefore = try harness.engine.store.lines(from: .distantPast, to: day)
        #expect(samplesBefore.contains { $0.contains("news.example.com") })
    }

    @Test("TRK-22 TRK-23 a [blocks] change that reapply-exclusions reads first reaches the Blocker at the next tick")
    func reapplyExclusionsKeepsBlockSettings() async throws {
        let harness = try AgentHarness(settings: "[blocks]\nidle_close = \"5m\"\n")
        await harness.engine.tick()
        #expect(harness.engine.blocker.settings.idleClose == 300)
        let url = harness.folders.shared.appending(path: "settings.toml", directoryHint: .notDirectory)
        try "[blocks]\nidle_close = \"2m\"\nsplit_after = \"10m\"\n".write(to: url, atomically: true, encoding: .utf8)
        let line = TrackerCommand.reapplyExclusions(from: "2024-03-14", to: "2024-03-14").line
        #expect(await harness.engine.handle(line: line) == TrackerReply.success.line)
        harness.advance(30)
        await harness.engine.tick()
        #expect(harness.engine.settings.blocks.idleClose == 120)
        #expect(harness.engine.blocker.settings.idleClose == 120)
        #expect(harness.engine.blocker.settings.splitAfter == 600)
    }

    @Test("TRK-22 delete-block and forget-day remove their block or day from both logs and the samples")
    func deleteAndForget() async throws {
        let harness = try await twoDays()
        let blocksBefore = try lines(harness, harness.engine.logs.blocksFolder)
        let target = try #require(harness.blocks.first { $0.localDay == "2024-03-14" })
        let start = ActivityTimestamp.text(target.start, utcOffset: target.utcOffset)
        #expect(harness.engine.rewrite(.deleteBlock(device: AgentHarness.device, start: start)) == .success)
        let afterDelete = try lines(harness, harness.engine.logs.blocksFolder)
        #expect(afterDelete.count == blocksBefore.count - 1)
        #expect(afterDelete.allSatisfy { blocksBefore.contains($0) })
        #expect(!harness.detailLogText.contains("\"s\":\"\(start)\""))
        #expect(try harness.engine.store.rows(from: target.start, to: target.end).isEmpty)
        #expect(harness.engine.rewrite(.deleteBlock(device: AgentHarness.device, start: start)) != .success)

        #expect(harness.engine.rewrite(.forgetDay("2024-03-13")) == .success)
        #expect(!harness.blocks.contains { $0.localDay == "2024-03-13" })
        #expect(!harness.detailLogText.contains("2024-03-13T"))
        let day = try #require(ActivityTimestamp.date("2024-03-13T00:00:00", timeZone: AgentHarness.zone))
        #expect(try harness.engine.store.rows(from: day, to: day.addingTimeInterval(86_400)).isEmpty)
        #expect(harness.blocks.contains { $0.localDay == "2024-03-14" })
    }
}
