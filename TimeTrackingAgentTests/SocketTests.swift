// The socket's requests: unknown commands, delete-block, forget-day, and
// reapply-exclusions (activity_tracking.md §2.6, §7.3).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct SocketTests {
    static let story = "https://news.example.com/story/42"

    /// Two blocks in TextEdit, 10:00 to 10:12 and 10:18 to 10:30, each ended by a lock.
    private func twoBlocks(_ harness: AgentHarness) async {
        harness.textEdit()
        await harness.workThenLock(for: 720)
        await harness.unlock()
        harness.textEdit("Plan")
        await harness.workThenLock(for: 720)
    }

    /// Three blocks on 2024-03-10, a date before the agent's first start.
    @discardableResult
    private func frozenDate(_ harness: AgentHarness) throws -> String {
        let mail = ActivityItem(app: "Mail", appID: "com.apple.mail", window: "Inbox")
        let news = ActivityItem(
            app: "Safari",
            appID: "com.apple.Safari",
            window: "Story",
            location: Self.story,
            workspace: "news.example.com"
        )
        return try harness.writeDateFile("2024-03-10", [
            AgentHarness.block("2024-03-10T09:00:00", "2024-03-10T09:30:00", mail),
            AgentHarness.block("2024-03-10T10:00:00", "2024-03-10T10:30:00", news),
            AgentHarness.block("2024-03-10T11:00:00", "2024-03-10T11:30:00", mail),
        ])
    }

    @Test("TRK-35 an unknown socket command gets error and changes nothing")
    func unknownCommand() async throws {
        let harness = try AgentHarness()
        await twoBlocks(harness)
        let url = harness.root.appending(path: "Group/tracker.sock", directoryHint: .notDirectory)
        let server = SocketServer(url: url) { [harness] line in await harness.agent.handle(line: line) }
        try server.start()
        defer { server.stop() }
        let output = harness.allOutput
        let deleted = try harness.agent.store.meta(.deletedRanges)
        harness.advance(5)
        let reply = await Task.detached { TrackerSocketClient(socketURL: url, timeout: 5).send(line: "frobnicate now") }.value
        guard case let .error(reason) = reply else {
            Issue.record("expected an error, got \(reply)")
            return
        }
        #expect(reason.contains("frobnicate"))
        #expect(await harness.request("forget-day yesterday").hasPrefix("error"))
        #expect(harness.allOutput == output)
        #expect(try harness.agent.store.meta(.deletedRanges) == deleted)
    }

    @Test(
        "TRK-36 delete-block over two blocks deletes them and their Samples; late DeviceEvents and app usage form no block there"
    )
    func deleteBlock() async throws {
        let harness = try AgentHarness()
        let server = InMemoryDeviceEventServer()
        harness.agent.deviceEvents = server.source
        await twoBlocks(harness)
        let blocks = harness.blocks(AgentHarness.today)
        try #require(blocks.count == 2)
        let first = blocks[0]
        let last = blocks[1]
        let end = ActivityTimestamp.textWithOffset(last.end, utcOffset: last.endUTCOffset)
        #expect(await harness.request("delete-block \(first.id) \(end)") == "ok")
        #expect(harness.blocks(AgentHarness.today).isEmpty)
        #expect(!harness.samples.contains { $0.time >= first.start && $0.time < last.end })
        #expect(try harness.agent.store.meta(.deletedRanges) == [DeletedRange(start: first.start, end: last.end)])

        // The iPhone's Screen Time for that time arrives late, and macOS app usage is read for it.
        try await server.upload(DeviceTests.minutes("Social", 1 ... 20, firstAt: "2024-03-14T10:01:00"))
        await harness.agent.fetchDeviceEvents()
        harness.knowledge.result = .data(
            apps: [KnowledgeAppInterval(start: first.start, end: last.end, bundleID: "com.apple.mail")],
            web: [],
            displayOff: []
        )
        try harness.agent.fillGaps()
        harness.advance(30)
        await harness.drain()
        #expect(!harness.samples.contains { $0.time >= first.start && $0.time < last.end })
        #expect(harness.blocks(AgentHarness.today).isEmpty)
        #expect(harness.agent.choice.log.days().map(\.description) == [AgentHarness.today])
    }

    @Test("TRK-36 on a frozen date, delete-block removes the blocks from the file and leaves the other lines byte-identical")
    func deleteBlockOnAFrozenDate() async throws {
        let harness = try AgentHarness()
        await harness.tick()
        let old = try frozenDate(harness)
        #expect(await harness.request("delete-block 2024-03-10T10:00:00-04:00 2024-03-10T10:30:00-04:00") == "ok")
        let lines = try #require(harness.dateFileText("2024-03-10")).split(separator: "\n")
        let oldLines = old.split(separator: "\n")
        #expect(lines == [oldLines[0], oldLines[1], oldLines[3]])
        #expect(await harness.request("delete-block 2024-03-10T10:00:00-04:00 2024-03-10T10:30:00-04:00").hasPrefix("error nothing at"))
    }

    @Test(
        "TRK-37 reapply-exclusions removes a newly excluded domain from the Samples and frozen files in range, and from the rebuilt dates"
    )
    func reapplyExclusions() async throws {
        let harness = try AgentHarness()
        harness.safari(Self.story, title: "Story")
        await harness.workThenLock(for: 720)
        let old = try frozenDate(harness)
        #expect(harness.blockLogText.contains("news.example.com"))
        #expect(harness.sampleText.contains("news.example.com"))

        try harness.writeSettings("[privacy]\nexclude_domains = [\"news.example.com\"]\n")
        #expect(await harness.request("reapply-exclusions 2024-03-10 2024-03-14") == "ok")
        #expect(!harness.sampleText.contains("news.example.com"))
        #expect(!harness.blockLogText.contains("news.example.com"))
        #expect(!harness.blockLogText.contains("Story"))
        #expect(harness.blocks(AgentHarness.today).count == 1)
        let lines = try #require(harness.dateFileText("2024-03-10")).split(separator: "\n")
        let oldLines = old.split(separator: "\n")
        #expect(lines.count == oldLines.count)
        #expect(zip(lines, oldLines).map { $0 == $1 } == [true, true, false, true])
    }

    @Test("TRK-37 forget-day deletes a date the same way: its Samples up to now, and on a frozen date its blocks")
    func forgetDay() async throws {
        let harness = try AgentHarness()
        await twoBlocks(harness)
        try frozenDate(harness)
        #expect(harness.blocks(AgentHarness.today).count == 2)
        #expect(await harness.request("forget-day \(AgentHarness.today)") == "ok")
        #expect(harness.blocks(AgentHarness.today).isEmpty)
        #expect(!harness.samples.contains { $0.time < harness.clock.now })
        let start = AgentHarness.instant("2024-03-14T00:00:00")
        #expect(try harness.agent.store.meta(.deletedRanges) == [DeletedRange(start: start, end: harness.clock.now)])

        #expect(await harness.request("forget-day 2024-03-10") == "ok")
        #expect(harness.blocks("2024-03-10").isEmpty)
        #expect(await harness.request("forget-day 2024-03-11").hasPrefix("error nothing at"))
    }
}
