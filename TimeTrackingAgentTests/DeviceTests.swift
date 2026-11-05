// Tests for the Devices module: iPhone and iPad events merged into `device`
// blocks (activity_tracking.md §2.3, §6.2, §7.2; TRK-8, 11, 26, 28).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct DeviceTests {
    static let phone = "phone-0123456789"

    /// An event of the phone `seconds` after the fixture time.
    static func event(
        _ seconds: TimeInterval,
        _ source: DeviceEvent.Source,
        _ label: String,
        _ kind: String,
        payload: [String: any Sendable] = [:],
        sequence: Int
    ) -> DeviceEvent {
        DeviceEvent(
            deviceID: phone,
            time: ManualClock.fixtureNow(in: AgentHarness.zone).addingTimeInterval(seconds),
            source: source,
            label: label,
            kind: kind,
            payload: DeviceEvent.payloadText(payload),
            sequence: sequence,
            utcOffset: -14_400,
            deviceName: "iPhone"
        )
    }

    /// Ladder minutes `steps` of `label`, step k at `start + 60 k` seconds.
    static func minutes(_ label: String, _ steps: ClosedRange<Int>, start: TimeInterval) -> [DeviceEvent] {
        steps.map { step in
            event(start + TimeInterval(60 * step), .ladder, label, "minute", payload: ["n": step], sequence: step)
        }
    }

    /// A harness whose engine reads `server`.
    static func harness(settings: String? = nil) throws -> (AgentHarness, InMemoryDeviceEventServer) {
        let harness = try AgentHarness(settings: settings)
        let server = InMemoryDeviceEventServer()
        harness.engine.deviceEvents = server.source
        return (harness, server)
    }

    @Test("TRK-28 ladder minutes 1 to 20, a 10 minute gap, and minutes 21 to 30 give two device blocks split at the gap")
    func ladderMinutesSplitAtTheGap() async throws {
        let (harness, server) = try Self.harness()
        let first = Self.minutes("Mail", 1 ... 20, start: 0)
        let second = Self.minutes("Mail", 21 ... 30, start: 600)
        try await server.upload(first + second)
        await harness.syncDevices(at: 3600)
        let blocks = harness.blocks
        #expect(blocks.count == 2)
        #expect(blocks.allSatisfy { $0.deviceNames == ["iPhone"] })
        #expect(blocks.map(\.groupKey) == ["Mail", "Mail"])
        #expect(blocks.map { $0.items.first?.context } == ["Mail", "Mail"])
        #expect(blocks.map { $0.items.first?.subject } == ["Mail", "Mail"])
        #expect(blocks.map(\.activeSeconds) == [1200, 600])
        #expect(blocks[0].start == harness.time(0))
        #expect(blocks[0].end == harness.time(1200))
        #expect(blocks[1].start == harness.time(1800))
        #expect(blocks[1].end == harness.time(2400))
        #expect(harness.blockLogText.contains(#""dev":[["iPhone",1200]]"#))
        #expect(harness.health("device_events")?.status == .active)
        #expect(harness.health("device_events")?.reason.isEmpty == true)
    }

    @Test func lateEventsReplaceTheDaysBlocks() async throws {
        let (harness, server) = try Self.harness()
        try await server.upload(Self.minutes("Mail", 1 ... 10, start: 0))
        await harness.syncDevices(at: 900)
        #expect(harness.blocks.map(\.activeSeconds) == [600])
        let before = harness.blockLogText
        // A fetch with nothing new leaves the file as it was.
        await harness.syncDevices(at: 1200)
        #expect(harness.blockLogText == before)
        try await server.upload(Self.minutes("Mail", 11 ... 15, start: 0))
        await harness.syncDevices(at: 1500)
        #expect(harness.blocks.map(\.activeSeconds) == [900])
        #expect(harness.details.count == 1)
        #expect(try harness.engine.store.deviceEventCount() == 15)
    }

    @Test func namedSetsWinOverEverythingAndEarlyStepsDoNotCount() async throws {
        let (harness, server) = try Self.harness()
        var events = Self.minutes("Everything", 1 ... 10, start: 0)
        events += [3, 4, 5].map { step in
            Self.event(TimeInterval(60 * step), .ladder, "Mail", "minute", payload: ["n": step - 2], sequence: 100 + step)
        }
        events.append(Self.event(61, .ladder, "Everything", "minute", payload: ["n": 5, "early": true], sequence: 200))
        try await server.upload(events)
        await harness.syncDevices(at: 3600)
        let block = try #require(harness.blocks.first)
        #expect(harness.blocks.count == 1)
        #expect(block.activeSeconds == 600)
        let seconds = Dictionary(uniqueKeysWithValues: block.items.map { ($0.context, $0.seconds) })
        #expect(seconds == ["iPhone": 420, "Mail": 180])
    }

    @Test func tabsAutomationsAndTheAppBecomeItems() async throws {
        let (harness, server) = try Self.harness()
        try await server.upload([
            Self.event(0, .intent, "Mail", ActivityEventKind.appOpened.rawValue, sequence: 1),
            Self.event(240, .intent, "Mail", ActivityEventKind.appClosed.rawValue, sequence: 2),
            Self.event(240, .webext, "github.com/owner/repo/pull/12", "tab", sequence: 3),
            Self.event(300, .app, "TimeTracking", "foreground", sequence: 4),
            Self.event(420, .app, "TimeTracking", "background", sequence: 5),
        ])
        await harness.syncDevices(at: 3600)
        let block = try #require(harness.blocks.first)
        #expect(harness.blocks.count == 1)
        let items = block.items.map { "\($0.context) \($0.subject) \($0.detail) \($0.seconds)" }
        #expect(items == ["Mail Mail  240", "safari github.com/owner/repo pull/12 60", "TimeTracking TimeTracking  120"])
        #expect(block.end == harness.time(420))
    }

    @Test func aFocusThatSuspendsCollectionClosesTheBlock() async throws {
        let (harness, server) = try Self.harness()
        var events = Self.minutes("Everything", 1 ... 6, start: 0)
        events.append(Self.event(180, .focus, "Sleep", "on", payload: ["collect": false], sequence: 50))
        try await server.upload(events)
        await harness.syncDevices(at: 3600)
        #expect(harness.blocks.map(\.activeSeconds) == [180, 180])
        #expect(harness.blocks.map(\.end) == [harness.time(180), harness.time(360)])
    }

    @Test("TRK-8 the device merge applies exclude_domains and private_domains to web extension items")
    func theDeviceMergeAppliesTheExclusions() async throws {
        let (harness, server) = try Self.harness(settings: """
        [privacy]
        exclude_domains = ["bank.example"]
        private_domains = ["mail.example"]
        """)
        try await server.upload([
            Self.event(0, .webext, "bank.example/accounts/42", "tab", sequence: 1),
            Self.event(60, .webext, "mail.example/inbox/7", "tab", sequence: 2),
            Self.event(120, .webext, "example.com/docs", "tab", sequence: 3),
        ])
        await harness.syncDevices(at: 3600)
        let output = harness.blockLogText + harness.detailLogText
        #expect(!output.contains("bank.example"))
        #expect(!output.contains("accounts"))
        #expect(!output.contains("inbox"))
        let subjects = harness.details.flatMap(\.items).map(\.subject).sorted()
        #expect(subjects == ["(private)", "example.com", "mail.example"])
    }

    @Test("TRK-11 a device block open at midnight ends at 00:00:00")
    func deviceBlocksEndAtMidnight() async throws {
        let (harness, server) = try Self.harness()
        // 23:54 to 23:59 and a tab at 23:59:30 on the phone; the steps restart after midnight.
        let late = 14 * 3600 - 300.0
        var events = Self.minutes("Everything", 1 ... 5, start: late - 60)
        events.append(Self.event(late + 270, .webext, "example.com/a", "tab", sequence: 9))
        events += (1 ... 5).map { step in
            Self.event(
                14 * 3600 + TimeInterval(60 * step),
                .ladder,
                "Everything",
                "minute",
                payload: ["n": step],
                sequence: 10 + step
            )
        }
        try await server.upload(events)
        await harness.syncDevices(at: 15 * 3600)
        let blocks = harness.blocks
        #expect(blocks.count == 2)
        let days = blocks.map { block in
            [block.start, block.end.addingTimeInterval(-1)].map { ActivityTimestamp.day($0, utcOffset: block.utcOffset) }
        }
        #expect(days == [["2024-03-14", "2024-03-14"], ["2024-03-15", "2024-03-15"]])
        #expect(ActivityTimestamp.text(blocks[0].end, utcOffset: -14_400) == "2024-03-15T00:00:00")
    }

    @Test("TRK-26 merged DeviceEvent records older than 90 days are deleted")
    func oldDeviceEventsArePurged() async throws {
        let (harness, server) = try Self.harness()
        let old = Self.event(-91 * 86_400, .app, "TimeTracking", "foreground", sequence: 1)
        let recent = Self.event(-86_400, .app, "TimeTracking", "foreground", sequence: 2)
        try await server.upload([old, recent])
        await harness.syncDevices(at: 0)
        #expect(await server.all == [recent])
        #expect(try harness.engine.store.deviceEventCount() == 1)
    }

    @Test func withoutCloudKitTheSourceIsOff() async throws {
        let harness = try AgentHarness()
        await harness.syncDevices(at: 0)
        #expect(harness.health("device_events")?.status == .off)
        #expect(harness.currentStateText.contains("iCloud is not available; iPhone and iPad activity doesn't reach this Mac"))
    }

    @Test func aFailedFetchKeepsTheTokenAndReportsIt() async throws {
        struct Offline: Error {}
        let (harness, server) = try Self.harness()
        try await server.upload(Self.minutes("Mail", 1 ... 3, start: 0))
        await server.setFailing(Offline())
        await harness.syncDevices(at: 600)
        #expect(harness.blocks.isEmpty)
        #expect(harness.health("device_events")?.reason == "Couldn't reach iCloud; trying again in 5 minutes")
        await server.setFailing(nil)
        await harness.syncDevices(at: 900)
        #expect(harness.blocks.count == 1)
    }
}
