// One timeline: device and synced Safari blocks only cover the time the
// Mac's blocks leave free (spec_activity_tracking.md §2.8, TRK-40).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct TimelineTests {
    /// A harness with the default `min_block` (10 minutes) reading `server`.
    static func harness(settings: String? = nil) throws -> (AgentHarness, InMemoryDeviceEventServer) {
        let harness = try AgentHarness(settings: settings, minBlock: nil)
        let server = InMemoryDeviceEventServer()
        harness.engine.deviceEvents = server.source
        return (harness, server)
    }

    /// The Mac's TextEdit block from the fixture time for `seconds`, closed by a lock.
    static func macBlock(_ harness: AgentHarness, seconds: TimeInterval) async {
        harness.frontmost("com.apple.TextEdit", name: "TextEdit", title: "Notes")
        await harness.run(for: seconds)
        harness.engine.handle(.lock, at: harness.clock.now)
    }

    /// Whether no two blocks of the log share time.
    static func isOneTimeline(_ blocks: [ActivityBlock]) -> Bool {
        let sorted = blocks.sorted { $0.start < $1.start }
        return zip(sorted, sorted.dropFirst()).allSatisfy { $0.end <= $1.start }
    }

    /// The (start, end) of the blocks of `source` other than the Mac's, as seconds after the fixture time.
    static func spans(_ harness: AgentHarness, device: String) -> [[TimeInterval]] {
        harness.blocks.filter { $0.device == device }.sorted { $0.start < $1.start }.map { block in
            [block.start.timeIntervalSince(harness.time(0)), block.end.timeIntervalSince(harness.time(0))]
        }
    }

    @Test("TRK-40 iPhone use from 20 minutes before to 15 after a 20 minute Mac block gives device blocks only before and after it")
    func deviceBlocksAroundTheMac() async throws {
        let (harness, server) = try Self.harness()
        await Self.macBlock(harness, seconds: 1200)
        try await server.upload(DeviceTests.minutes("Everything", 1 ... 55, start: -1200))
        await harness.engine.syncDeviceEvents(now: harness.time(2400))
        #expect(Self.spans(harness, device: "iPhone") == [[-1200, 0], [1200, 2100]])
        #expect(harness.blocks.filter { $0.device == "iPhone" }.map(\.activeSeconds) == [1200, 900])
        #expect(Self.isOneTimeline(harness.blocks))
    }

    @Test("TRK-40 iPhone time left shorter than min_block around a Mac block is dropped, not merged across it")
    func shortDeviceRemaindersAreDropped() async throws {
        let (harness, server) = try Self.harness()
        await Self.macBlock(harness, seconds: 1200)
        try await server.upload(DeviceTests.minutes("Everything", 1 ... 29, start: -240))
        await harness.engine.syncDeviceEvents(now: harness.time(2400))
        #expect(Self.spans(harness, device: "iPhone").isEmpty)
        #expect(harness.blocks.count == 1)
    }

    @Test("TRK-40 a Mac block closing over a device block merged while it was open removes the overlap")
    func macBlockClosesOverADeviceBlock() async throws {
        let (harness, server) = try Self.harness()
        try await server.upload(DeviceTests.minutes("Everything", 1 ... 40, start: -1200))
        harness.frontmost("com.apple.TextEdit", name: "TextEdit", title: "Notes")
        await harness.run(for: 600)
        await harness.engine.syncDeviceEvents(now: harness.clock.now)
        // The open block claims the time up to its last attentive sample.
        #expect(Self.spans(harness, device: "iPhone") == [[-1200, 0], [570, 1200]])
        await harness.run(for: 600)
        harness.engine.handle(.lock, at: harness.clock.now)
        #expect(Self.spans(harness, device: "iPhone") == [[-1200, 0]])
        #expect(Self.isOneTimeline(harness.blocks))
        #expect(harness.details.count == 2)
    }

    @Test("TRK-40 synced Safari visits during a Mac block form no block; a remote block the Mac block overlaps keeps its free part")
    func syncedSafariAroundTheMac() async throws {
        let (harness, _) = try Self.harness(settings: "[devices]\nsynced_safari_history = true\n")
        let remote = ActivityBlock(
            start: harness.time(-600),
            end: harness.time(900),
            activeSeconds: 1500,
            device: "remote",
            groupKey: "example.com",
            groupShare: 1,
            items: [ActivityItem(context: "safari", subject: "example.com", detail: "", seconds: 1500)],
            utcOffset: -14_400
        )
        let closed = ClosedBlock(block: remote, detailItems: remote.items, contexts: ["safari": "com.apple.Safari"])
        try harness.engine.logs.appendSummary(closed)
        await Self.macBlock(harness, seconds: 1200)
        #expect(Self.spans(harness, device: "remote") == [[-600, 0]])
        #expect(harness.blocks.first { $0.device == "remote" }?.activeSeconds == 600)
        #expect(harness.details.first { $0.blockID.hasPrefix("remote/") }?.items.map(\.seconds) == [600])

        harness.history.safari = stride(from: 600, through: 2400, by: 60).map { second in
            let time = harness.time(TimeInterval(second))
            return (HistoryVisit(time: time, browser: "safari", url: "https://example.com/b", title: ""), 1)
        }
        harness.engine.collectSyncedSafari(now: harness.time(3000))
        let spans = Self.spans(harness, device: "remote")
        #expect(spans.count == 2)
        #expect(spans.last?.first == 1200)
        #expect(Self.isOneTimeline(harness.blocks))
    }
}
