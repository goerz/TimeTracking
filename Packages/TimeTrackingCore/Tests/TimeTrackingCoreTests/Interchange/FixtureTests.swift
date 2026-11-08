// Store fixtures, store location, and the change notification
// (architecture.md §1.5, §3.4; data_and_sync.md §2.2, §9 item 14, §9.1).

import Foundation
import Testing
import TimeTrackingCore

struct FixtureTests {
    private static let debugIdentity = AppIdentity(
        appID: "com.example.timetracking.debug",
        bundleID: "com.example.timetracking",
        teamID: "TEAM000000",
        appGroup: "TEAM000000.com.example.timetracking.debug",
        cloudKitContainer: "iCloud.com.example.timetracking.debug",
        urlScheme: "timetracking-debug"
    )

    @Test("The committed store fixtures equal the generator's output", arguments: ["empty", "small", "running"])
    func committedFixturesAreCurrent(name: String) async throws {
        let dataset = try #require(SyntheticDataset.fixture(named: name))
        let generated = try await dataset.exportDocument()
        let url = try #require(StoreFixture.url(named: name), "run scripts/make_fixtures.swift")
        let committed = try Data(contentsOf: url)
        #expect(String(decoding: committed, as: UTF8.self).trimmingCharacters(in: .newlines) == String(decoding: generated, as: UTF8.self))
    }

    @Test("DATA-14 consistencyIssues reports orphans, unknown projects, duplicates, a future running entry; nothing on small")
    func consistency() async throws {
        let small = try await #require(SyntheticDataset.fixture(named: "small")).populatedStore()
        #expect(try await small.consistencyIssues().isEmpty)

        let test = try await TestStore()
        let made = try await test.structure(projects: ["Paper"])
        let unknown = ProjectID()
        let gone = EntryID()
        let running = EntryID()
        let duplicate = ProjectID()
        let records = try [
            SyncRecord(ref: SyncRecordRef(.timeEntry, gone.rawValue), fields: [
                "projectID": .string(unknown.rawValue), "task": .string(""), "start": .date(test.date("2024-03-14T08:00")),
                "end": .date(test.date("2024-03-14T08:30")), "timeZone": .string("Europe/Berlin"),
                "deviceID": .string(DeviceID().rawValue), "modifiedAt": .date(test.clock.now),
            ]),
            SyncRecord(ref: SyncRecordRef(.timeEntry, running.rawValue), fields: [
                "task": .string(""), "start": .date(test.clock.now + 360), "timeZone": .string("Europe/Berlin"),
                "deviceID": .string(DeviceID().rawValue), "modifiedAt": .date(test.clock.now),
            ]),
            SyncRecord(ref: SyncRecordRef(.project, duplicate.rawValue), fields: [
                "areaID": .string(made.area.id.rawValue), "name": .string("paper"), "modifiedAt": .date(test.clock.now),
            ]),
        ]
        try await test.store.applyFetched(records, deletions: [])
        let orphan = try await test.store.createProject(ProjectDraft(areaID: made.area.id, name: "Orphan"))
        let areaTombstone = SyncRecord(ref: SyncRecordRef(.area, made.area.id.rawValue), fields: [
            "clientID": .string(made.client.id.rawValue), "name": .string("Research"), "color": .string("#2E8BC0"),
            "modifiedAt": .date(test.clock.now + 1), "deletedAt": .date(test.clock.now),
        ])
        try await test.store.applyFetched([areaTombstone], deletions: [])
        let issues = try await test.store.consistencyIssues()
        #expect(issues.contains(.runningInFuture(running, start: test.clock.now + 360)))
        #expect(issues.contains(.unknownProject(gone, projectID: unknown)))
        #expect(issues.contains(.projectWithoutArea(orphan.id, areaID: made.area.id)))
        #expect(issues.contains { issue in
            if case let .duplicateName(.project, _, ids) = issue {
                return Set(ids) == [made.projects[0].id.uuid, duplicate.uuid]
            }
            return false
        })
    }

    @Test("ARCH-17 -UITesting YES -Fixture running gives an in-memory store with the fixture, 25 minutes running at 10:00 local")
    func uiTestingFixture() async throws {
        for zoneName in ["Asia/Tokyo", "America/Los_Angeles"] {
            let zone = try #require(TimeZone(identifier: zoneName))
            let clock = ManualClock.fixture(in: zone)
            let arguments = LaunchArguments(arguments: ["app", "-UITesting", "YES", "-Fixture", "running"], environment: [:])
            let store = try await TimeStore.open(
                arguments: arguments,
                identity: Self.debugIdentity,
                deviceID: DeviceID(),
                clock: clock,
                timeZone: { zone }
            )
            #expect(store.location == .inMemory)
            let running = try #require(try await store.runningEntry())
            #expect(running.seconds(at: clock.now) == 25 * 60)
            #expect(running.timeZone == zoneName)
            #expect(try await store.clients(includeRetired: true).count == 3)
        }
    }

    @Test("ARCH-19 the Debug identity's store is under its own group container, never the Release one")
    func debugStoreLocation() {
        let location = TimeStore.Location.resolve(arguments: LaunchArguments(), identity: Self.debugIdentity)
        guard case let .file(url) = location else {
            Issue.record("expected a file location, got \(String(describing: location))")
            return
        }
        let container = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Group Containers/TEAM000000.com.example.timetracking.debug/").path
        #expect(url.path.hasPrefix(container))
        #expect(url.path.hasSuffix("Library/Application Support/TimeTracking/store.sqlite"))
        #expect(!url.path.contains("TEAM000000.com.example.timetracking/"))
        let override = LaunchArguments(arguments: [], environment: ["TIMETRACKING_STORE": "/tmp/x.sqlite"])
        #expect(TimeStore.Location.resolve(arguments: override, identity: Self.debugIdentity) == .file(URL(filePath: "/tmp/x.sqlite")))
    }

    @Test(.timeLimit(.minutes(1)))
    func darwinNotificationReachesOtherNotifiers() async {
        let name = "com.example.timetracking.tests.\(UUID().uuidString)"
        let sender = DarwinChangeNotifier(name: name)
        let receiver = DarwinChangeNotifier(name: name)
        var own = sender.notifications().makeAsyncIterator()
        var other = receiver.notifications().makeAsyncIterator()
        sender.post()
        #expect(await other.next() != nil)
        receiver.post()
        #expect(await own.next() != nil)
    }

    @Test func syntheticActivityLog() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let dataset = try #require(SyntheticDataset.fixture(named: "small"))
        try await dataset.activityLog(to: folder.url)
        let reader = FileActivityStore(folders: ActivityFolders(shared: folder.url, local: folder.url, isFallback: true))
        let calendar = try TrackingCalendar(timeZone: #require(TimeZone(identifier: "America/New_York")))
        let blocks = await reader.blocks(in: calendar.interval(of: dataset.days), devices: nil)
        #expect(blocks.count > 40)
        #expect(Set(blocks.map(\.utcOffset)).count >= 2)
    }
}
