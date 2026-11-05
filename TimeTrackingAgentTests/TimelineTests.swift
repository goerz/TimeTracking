// One timeline of the user: the Mac, iPhones and iPads, and synced Safari
// history merged into one stream of blocks (activity_tracking.md §2.8,
// TRK-40).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct TimelineTests {
    static let mac = AgentHarness.device

    /// A harness with the default `min_block` (10 minutes) reading `server`.
    static func harness(settings: String? = nil) throws -> (AgentHarness, InMemoryDeviceEventServer) {
        let harness = try AgentHarness(settings: settings, minBlock: nil)
        let server = InMemoryDeviceEventServer()
        harness.engine.deviceEvents = server.source
        return (harness, server)
    }

    /// An event of the iPad `seconds` after the fixture time.
    static func padEvent(_ seconds: TimeInterval, _ kind: String, sequence: Int) -> DeviceEvent {
        DeviceEvent(
            deviceID: "pad-0123456789",
            time: ManualClock.fixtureNow(in: AgentHarness.zone).addingTimeInterval(seconds),
            source: .app,
            label: "TimeTracking",
            kind: kind,
            payload: DeviceEvent.payloadText([:]),
            sequence: sequence,
            utcOffset: -14_400,
            deviceName: "iPad"
        )
    }

    /// Whether no two blocks share time.
    static func isOneTimeline(_ blocks: [ActivityBlock]) -> Bool {
        let sorted = blocks.sorted { $0.start < $1.start }
        return zip(sorted, sorted.dropFirst()).allSatisfy { $0.end <= $1.start }
    }

    /// The device shares of `block` as `[name: seconds]`.
    static func shares(_ block: ActivityBlock?) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: (block?.devices ?? []).map { ($0.name, $0.seconds) })
    }

    @Test("TRK-40 Mac work, 5 minutes on the iPhone while the Mac is locked, and Mac work again form one block of both devices")
    func iPhoneBetweenMacWork() async throws {
        let (harness, server) = try Self.harness()
        harness.frontmost("com.apple.TextEdit", name: "TextEdit", title: "Notes")
        await harness.run(for: 900)
        harness.engine.handle(.lock, at: harness.clock.now)
        try await server.upload(DeviceTests.minutes("Everything", 1 ... 5, start: 900))
        harness.advance(300)
        await harness.engine.syncDeviceEvents(now: harness.clock.now)
        harness.engine.handle(.unlock, at: harness.clock.now)
        harness.schedule = TickSchedule(start: harness.clock.now)
        await harness.run(for: 900)
        harness.engine.handle(.lock, at: harness.clock.now)
        await harness.run(for: 900)

        let block = try #require(harness.blocks.first)
        #expect(harness.blocks.count == 1)
        #expect(block.start == harness.time(0))
        #expect(block.end == harness.time(2100))
        #expect(Self.shares(block) == [Self.mac: 1800, "iPhone": 300])
        #expect(block.deviceNames.first == Self.mac)
        #expect(block.items.contains { $0.context == "iPhone" && $0.subject.isEmpty && $0.device == "iPhone" && $0.seconds == 300 })
        #expect(harness.blockLogText.contains(#"["iPhone","","",300,"iPhone"]"#))
        #expect(!harness.blockLogText.contains("Everything"))
    }

    @Test("TRK-40 iPhone use while the Mac has attention is a background item and adds no active time")
    func iPhoneDuringMacWork() async throws {
        let (harness, server) = try Self.harness()
        try await server.upload(DeviceTests.minutes("Everything", 1 ... 10, start: 300))
        await harness.engine.syncDeviceEvents(now: harness.clock.now)
        harness.frontmost("com.apple.TextEdit", name: "TextEdit", title: "Notes")
        await harness.run(for: 1200)
        harness.engine.handle(.lock, at: harness.clock.now)

        let block = try #require(harness.blocks.first)
        #expect(harness.blocks.count == 1)
        #expect(Self.shares(block) == [Self.mac: 1200])
        #expect(block.activeSeconds == 1200)
        #expect(block.background.map { "\($0.context) \($0.device) \($0.seconds)" } == ["iPhone iPhone 600"])
    }

    @Test("TRK-40 overlapping iPhone and iPad use forms one block in which the more specific iPad app wins its minutes")
    func iPhoneAndIPad() async throws {
        let (harness, server) = try Self.harness()
        try await server.upload(DeviceTests.minutes("Everything", 1 ... 20, start: -1200) + [
            Self.padEvent(-600, "foreground", sequence: 1),
            Self.padEvent(-300, "background", sequence: 2),
        ])
        await harness.syncDevices(at: 600)

        let block = try #require(harness.blocks.first)
        #expect(harness.blocks.count == 1)
        #expect(block.start == harness.time(-1200))
        #expect(block.end == harness.time(0))
        #expect(Self.shares(block) == ["iPhone": 900, "iPad": 300])
        #expect(harness.details.count == 1)
    }

    @Test("TRK-40 synced Safari history fills only time no iPhone stretch claims")
    func syncedSafariBelowTheIPhone() async throws {
        let (harness, server) = try Self.harness(settings: "[devices]\nsynced_safari_history = true\n")
        try await server.upload(DeviceTests.minutes("Everything", 1 ... 10, start: -1800))
        await harness.engine.syncDeviceEvents(now: harness.clock.now)
        harness.history.safari = stride(from: -1500, through: -900, by: 60).map { second in
            let time = harness.time(TimeInterval(second))
            return (HistoryVisit(time: time, browser: "safari", url: "https://example.com/b", title: ""), 1)
        }
        harness.engine.collectSyncedSafari(now: harness.time(600))

        let block = try #require(harness.blocks.first)
        #expect(harness.blocks.count == 1)
        #expect(block.start == harness.time(-1800))
        #expect(block.end == harness.time(-900))
        #expect(Self.shares(block) == ["iPhone": 600, ActivityDeviceTime.remote: 300])
    }

    @Test("TRK-40 a deleted block stays deleted when late iPhone events for its time arrive")
    func deletedTimeStaysDeleted() async throws {
        let (harness, server) = try Self.harness()
        try await server.upload(DeviceTests.minutes("Everything", 1 ... 20, start: -1800))
        await harness.engine.syncDeviceEvents(now: harness.clock.now)
        let block = try #require(harness.blocks.first)
        let start = ActivityTimestamp.text(block.start, utcOffset: block.utcOffset)
        #expect(harness.engine.rewrite(.deleteBlock(start: start)) == .success)
        #expect(harness.blocks.isEmpty)
        try await server.upload(DeviceTests.minutes("Mail", 1 ... 15, start: -1800))
        await harness.engine.syncDeviceEvents(now: harness.clock.now)
        #expect(harness.blocks.isEmpty)
        #expect(Self.isOneTimeline(harness.blocks))
    }

    @Test("TRK-40 a tick that continues from the checkpoint forms the same blocks as a run over the whole day")
    func checkpointsMatchAFullRun() {
        let start = ManualClock.fixtureNow(in: AgentHarness.zone)
        let parts: [(String?, TimeInterval)] = [("a", 1500), (nil, 420), ("b", 240), (nil, 900), ("a", 2400), ("c", 1500), (nil, 600)]
        let samples = BlockerTests.stream(parts, from: start)
        let phone = TimelineStretch(
            start: start.addingTimeInterval(1600),
            end: start.addingTimeInterval(2500),
            item: SampleItem(context: "Everything", subject: "Everything", groupKey: "Everything", app: "ladder"),
            device: "iPhone",
            rank: 1
        )
        var settings = TrackerBlockSettings()
        settings.minBlock = 600
        var inputs = TimelineInputs(others: [phone])
        var checkpoint: Timeline.Checkpoint?
        var incremental = Timeline.Result(closed: [], open: nil)
        for sample in samples {
            inputs.mac.append(sample)
            (incremental, checkpoint) = Timeline.run(
                inputs,
                settings: settings,
                timeZone: AgentHarness.zone,
                mac: Self.mac,
                flush: false,
                until: sample.time,
                checkpoint: checkpoint
            )
        }
        let zone = AgentHarness.zone
        let (full, _) = Timeline.run(inputs, settings: settings, timeZone: zone, mac: Self.mac, flush: false, until: samples.last?.time)
        #expect(checkpoint != nil)
        #expect(incremental.closed == full.closed)
        #expect(incremental.open == full.open)
        #expect(full.closed.count >= 2)
        #expect(full.closed.contains { $0.block.deviceNames.contains("iPhone") })
    }
}
