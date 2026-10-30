// The widget and control buttons as the widget views map them, the live
// elapsed time, and the control's value (spec_ios.md §3.4, §3.5, §5).

import AppIntents
import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingiOS

@MainActor
struct WidgetButtonTests {
    @Test(
        "IOS-13 the Lock Screen buttons stop the running entry and otherwise continue the latest; every family's time counts live"
    )
    func lockScreenButtons() async throws {
        let test = try await TestPhone()
        #expect(WidgetStopIntent.authenticationPolicy == .requiresAuthentication)
        _ = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Latest",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T09:00")
        ))
        let builder = WidgetSnapshotBuilder(store: test.store, timeZone: .current)
        let idle = try await builder.build(at: test.clock.now, live: test.store.liveState(), setupComplete: true)
        #expect(idle.elapsedTimer == nil)
        try await test.model.performWidgetAction(idle.primaryAction, service: AutomationService(store: test.store))
        let running = try #require(test.model.timer.running)
        #expect(running.task == "Latest")

        // Every family's elapsed text runs from the chain start without end,
        // so the system advances it between the timeline's reloads.
        test.clock.advance(by: 754)
        let busy = try await builder.build(at: test.clock.now, live: test.store.liveState(), setupComplete: true)
        let timer = try #require(busy.elapsedTimer)
        #expect(timer.lowerBound == running.start)
        #expect(timer.upperBound == .distantFuture)
        #expect(DurationText.clock(Int(busy.date.timeIntervalSince(timer.lowerBound))) == "0:12:34")
        #expect(busy.primaryAction == .stop(expected: running.id))
        try await test.model.performWidgetAction(busy.primaryAction, service: AutomationService(store: test.store))
        #expect(try await test.store.runningEntry() == nil)
    }

    @Test(
        "IOS-19 the control is on exactly while an entry runs, after local changes, applied syncs, and provider updates"
    )
    func controlReloads() async throws {
        let server = InMemorySyncServer()
        let test = try await TestPhone { store in SynchronizerSync(store: store, transport: server.transport(for: "phone")) }
        #expect(ToggleTimerIntent(value: true).action == .toggle(true))
        #expect(ToggleTimerIntent.authenticationPolicy == .requiresAuthentication)
        #expect(ToggleTimerIntent.allowedExecutionTargets == .main)
        let builder = WidgetSnapshotBuilder(store: test.store, timeZone: .current)
        func control(_ live: LiveState? = nil) async throws -> WidgetControlValue {
            let state = if let live {
                live
            } else {
                try await test.store.liveState()
            }
            return await builder.build(at: test.clock.now, live: state, setupComplete: true).control
        }
        #expect(try await control() == WidgetControlValue(isRunning: false, label: "Start"))

        // A local change.
        let before = test.widgets.controlReloads
        test.model.timer.taskText = "Write"
        await test.model.timer.start()
        #expect(test.widgets.controlReloads > before)
        #expect(try await control() == WidgetControlValue(isRunning: true, label: "Write"))
        try await test.model.performWidgetAction(.toggle(false), service: AutomationService(store: test.store))
        #expect(try await control().isRunning == false)

        // An applied sync of a start on the Mac.
        let macClock = try ManualClock(TestPhone.date("2024-03-14T09:50"))
        let mac = try await TimeStore.inMemory(clock: macClock, timeZone: .current)
        _ = try await mac.start(projectID: nil, task: "On the Mac", at: macClock.now)
        try await StoreSynchronizer(store: mac, transport: server.transport(for: "mac")).sync()
        let afterLocal = test.widgets.controlReloads
        await test.model.sync?.fetchNow()
        await test.model.storeChanged(.runningEntry(nil))
        #expect(test.widgets.controlReloads > afterLocal)
        #expect(try await control() == WidgetControlValue(isRunning: true, label: "On the Mac"))

        // A provider update: a LiveState running entry the store does not hold.
        let other = LiveState(running: LiveState.Running(
            entryID: EntryID(),
            projectID: nil,
            task: "",
            projectName: "Household",
            clientName: nil,
            areaColor: nil,
            chainStart: test.clock.now - 60
        ))
        #expect(try await control(other) == WidgetControlValue(isRunning: true, label: "Household"))
        #expect(try await control(LiveState()).isRunning == false)
    }

    @Test("IOS-14 pressing the running project's Pinned button stops it; another project's button starts that project")
    func pinnedPress() async throws {
        let test = try await TestPhone()
        let projects = try await test.projects(["Garden", "Household"])
        try await test.store.set(.pinnedProjectIDs, projects.map(\.id))
        _ = try await test.store.start(projectID: projects[1].id, task: "Dishes", at: test.clock.now - 300)
        let builder = WidgetSnapshotBuilder(store: test.store, timeZone: .current)
        let snapshot = try await builder.build(at: test.clock.now, live: test.store.liveState(), setupComplete: true)
        let runningButton = try #require(snapshot.pinned.first { $0.projectID == projects[1].id })
        #expect(runningButton.isRunning)
        try await test.model.performWidgetAction(snapshot.action(of: runningButton), service: AutomationService(store: test.store))
        #expect(try await test.store.runningEntry() == nil)

        let after = try await builder.build(at: test.clock.now, live: test.store.liveState(), setupComplete: true)
        let garden = try #require(after.pinned.first { $0.projectID == projects[0].id })
        #expect(!garden.isRunning)
        try await test.model.performWidgetAction(after.action(of: garden), service: AutomationService(store: test.store))
        #expect(try await test.store.runningEntry()?.projectID == projects[0].id)
    }
}
