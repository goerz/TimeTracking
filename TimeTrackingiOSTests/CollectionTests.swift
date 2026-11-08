// Tests for the app's side of the activity collection: the flush from the
// wrapper intents, Screen Time denied, the app's own lines, and the iPad
// never writing the block log (ios.md §6.1, §9, §10.4).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingiOS

/// A TestPhone with a real CollectionModel over a temporary folder and an
/// in-memory server.
@MainActor
struct CollectionPhone {
    let test: TestPhone
    let collection: CollectionModel
    let server: InMemoryDeviceEventServer
    let monitor: RecordingScreenTimeMonitor
    let root: URL

    init(screenTime: ScreenTimeStatus = .denied, settings: PhoneSettings = .ephemeral()) async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CollectionTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let folders = ActivityFolders(
            shared: root.appending(path: "iCloud/Activity", directoryHint: .isDirectory),
            local: root.appending(path: "Group/Activity", directoryHint: .isDirectory)
        )
        let server = InMemoryDeviceEventServer()
        let monitor = RecordingScreenTimeMonitor()
        let defaults = try #require(UserDefaults(suiteName: "CollectionTests.\(UUID().uuidString)"))
        var made: CollectionModel?
        self.test = try await TestPhone(settings: settings, collection: { clock, shared in
            let collection = CollectionModel.local(
                folder: folders.local,
                defaults: defaults,
                shared: shared,
                clock: clock,
                server: server,
                screenTime: screenTime,
                monitor: monitor,
                folders: folders
            )
            made = collection
            return collection
        })
        self.collection = try #require(made)
        self.server = server
        self.monitor = monitor
        self.root = root
    }

    /// The uploaded lines as `source kind label`.
    var uploaded: [String] {
        get async {
            await server.all.map { "\($0.source.rawValue) \($0.kind) \($0.label)" }
        }
    }
}

@MainActor
struct CollectionTests {
    @Test("IOS-31 a wrapper intent flushes only when the last flush is more than 5 minutes old")
    func wrapperIntentsFlushAfterFiveMinutes() async throws {
        let phone = try await CollectionPhone()
        phone.collection.setEnabled(true)
        try phone.collection.log.logIntent(label: "Mail", kind: .appOpened)
        let service = AutomationService(store: phone.test.store)
        phone.test.shared.lastFlushAt = phone.test.clock.now.addingTimeInterval(-60)
        try await phone.test.model.performWidgetAction(.start(project: nil, task: "Reading"), service: service)
        #expect(await phone.server.all.isEmpty)
        phone.collection.refresh()
        #expect(phone.collection.pendingCount == 1)
        phone.test.shared.lastFlushAt = phone.test.clock.now.addingTimeInterval(-301)
        try await phone.test.model.performWidgetAction(.stop(expected: nil), service: service)
        #expect(await phone.uploaded == ["intent appOpened Mail"])
        #expect(phone.test.shared.lastFlushAt == phone.test.clock.now)
        #expect(phone.collection.pendingCount == 0)
        // The uploaded events carry the device's name for the Mac's blocks.
        #expect(await phone.server.all.first?.deviceName == "iPhone")
    }

    @Test("IOS-32 with Screen Time authorization denied, every other collector works")
    func screenTimeDeniedLeavesTheOtherCollectors() async throws {
        let phone = try await CollectionPhone(screenTime: .denied)
        let collection = phone.collection
        collection.setEnabled(true)
        await collection.requestAuthorization()
        #expect(collection.screenTime == .denied)
        #expect(phone.monitor.all.isEmpty)
        let log = collection.log
        try log.focusFilterPerformed(label: "Work", collect: true)
        try log.logIntent(label: "Home", kind: .arrived)
        try log.logWeb(url: "https://example.com/docs?x=1", at: nil, exclusions: .empty)
        await collection.appMoved(toForeground: true)
        #expect(await phone.uploaded == [
            "focus on Work",
            "intent arrived Home",
            "webext tab example.com/docs",
            "app foreground TimeTracking",
        ])
    }

    @Test func approvedScreenTimeRegistersTheThresholdsAndMeasuresTheCap() async throws {
        let phone = try await CollectionPhone(screenTime: .approved)
        let collection = phone.collection
        collection.setEnabled(true)
        #expect(collection.state.eventCap == ScreenTimePlan.defaultCap)
        #expect(phone.monitor.all.map(\.setID) == ["everything"])
        let mail = collection.addSet(label: "Mail")
        #expect(phone.monitor.all.suffix(2).map(\.setID) == ["everything", mail.id])
        collection.removeSet(id: ScreenTimeSet.everythingID)
        #expect(collection.sets.map(\.id) == ["everything", mail.id])
        collection.removeSet(id: mail.id)
        #expect(phone.monitor.stops == [mail.id])
        collection.setEnabled(false)
        #expect(phone.monitor.stops.suffix(1) == ["everything"])
    }

    @Test func theAppLogsEachTransitionOnce() async throws {
        let phone = try await CollectionPhone()
        phone.collection.setEnabled(true)
        await phone.test.model.foreground()
        await phone.test.model.foreground()
        await phone.test.model.background()
        // The background flushes only when due; the refresh task always does.
        #expect(await phone.uploaded == ["app foreground TimeTracking"])
        #expect(phone.collection.pendingCount == 1)
        await phone.test.model.refreshTask()
        #expect(await phone.uploaded == ["app foreground TimeTracking", "app background TimeTracking"])
    }

    @Test func nothingIsCollectedWithCollectionOff() async throws {
        let phone = try await CollectionPhone()
        await phone.test.model.foreground()
        try phone.collection.log.logIntent(label: "Mail", kind: .appOpened)
        await phone.collection.flush()
        #expect(await phone.server.all.isEmpty)
    }

    @Test("IOS-36 the iPad never writes to Activity/blocks/")
    func theIPadNeverWritesTheBlockLog() async throws {
        let phone = try await CollectionPhone(settings: .ephemeral(isPad: true))
        let shared = phone.root.appending(path: "iCloud/Activity", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try Data("[privacy]\nexclude_domains = [\"bank.example\"]\n".utf8).write(to: shared.appending(path: "settings.toml"))
        phone.collection.setEnabled(true)
        await phone.test.model.foreground()
        try phone.collection.log.logWeb(url: "https://example.com/a", at: nil, exclusions: .empty)
        try phone.collection.log.focusFilterPerformed(label: "Work", collect: true)
        await phone.test.model.background()
        await phone.test.model.refreshTask()
        await phone.collection.flush()
        #expect(phone.collection.privacy.excludeDomains == ["bank.example"])
        let root = phone.root.resolvingSymlinksInPath().path
        let files = FileManager.default.enumerator(at: phone.root, includingPropertiesForKeys: nil)?.allObjects
            .compactMap { $0 as? URL } ?? []
        let names = files.map { $0.resolvingSymlinksInPath().path.replacingOccurrences(of: root, with: "") }
        #expect(!names.contains { $0.contains("/blocks") })
        #expect(names.contains("/Group/Activity/settings.toml"))
        #expect(await !phone.server.all.isEmpty)
    }
}
