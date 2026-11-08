// The remote activity loop and the shared block log: DeviceEvents of an
// iPhone fetched and redone per device-date, device names, frozen dates on
// a new Mac, and the source list (activity_tracking.md §2.2, §2.5, §3.5,
// §4.1, §6.2).

import Foundation
import GRDB
import Synchronization
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct DeviceTests {
    static let phone = "phone-0123"

    /// Screen Time threshold `n` of `label` for each step, step k at `firstAt` plus k − 1 minutes.
    static func minutes(_ label: String, _ steps: ClosedRange<Int>, firstAt: String, name: String = "iPhone") -> [DeviceEvent] {
        let first = AgentHarness.instant(firstAt)
        return steps.map { step in
            DeviceEvent(
                deviceID: phone,
                time: first + TimeInterval(60 * (step - steps.lowerBound)),
                source: .screenTime,
                label: label,
                kind: "minute",
                payload: DeviceEvent.payloadText(["n": step]),
                sequence: step,
                utcOffset: AgentHarness.zone.secondsFromGMT(for: first),
                deviceName: name
            )
        }
    }

    /// A harness whose agent fetches from a server in memory.
    static func harness(settings: String? = nil) throws -> (AgentHarness, InMemoryDeviceEventServer) {
        let harness = try AgentHarness(settings: settings)
        let server = InMemoryDeviceEventServer()
        harness.agent.deviceEvents = server.source
        return (harness, server)
    }

    /// Uploads `events`, then lets the agent fetch them and form blocks.
    static func sync(_ harness: AgentHarness, _ server: InMemoryDeviceEventServer, _ events: [DeviceEvent]) async throws {
        try await server.upload(events)
        await harness.agent.fetchDeviceEvents()
        await harness.drain()
    }

    private func phoneSamples(_ harness: AgentHarness, on day: String) -> [Sample] {
        let start = AgentHarness.instant("\(day)T00:00:00")
        return harness.samples.filter { $0.deviceID == Self.phone && $0.time >= start && $0.time < start + 86_400 }
    }

    @Test(
        "TRK-17 a new DeviceEvent replaces the device's iOS Samples of its date; a fetch without new events marks no date"
    )
    func newEventsReplaceTheDate() async throws {
        let (harness, server) = try Self.harness()
        try harness.startedOn("2024-03-01")
        try await Self.sync(
            harness,
            server,
            Self.minutes("Social", 1 ... 5, firstAt: "2024-03-13T08:01:00") + Self.minutes(
                "Social",
                1 ... 10,
                firstAt: "2024-03-14T08:01:00"
            )
        )
        let yesterday = phoneSamples(harness, on: "2024-03-13")
        // One Sample per threshold minute, at its start.
        #expect(yesterday.count == 5)
        let first = phoneSamples(harness, on: AgentHarness.today)
        #expect(first.first?.time == AgentHarness.instant("2024-03-14T08:00:00"))
        #expect(first.last?.time == AgentHarness.instant("2024-03-14T08:09:00"))
        #expect(first.allSatisfy { $0.source == .screenTime && $0.foreground?.app == "Social" })

        try await Self.sync(harness, server, Self.minutes("Social", 11 ... 15, firstAt: "2024-03-14T08:11:00"))
        let second = phoneSamples(harness, on: AgentHarness.today)
        #expect(second.first?.time == AgentHarness.instant("2024-03-14T08:00:00"))
        #expect(second.last?.time == AgentHarness.instant("2024-03-14T08:14:00"))
        #expect(second.count == 15)
        #expect(phoneSamples(harness, on: "2024-03-13") == yesterday)
        #expect(harness.blocks(AgentHarness.today).first?.foreground.map(\.device) == ["iPhone"])

        // Nothing new: no write marks a date.
        let marks = Mutex<[Set<TrackingDay>]>([])
        let observation = DatabaseRegionObservation(tracking: Table("meta"))
        let cancellable = observation.start(
            in: harness.agent.store.database,
            onError: { _ in },
            onChange: { database in
                let days = (try? database.meta(.changedDays)) ?? []
                marks.withLock { $0.append(days) }
            }
        )
        await harness.agent.fetchDeviceEvents()
        await harness.drain()
        cancellable.cancel()
        let recorded = marks.withLock { $0 }
        #expect(!recorded.isEmpty)
        let unmarked = recorded.allSatisfy(\.isEmpty)
        #expect(unmarked)
        #expect(phoneSamples(harness, on: AgentHarness.today) == second)
        #expect(try harness.agent.store.meta(.pendingRemoteDays)?.isEmpty ?? true)
    }

    @Test("TRK-59 renaming an iPhone changes its name in every rebuilt block, also of dates without new events")
    func renamedDevice() async throws {
        let (harness, server) = try Self.harness()
        try harness.startedOn("2024-03-01")
        try await Self.sync(
            harness,
            server,
            Self.minutes("Social", 1 ... 20, firstAt: "2024-03-13T08:01:00") + Self.minutes(
                "Social",
                1 ... 20,
                firstAt: "2024-03-14T08:01:00"
            )
        )
        let days = ["2024-03-13", AgentHarness.today]
        for day in days {
            #expect(harness.blocks(day).flatMap(\.foreground).map(\.device) == ["iPhone"], "\(day)")
        }

        try await Self.sync(harness, server, Self.minutes("Social", 21 ... 21, firstAt: "2024-03-14T09:00:00", name: "Alex's iPhone"))
        for day in days {
            let devices = harness.blocks(day).flatMap(\.foreground).map(\.device)
            #expect(!devices.isEmpty && devices.allSatisfy { $0 == "Alex's iPhone" }, "\(day): \(devices)")
        }
        #expect(!harness.blockLogText.contains("\"d\":\"iPhone\""))
    }

    @Test("TRK-64 with synced_safari_history off, synced_safari is not in health.sources; on, it is")
    func syncedSafariSource() async throws {
        let harness = try AgentHarness()
        await harness.tick()
        let ids = try #require(harness.currentState?.health.sources.map(\.id))
        #expect(!ids.contains("synced_safari"))
        #expect(ids.contains("device_events"))

        let enabled = try AgentHarness(settings: "[devices]\nsynced_safari_history = true\n")
        await enabled.agent.fetchDeviceEvents()
        await enabled.drain()
        await enabled.tick()
        #expect(enabled.currentState?.health.sources.map(\.id).contains("synced_safari") == true)
    }

    @Test("TRK-19 off, the remote cycle stores no safariHistory Sample and never opens CloudTabs.db; on, the visits become Samples")
    func syncedSafariVisits() async throws {
        func visits(_ harness: AgentHarness) {
            harness.history.safari = (0 ..< 3).map { index in
                let visit = HistoryVisit(
                    time: harness.time(TimeInterval(-3600 + index * 120)),
                    browser: "safari",
                    url: "https://example.com/\(index)",
                    title: "Page \(index)"
                )
                return (visit, 1)
            }
            harness.history.tabs = [CloudTabDevice(name: "iPhone", urls: ["https://example.com/0"])]
        }
        let disabled = try AgentHarness()
        visits(disabled)
        await disabled.agent.fetchDeviceEvents()
        await disabled.drain()
        #expect(disabled.history.cloudTabsReads == 0)
        #expect(!disabled.samples.contains { $0.source == .safariHistory })

        let enabled = try AgentHarness(settings: "[devices]\nsynced_safari_history = true\n")
        visits(enabled)
        await enabled.agent.fetchDeviceEvents()
        await enabled.drain()
        #expect(enabled.history.cloudTabsReads == 1)
        let synced = enabled.samples.filter { $0.source == .safariHistory }
        // Two minutes per visit but the last, which lasts one; the last Sample of each a minute before its end.
        #expect(synced.count == 3 + 3 + 1)
        #expect(Set(synced.map(\.deviceID)) == [ActivityBlockItem.remoteDevice])
        #expect(enabled.agent.health.status(.syncedSafari) == .active)
    }

    @Test(
        "TRK-65 on a new Mac, dates before the first start are frozen: the first fetch leaves them, reapply-exclusions edits them"
    )
    func frozenDatesOnANewMac() async throws {
        let (harness, server) = try Self.harness()
        let news = ActivityItem(
            app: "Safari",
            appID: "com.apple.Safari",
            location: "https://news.example.com/story/42",
            workspace: "news.example.com"
        )
        let mail = ActivityItem(app: "Mail", appID: "com.apple.mail", window: "Inbox")
        let old = try harness.writeDateFile("2024-03-10", [
            AgentHarness.block("2024-03-10T09:00:00", "2024-03-10T09:30:00", mail),
            AgentHarness.block("2024-03-10T10:00:00", "2024-03-10T10:30:00", news),
            AgentHarness.block("2024-03-10T11:00:00", "2024-03-10T11:30:00", mail),
        ])
        try await Self.sync(harness, server, Self.minutes("Social", 1 ... 20, firstAt: "2024-03-10T08:01:00"))
        #expect(harness.dateFileText("2024-03-10") == old)
        #expect(phoneSamples(harness, on: "2024-03-10").isEmpty)

        try harness.writeSettings("[privacy]\nexclude_domains = [\"news.example.com\"]\n")
        #expect(await harness.request("reapply-exclusions 2024-03-10 2024-03-10") == "ok")
        let edited = try #require(harness.dateFileText("2024-03-10"))
        let before = old.split(separator: "\n")
        let after = edited.split(separator: "\n")
        #expect(after.count == before.count)
        #expect(zip(before, after).filter { $0 != $1 }.count == 1)
        #expect(after[2].contains("(private)"))
        #expect(!edited.contains("news.example.com"))
    }

    @Test(
        "TRK-71 a fetch skips records of another app version, stores the others, and reports device_events fallback; the purge deletes them"
    )
    func unreadableRecordsSkipped() async throws {
        let (harness, server) = try Self.harness()
        await server.uploadUnreadable("old-ladder-1", at: AgentHarness.instant("2024-03-14T08:00:00"))
        try await Self.sync(harness, server, Self.minutes("Social", 1 ... 5, firstAt: "2024-03-14T08:01:00"))
        #expect(harness.samples.contains { $0.deviceID == Self.phone })
        #expect(harness.agent.health.status(.deviceEvents) == .fallback)
        // The token moved past the record: the next fetch doesn't see it again.
        try await Self.sync(harness, server, [])
        #expect(harness.agent.health.status(.deviceEvents) == .active)

        try await server.source.purge(before: AgentHarness.instant("2024-03-15T00:00:00"))
        #expect(await server.unreadableNames.isEmpty)
    }
}
