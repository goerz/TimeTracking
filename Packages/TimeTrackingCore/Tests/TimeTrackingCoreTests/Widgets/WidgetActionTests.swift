// The widget and control buttons' library side (spec_ios.md §4 item 3, §5,
// §6.1, §6.3).

import Foundation
import Testing
import TimeTrackingCore

struct WidgetActionTests {
    @Test("IOS-18 a widget Stop on an entry known only from LiveState fetches changes first and then stops it")
    func stopAfterFetch() async throws {
        let server = InMemorySyncServer()
        let mac = try await TestStore()
        let entry = try await mac.store.start(projectID: nil, task: "Draft", at: mac.clock.now - 600)
        try await StoreSynchronizer(store: mac.store, transport: server.transport(for: "mac")).sync()

        let phone = try await TestStore()
        let service = AutomationService(store: phone.store, timeZone: phone.zone)
        let phoneSync = StoreSynchronizer(store: phone.store, transport: server.transport(for: "phone"))
        #expect(try await phone.store.entry(entry.id) == nil)
        try await WidgetIntentActions.perform(.stop(expected: entry.id), service: service) {
            try? await phoneSync.sync()
        }
        let stopped = try #require(try await phone.store.entry(entry.id))
        #expect(!stopped.isRunning)
    }

    @Test("IOS-18 if the entry still has not arrived, the stop fails with the iCloud message")
    func stopUnreachable() async throws {
        let phone = try await TestStore()
        let service = AutomationService(store: phone.store, timeZone: phone.zone)
        await #expect(throws: AutomationError.failure(WidgetIntentActions.unreachableMessage)) {
            try await WidgetIntentActions.perform(.stop(expected: EntryID()), service: service) {}
        }
    }

    @Test("IOS-52 the control's off on an entry known only from LiveState fetches changes first and then stops it")
    func toggleOffAfterFetch() async throws {
        let server = InMemorySyncServer()
        let mac = try await TestStore()
        let entry = try await mac.store.start(projectID: nil, task: "Draft", at: mac.clock.now - 600)
        try await StoreSynchronizer(store: mac.store, transport: server.transport(for: "mac")).sync()
        let resolved = try await mac.store.liveState()

        let phone = try await TestStore()
        let service = AutomationService(store: phone.store, timeZone: phone.zone)
        let phoneSync = StoreSynchronizer(store: phone.store, transport: server.transport(for: "phone"))
        #expect(try await phone.store.entry(entry.id) == nil)
        try await WidgetIntentActions.perform(.toggle(false), service: service, resolved: resolved) {
            try? await phoneSync.sync()
        }
        let stopped = try #require(try await phone.store.entry(entry.id))
        #expect(!stopped.isRunning)
    }

    @Test("IOS-52 if the entry still has not arrived, the control's off fails with the iCloud message")
    func toggleOffUnreachable() async throws {
        let mac = try await TestStore()
        _ = try await mac.store.start(projectID: nil, task: "Draft", at: mac.clock.now - 600)
        let resolved = try await mac.store.liveState()
        let phone = try await TestStore()
        let service = AutomationService(store: phone.store, timeZone: phone.zone)
        await #expect(throws: AutomationError.failure(WidgetIntentActions.unreachableMessage)) {
            try await WidgetIntentActions.perform(.toggle(false), service: service, resolved: resolved) {}
        }
    }

    @Test("IOS-52 a local start newer than the widgets' last state wins: the control's off stops it")
    func toggleOffStopsTheNewerEntry() async throws {
        let mac = try await TestStore()
        _ = try await mac.store.start(projectID: nil, task: "Earlier", at: mac.clock.now - 600)
        let stale = try await mac.store.liveState()
        let phone = try await TestStore()
        let service = AutomationService(store: phone.store, timeZone: phone.zone)
        phone.clock.advance(by: 60)
        _ = try await phone.store.start(projectID: nil, task: "Here", at: phone.clock.now)
        try await WidgetIntentActions.perform(.toggle(false), service: service, resolved: stale) {}
        #expect(try await phone.store.runningEntry() == nil)
    }

    @Test("IOS-11 IOS-13 IOS-19 Stop stops the running entry; Continue and the toggle's on continue the latest; off stops")
    func stopAndContinue() async throws {
        let test = try await TestStore()
        let service = AutomationService(store: test.store, timeZone: test.zone)
        let first = try await test.store.start(projectID: nil, task: "First", at: test.clock.now - 3600)
        try await WidgetIntentActions.perform(.stop(expected: first.id), service: service) {}
        #expect(try await test.store.runningEntry() == nil)

        try await WidgetIntentActions.perform(.continueEntry(nil), service: service) {}
        #expect(try await test.store.runningEntry()?.task == "First")
        try await WidgetIntentActions.perform(.toggle(false), service: service) {}
        #expect(try await test.store.runningEntry() == nil)
        try await WidgetIntentActions.perform(.toggle(true), service: service) {}
        #expect(try await test.store.runningEntry()?.task == "First")
        // A stop of an entry that was stopped elsewhere meanwhile does nothing.
        let running = try #require(try await test.store.runningEntry())
        _ = try await test.store.stop(at: test.clock.now)
        _ = try await test.store.start(projectID: nil, task: "Other", at: test.clock.now)
        try await WidgetIntentActions.perform(.stop(expected: running.id), service: service) {}
        #expect(try await test.store.runningEntry()?.task == "Other")
    }

    @Test("IOS-45 a Stop for one entry stops it or its midnight continuation, and never another entry started meanwhile")
    func stopOnlyTheShownChain() async throws {
        let test = try await TestStore()
        let service = AutomationService(store: test.store, timeZone: test.zone)
        // Started before midnight: the running piece is a continuation with another id.
        let overnight = try await test.store.start(projectID: nil, task: "Overnight", at: test.date("2024-03-13T23:00"))
        #expect(try await test.store.runningEntry()?.id != overnight.id)
        #expect(try await service.stop(chainOf: overnight.id) != nil)
        #expect(try await test.store.runningEntry() == nil)
        // Another entry started since the button was drawn keeps running.
        let shown = try await test.store.start(projectID: nil, task: "Shown", at: test.date("2024-03-14T09:00"))
        _ = try await test.store.start(projectID: nil, task: "Started elsewhere", at: test.date("2024-03-14T09:30"))
        #expect(try await service.stop(chainOf: shown.id) == nil)
        #expect(try await test.store.runningEntry()?.task == "Started elsewhere")
        let stopped = try await test.store.transaction { try $0.stop(chainOf: shown.id, at: test.clock.now) }
        #expect(stopped == nil)
    }

    @Test("IOS-14 a pinned button starts its project with the given task, stopping the running entry")
    func startPinned() async throws {
        let test = try await TestStore()
        let made = try await test.structure(projects: ["A", "B"])
        let service = AutomationService(store: test.store, timeZone: test.zone)
        _ = try await test.store.start(projectID: made.projects[0].id, task: "One", at: test.clock.now - 60)
        try await WidgetIntentActions.perform(.start(project: made.projects[1].id, task: "Two"), service: service) {}
        let running = try #require(try await test.store.runningEntry())
        #expect(running.projectID == made.projects[1].id)
        #expect(running.task == "Two")
    }
}
