// Widget buttons, controls, push tokens, App Shortcuts, sync, adjustments,
// onboarding, and the URL scheme on iOS (spec_ios.md §3 to §7, §11).

import AppIntents
import Foundation
import Synchronization
import Testing
import TimeTrackingCore
@testable import TimeTrackingiOS

@MainActor
struct WidgetSyncTests {
    @Test("IOS-11 the Now widget's Stop stops the entry in the app process and reloads the widgets, which then show the idle state")
    func widgetStop() async throws {
        let test = try await TestPhone()
        await test.model.timer.start()
        let running = try #require(test.model.timer.running)
        let reloads = test.widgets.timelineReloads
        let intent = WidgetStopIntent(entry: running.id)
        try await test.model.performWidgetAction(intent.action, service: AutomationService(store: test.store))
        #expect(try await test.store.runningEntry() == nil)
        #expect(test.widgets.timelineReloads > reloads)
        #expect(test.shared.lastAppWriteAt == test.clock.now)
        let snapshot = await WidgetSnapshotBuilder(store: test.store, timeZone: .current)
            .build(at: test.clock.now, live: test.shared.liveState ?? LiveState(), setupComplete: true)
        #expect(snapshot.running == nil)
    }

    @Test("IOS-15 a new push token reaches the Device record at the next run; with no widget installed the token becomes nil")
    func pushTokenUpload() async throws {
        let test = try await TestPhone()
        // The push handler with one widget installed.
        test.shared.recordPushToken(Data([0xAB, 0xCD]), widgetCount: 1)
        await test.model.foreground()
        #expect(try await test.store.devices().first { $0.id == test.store.deviceID }?.widgetPushToken == "abcd")
        // The last widget removed: the handler reports no widgets.
        test.shared.recordPushToken(Data([0xAB, 0xCD]), widgetCount: 0)
        #expect(test.shared.pushToken == .some(nil))
        await test.model.foreground()
        #expect(try await test.store.devices().first { $0.id == test.store.deviceID }?.widgetPushToken == nil)
    }

    @Test("IOS-18 a widget Stop of an entry from another device fetches first, then stops it")
    func widgetStopFetches() async throws {
        let server = InMemorySyncServer()
        let macClock = try ManualClock(TestPhone.date("2024-03-14T09:00"))
        let mac = try await TimeStore.inMemory(clock: macClock, timeZone: .current)
        let entry = try await mac.start(projectID: nil, task: "On the Mac", at: macClock.now)
        try await StoreSynchronizer(store: mac, transport: server.transport(for: "mac")).sync()
        let test = try await TestPhone { store in SynchronizerSync(store: store, transport: server.transport(for: "phone")) }
        try await test.model.performWidgetAction(.stop(expected: entry.id), service: AutomationService(store: test.store))
        #expect(try await test.store.entry(entry.id)?.isRunning == false)
    }

    @Test(
        "IOS-22 shortcut parameters update after creating, renaming, archiving, restoring, and syncing projects"
    )
    func shortcutParameters() async throws {
        let test = try await TestPhone()
        let area = try await test.projects(["Seed"])[0].areaID
        let id = ProjectID()
        let store = test.store
        let operations: [() async throws -> Void] = [
            { _ = try await store.createProject(ProjectDraft(id: id, areaID: area, name: "Paper")) },
            { _ = try await store.updateProject(id, ProjectChange(name: "Paper 2")) },
            { try await store.archive(id) },
            { try await store.restoreProject(id) },
        ]
        for operation in operations {
            let before = test.shortcuts.updates
            let change = try await test.change(after: operation)
            #expect(change == .structure)
            try await test.model.storeChanged(#require(change))
            #expect(test.shortcuts.updates == before + 1)
        }
        // A sync that brings a project from another device.
        let server = InMemorySyncServer()
        let other = try await TimeStore.inMemory(clock: test.clock, timeZone: .current)
        let (client, general) = try await other.createClient(name: "Remote")
        _ = client
        _ = try await other.createProject(ProjectDraft(areaID: general.id, name: "Remote project"))
        try await StoreSynchronizer(store: other, transport: server.transport(for: "other")).sync()
        let before = test.shortcuts.updates
        var iterator = test.store.changes.makeAsyncIterator()
        try await StoreSynchronizer(store: test.store, transport: server.transport(for: "phone")).sync()
        while let change = await iterator.next(), change != .structure {}
        await test.model.storeChanged(.structure)
        #expect(test.shortcuts.updates == before + 1)
    }

    @Test("IOS-23 the silent-push handler finishes within 25 s, runs the fan-out, and calls the completion handler exactly once")
    func silentPush() async {
        let completions = Mutex<[Bool]>([])
        var fannedOut = 0
        let slow = SilentPushHandler(
            fetch: { await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in } },
            fanOut: { fannedOut += 1 },
            sleep: { seconds in #expect(seconds == 25) }
        )
        await slow.handle { inTime in completions.withLock { $0.append(inTime) } }
        #expect(completions.withLock { $0 } == [false])
        #expect(fannedOut == 1)

        let fast = SilentPushHandler(
            fetch: {},
            fanOut: { fannedOut += 1 },
            sleep: { _ in await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in } }
        )
        await fast.handle { inTime in completions.withLock { $0.append(inTime) } }
        #expect(completions.withLock { $0 } == [false, true])
        #expect(fannedOut == 2)
    }

    @Test(
        "IOS-24 an offline change shows at once with the sync pill and syncs at the next connection; the pill disappears"
    )
    func offline() async throws {
        let server = InMemorySyncServer()
        await server.setPartitioned("phone", true)
        let test = try await TestPhone { store in SynchronizerSync(store: store, transport: server.transport(for: "phone")) }
        test.model.timer.taskText = "Offline"
        await test.model.timer.start()
        #expect(test.model.timer.running?.task == "Offline")
        await test.model.storeChanged(.sync(.waitingForNetwork))
        #expect(test.model.syncPill(at: test.clock.now) == "Waiting for the network")

        await server.setPartitioned("phone", false)
        await test.model.sync?.sendNow()
        await test.model.storeChanged(.sync(.idle))
        #expect(test.model.outboxCount == 0)
        #expect(test.model.syncPill(at: test.clock.now) == nil)
        #expect(try await server.record(SyncRecordRef(.timeEntry, #require(test.model.timer.running).id.rawValue)) != nil)
    }

    @Test("IOS-24 sending shows the pill only after 10 seconds")
    func sendingPill() async throws {
        let test = try await TestPhone()
        await test.model.timer.start()
        await test.model.storeChanged(.sync(.sending(2)))
        #expect(test.model.syncPill(at: test.clock.now + 5) == nil)
        #expect(test.model.syncPill(at: test.clock.now + 11) == "Sending 2 changes…")
    }

    @Test(
        "IOS-25 an adjustment of this device's entry shows the banner and badges the row until its sheet opens; a midnight split shows none"
    )
    func adjustments() async throws {
        let test = try await TestPhone()
        let entry = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Mine",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T09:00")
        ))[0]
        let mac = DeviceID()
        var after = entry
        after.end = try test.date("2024-03-14T08:30")
        let split = EntryAdjustment(entryID: entry.id, reason: .splitAtMidnight, before: entry, after: entry, time: test.clock.now)
        await test.model.storeChanged(.adjusted([split]))
        #expect(test.model.banner == nil)

        let stopped = EntryAdjustment(
            entryID: entry.id,
            reason: .stoppedByLaterStart,
            before: entry,
            after: after,
            causingDeviceID: mac,
            time: test.clock.now
        )
        await test.model.storeChanged(.adjusted([stopped]))
        #expect(test.model.banner?.entryID == entry.id)
        #expect(test.model.badged.contains(entry.id))
        let time = try LocalDateText.time(test.date("2024-03-14T08:30"))
        #expect(test.model.explanations[entry.id] == "Stopped at \(time) because an entry started on another device")
        test.model.openEditor(entry.id)
        #expect(!test.model.badged.contains(entry.id))
        #expect(test.model.banner == nil)

        test.model.isActive = false
        await test.model.storeChanged(.adjusted([stopped]))
        #expect(test.scheduler.pending(.syncAdjusted)?.entryID == entry.id.rawValue)
    }

    @Test("IOS-37 without an iCloud account onboarding shows the blocking screen and nothing else")
    func noAccount() async throws {
        let test = try await TestPhone()
        test.settings.onboarded = false
        let onboarding = OnboardingModel(settings: test.settings, shared: test.shared) { .unavailable }
        await onboarding.check()
        #expect(onboarding.step == .noAccount)
        let available = OnboardingModel(settings: test.settings, shared: test.shared) { .available }
        await available.check()
        #expect(available.step == .deviceName)
        available.deviceName = "Test iPhone"
        await available.confirmName(model: test.model)
        #expect(available.step == .done)
        #expect(test.shared.setupComplete)
        #expect(try await test.store.devices().first { $0.id == test.store.deviceID }?.name == "Test iPhone")
    }

    @Test("IOS-37 before the first sync, tracking intents fail with the setup message")
    func setupGate() async throws {
        let test = try await TestPhone()
        test.shared.setupComplete = false
        PhoneIntentBridge.shared.attach(test.model)
        await #expect(throws: AutomationError.failure(WidgetIntentActions.setupMessage)) {
            _ = try await PhoneIntentBridge.shared.service()
        }
    }

    @Test("IOS-38 timetracking://start?project=Household shows the Timer with a running Household entry")
    func urlStart() async throws {
        let test = try await TestPhone()
        let household = try await test.projects(["Garden", "Household"])[1]
        test.model.sheet = .settings
        let router = PhoneURLRouter(model: test.model, scheme: "timetracking")
        let outcome = try await router.open(#require(URL(string: "timetracking://start?project=Household")))
        #expect(outcome == .tracked("Started Household"))
        #expect(test.model.sheet == nil)
        let running = try #require(test.model.timer.running)
        #expect(running.projectID == household.id)
        #expect(test.model.timer.chipLabel.name == "Household")
        #expect(test.model.padTab == .timer)
        let failed = try await router.open(#require(URL(string: "timetracking://delete")))
        if case .failed = failed {} else {
            Issue.record("delete URL did something")
        }
        #expect(test.model.urlAlert != nil)
    }
}
