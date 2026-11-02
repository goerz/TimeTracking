// The block log, the detail log, current.json, the shared folder, and
// retention (spec_activity_tracking.md §4).

import Foundation
import Synchronization
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct LogTests {
    @Test("TRK-15 headers start each month file, follow a time zone change, and precede a new context; blocks have every key")
    func headers() async throws {
        let harness = try AgentHarness()
        // Saturday before the DST change of 2024-03-10 in New York.
        let beforeChange = try #require(ActivityTimestamp.date("2024-03-09T10:00:00", timeZone: AgentHarness.zone))
        harness.clock.set(beforeChange)
        harness.schedule = TickSchedule(start: beforeChange)
        harness.frontmost("com.apple.TextEdit", name: "TextEdit", title: "Notes")
        await harness.run(for: 300)
        harness.engine.handle(.lock, at: harness.clock.now)
        let afterChange = try #require(ActivityTimestamp.date("2024-03-10T10:00:00", timeZone: AgentHarness.zone))
        harness.clock.set(afterChange)
        harness.schedule = TickSchedule(start: afterChange)
        harness.engine.handle(.unlock, at: afterChange)
        await harness.run(for: 300)
        harness.engine.handle(.lock, at: harness.clock.now)
        harness.engine.handle(.unlock, at: harness.clock.now)
        harness.frontmost("com.apple.mail", name: "Mail", title: "Inbox")
        await harness.run(for: 300)
        harness.engine.handle(.lock, at: harness.clock.now)
        let april = try #require(ActivityTimestamp.date("2024-04-01T09:00:00", timeZone: AgentHarness.zone))
        harness.clock.set(april)
        harness.schedule = TickSchedule(start: april)
        harness.engine.handle(.unlock, at: april)
        await harness.run(for: 300)
        harness.engine.handle(.lock, at: harness.clock.now)

        let march = try String(contentsOf: harness.engine.logs.blocksFolder.appending(path: "2024-03.jsonl"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(march.count == 6)
        #expect(march[0].hasPrefix("{\"type\":\"header\"") && march[0].contains("\"tz\":\"-05:00\""))
        #expect(march[2].hasPrefix("{\"type\":\"header\"") && march[2].contains("\"tz\":\"-04:00\""))
        #expect(march[4].hasPrefix("{\"type\":\"header\"") && march[4].contains("\"mail\":\"com.apple.mail\"") && march[4]
            .contains("\"textedit\""))
        let aprilLines = try String(contentsOf: harness.engine.logs.blocksFolder.appending(path: "2024-04.jsonl"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(aprilLines.count == 2)
        #expect(aprilLines[0].hasPrefix("{\"type\":\"header\""))
        for line in march + aprilLines where !line.hasPrefix("{\"type\"") {
            let object = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            #expect(Set(object.keys) == ["s", "e", "a", "dev", "g", "gs", "items", "bg", "src"])
        }
    }

    @Test("TRK-39 a short block merged into the previous block replaces its line in the block log and the detail log")
    func shortBlockReplacesTheLine() async throws {
        let harness = try AgentHarness(minBlock: nil)
        harness.frontmost("com.apple.TextEdit", name: "TextEdit", title: "Notes")
        await harness.run(for: 1200)
        harness.engine.handle(.lock, at: harness.clock.now)
        #expect(harness.blocks.count == 1)
        let first = try #require(harness.blocks.first)
        harness.advance(120)
        harness.engine.handle(.unlock, at: harness.clock.now)
        harness.schedule = TickSchedule(start: harness.clock.now)
        harness.frontmost("com.apple.mail", name: "Mail", title: "Inbox")
        await harness.run(for: 240)
        let secondEnd = harness.clock.now
        harness.engine.handle(.lock, at: secondEnd)
        #expect(harness.blocks == [first])
        await harness.run(for: 900)

        let blocks = harness.blocks
        #expect(blocks.count == 1)
        #expect(blocks.first?.id == first.id)
        #expect(blocks.first?.end == secondEnd)
        #expect(Set(blocks.first?.items.map(\.context) ?? []) == ["textedit", "mail"])
        let detailLines = harness.detailLogText.split(separator: "\n").filter { !$0.hasPrefix("{\"type\"") }
        #expect(detailLines.count == 1)
        #expect(harness.details.first?.blockID == first.id)
        #expect(harness.details.first?.presence.contains { $0.state == .locked } == true)
    }

    @Test("TRK-16 the shared folder holds only blocks/ and settings.toml, without urls, files, or presence keys")
    func sharedFolderContents() async throws {
        let harness = try AgentHarness(settings: "[presence]\nidle_after = \"2m\"\n")
        harness.frontmost("com.apple.Safari", name: "Safari")
        harness.scripts.results["com.apple.Safari"] = .value(AgentHarness.fixture("applescript/safari-pull-request.txt"))
        let url = "https://github.com/owner/repo/pull/123?diff=split#discussion"
        let before = HistoryVisit(time: harness.time(-60), browser: "safari", url: url, title: "PR")
        let during = HistoryVisit(time: harness.time(30), browser: "safari", url: url, title: "PR")
        harness.history.safari = [(before, 0), (during, 0)]
        harness.engine.fileChanges.record(
            path: "/Users/alex/Documents/Papers/notes.tex",
            at: harness.time(40),
            context: harness.engine.resolveContext()
        )
        await harness.run(for: 300)
        harness.engine.handle(.lock, at: harness.clock.now)
        let names = try FileManager.default.contentsOfDirectory(atPath: harness.folders.shared.path)
        #expect(Set(names).isSubset(of: ["blocks", "settings.toml"]))
        #expect(!harness.blockLogText.isEmpty)
        for key in ["\"urls\"", "\"files\"", "\"presence\"", "\"dwell\""] {
            #expect(!harness.blockLogText.contains(key))
        }
        let detail = try #require(harness.details.first)
        #expect(detail.urls.contains { $0.url == url })
        #expect(detail.files.map(\.path) == ["~/Documents/Papers/notes.tex"])
        #expect(!detail.presence.isEmpty)
    }

    @Test("TRK-17 a reader polling current.json never sees a partial file")
    func atomicCurrentState() async throws {
        let harness = try AgentHarness()
        await harness.engine.tick()
        let url = harness.engine.logs.currentStateURL
        let zone = AgentHarness.zone
        let reads = Atomic<Int>(0)
        let reader = Task.detached { () -> Int in
            var failures = 0
            while !Task.isCancelled {
                if let data = try? Data(contentsOf: url) {
                    reads.add(1, ordering: .relaxed)
                    if (try? TrackerState.parse(data, timeZone: zone)) == nil {
                        failures += 1
                    }
                }
                await Task.yield()
            }
            return failures
        }
        // Rewrite until the reader has read 200 times while writes go on,
        // however slowly a loaded machine schedules it (at most 100,000 writes).
        var writes = 0
        while reads.load(ordering: .relaxed) < 200, writes < 100_000 {
            harness.advance(1)
            harness.engine.writeCurrentState()
            writes += 1
            await Task.yield()
        }
        reader.cancel()
        let failures = await reader.value
        #expect(reads.load(ordering: .relaxed) >= 200)
        #expect(writes >= 1)
        #expect(failures == 0)
    }

    @Test("TRK-19 after the agent stops, readers report it delayed at 90 seconds and not running at 2 minutes")
    func liveness() async throws {
        let harness = try AgentHarness()
        await harness.run(for: 60)
        let state = try #require(harness.currentState)
        let last = state.health.lastTick
        #expect(state.isRunning(at: last.addingTimeInterval(89)) && !state.isDelayed(at: last.addingTimeInterval(89)))
        #expect(state.isRunning(at: last.addingTimeInterval(90)) && state.isDelayed(at: last.addingTimeInterval(90)))
        #expect(state.isRunning(at: last.addingTimeInterval(119)))
        #expect(!state.isRunning(at: last.addingTimeInterval(120)))
        let store = FileActivityStore(folders: harness.folders, timeZone: AgentHarness.zone, clock: harness.clock)
        let read = await store.currentState()
        #expect(read?.health.lastTick == last)
    }

    @Test(
        "TRK-20 with container writes denied the Mac app's copy matches the local log, settings propagate, shared_folder reports fallback"
    )
    func containerFallback() async throws {
        let harness = try AgentHarness(canWriteShared: false)
        #expect(harness.health("shared_folder")?.status == .fallback)
        #expect(harness.health("shared_folder")?.reason == "Copied to iCloud Drive while the app is open")
        #expect(harness.engine.logs.blocksFolder == harness.folders.localBlocks)
        let mirror = ActivityFolderMirror(local: harness.folders.local, container: harness.folders.shared)
        await harness.run(for: 300)
        harness.engine.handle(.lock, at: harness.clock.now)
        let report = try mirror.sync()
        #expect(report.months == ["2024-03.jsonl"])
        let local = try Data(contentsOf: harness.folders.localBlocks.appending(path: "2024-03.jsonl"))
        let copy = try Data(contentsOf: harness.folders.sharedBlocks.appending(path: "2024-03.jsonl"))
        #expect(local == copy)
        #expect(try mirror.sync().months.isEmpty)

        let containerSettings = harness.folders.shared.appending(path: "settings.toml")
        try "[presence]\nidle_after = \"1m\"\n".write(to: containerSettings, atomically: true, encoding: .utf8)
        #expect(try mirror.sync().settingsFrom == "container")
        harness.presence.reading = PresenceReading(idleSeconds: 90)
        harness.engine.handle(.unlock, at: harness.clock.now)
        #expect(await harness.engine.tick().state == .idle)
    }

    @Test("TRK-26 samples and merged DeviceEvent records older than 90 days are deleted")
    func retention() async throws {
        let harness = try AgentHarness()
        let events = FakeDeviceEvents()
        harness.engine.deviceEvents = events
        let old = harness.time(-91 * 86_400)
        try harness.engine.store.insert(Sample(time: old, state: .idle), utcOffset: -14_400)
        try harness.engine.store.insert(Sample(time: harness.time(-89 * 86_400), state: .idle), utcOffset: -14_400)
        await harness.engine.tick()
        let times = harness.samples().map(\.time)
        #expect(!times.contains(old))
        #expect(times.count == 2)
        // The device events are purged by the device fetch, off the tick.
        await harness.engine.syncDeviceEvents(now: harness.clock.now)
        await harness.engine.syncDeviceEvents(now: harness.clock.now)
        #expect(await events.purges == [harness.time(-90 * 86_400)])
    }
}
