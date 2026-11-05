// A running entry across real midnight: midnight is no change of the entry,
// and idle time before it stops the entry at the idle start
// (timer.md §5.3, §6.3, §8.3).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

/// The state `promptAfterMidnight` sets up.
@MainActor
private struct PromptAfterMidnight {
    let test: TestApp
    let first: TimeEntry
    let idleStart: Date
}

@MainActor
struct MidnightRunningTests {
    @Test("TM-47 real midnight changes no running entry: no window shows, the prompt and Pomodoro stay, a typed task stays")
    func midnightIsNoChange() async throws {
        let test = try await TestApp(now: "2024-03-13T23:30")
        let app = test.app
        app.pomodoro.sleepUntil = { _ in try await Task.sleep(for: .seconds(3600)) }
        app.timer.debounce = { _ in try await Task.sleep(for: .seconds(3600)) }
        app.timer.taskText = "Clarify"
        await app.timer.start()
        let first = try #require(app.timer.running)
        app.perform(.start)
        let phase = app.pomodoro.state
        // Input stops at 23:32; the prompt opens at 23:55 and stays open.
        try test.clock.set(test.date("2024-03-13T23:42:05"))
        await app.idle.sample(idleSeconds: 605, presence: nil)
        try test.clock.set(test.date("2024-03-13T23:55"))
        await app.idle.sample(idleSeconds: 1, presence: nil)
        let prompt = try #require(app.idle.prompt)
        app.settings.focusOnStart = true
        app.settings.focusOnStop = true
        let calls = test.router.calls
        app.timer.taskText = "Clarify noise model"
        app.timer.taskTextChanged()

        try test.clock.set(test.date("2024-03-14T00:05"))
        await app.afterChange()

        #expect(app.timer.running == first)
        #expect(test.router.calls == calls)
        #expect(app.idle.prompt == prompt)
        #expect(app.pomodoro.state == phase)
        #expect(app.timer.taskText == "Clarify noise model")
        await app.timer.commitTask()
        #expect(try await test.store.entry(first.id)?.task == "Clarify noise model")
        await app.idle.resolve(.keep)
        #expect(app.idle.prompt == nil)
        #expect(try await test.store.runningEntry()?.id == first.id)
    }

    @Test("TM-48 Show the Mini Timer doesn't follow a Timer or the main menu, whether the command or the store's event comes first")
    func miniTimerIgnoresWindows() async throws {
        let test = try await TestApp(observing: true)
        let app = test.app
        defer { app.stop() }
        try await test.entry("Review", from: "08:00", to: "08:30")
        app.settings.focusOnStart = true
        app.settings.focusOnStop = true
        await app.timer.start()
        await app.timer.stop()
        await app.timer.continueEntry()
        await app.timer.stop()
        await app.continueCommand(timerKey: false)
        await app.timer.stop()
        await app.afterChange()
        #expect(test.router.calls.isEmpty)
    }

    @Test("TM-48 Show the Mini Timer follows the menu bar, a notification, an intent, and another device")
    func miniTimerFollowsSources() async throws {
        let test = try await TestApp(observing: true)
        let app = test.app
        defer { app.stop() }
        try await test.entry("Review", from: "08:00", to: "08:30")
        app.settings.focusOnStart = true
        app.settings.focusOnStop = true
        await app.continueLatest()
        await app.stopEntry()
        await app.handle(.continueLatest)
        await app.timer.stop()
        #expect(test.router.calls.count == 3)

        let intent = AutomationService(store: test.store, isIntent: true)
        _ = try await intent.start(task: "From Siri", projectID: nil)
        #expect(await eventually { test.router.calls.count == 4 })
        _ = try await intent.stop()
        #expect(await eventually { test.router.calls.count == 5 })

        let phone = try await TimeStore.inMemory(clock: test.clock, timeZone: .current)
        let entry = try await phone.start(projectID: nil, task: "From the iPhone", at: test.clock.now)
        let ref = SyncRecordRef(.timeEntry, entry.id.rawValue)
        try await test.store.applyFetched([#require(try await phone.syncRecord(ref))], deletions: [])
        #expect(await eventually { test.router.calls.count == 6 })
        test.clock.advance(by: 60)
        _ = try await phone.stop(at: test.clock.now)
        try await test.store.applyFetched([#require(try await phone.syncRecord(ref))], deletions: [])
        #expect(await eventually { test.router.calls.count == 7 })
        #expect(test.router.calls == Array(repeating: .showTimer(focusTask: true), count: 7))
    }

    @Test("TM-48 Show the Mini Timer doesn't follow a URL, the tool, the Calendar, idle detection, or deleting the running entry")
    func miniTimerIgnoresOtherChanges() async throws {
        let test = try await TestApp(observing: true)
        let app = test.app
        defer { app.stop() }
        try await test.entry("Review", from: "08:00", to: "08:30")
        app.settings.focusOnStart = true
        app.settings.focusOnStop = true
        let router = URLRouter(app: app, scheme: "timetracking-debug")
        try await router.open(#require(URL(string: "timetracking-debug://start?task=Linked")))
        try await router.open(#require(URL(string: "timetracking-debug://stop")))
        // The tool is another process: the store only reports a change.
        _ = try await test.store.start(projectID: nil, task: "From the tool", at: test.clock.now)
        await app.afterChange()
        await app.idle.systemEvent(.shutdown, at: test.clock.now)
        await app.afterChange()
        #expect(try await test.store.runningEntry() == nil)
        let running = try await test.store.start(projectID: nil, task: "Doomed", at: test.clock.now)
        await app.afterChange()
        try await test.store.delete([running.id])
        await app.afterChange()
        #expect(test.router.calls.isEmpty)
    }

    /// An entry from 23:30, idle since 23:50, and the prompt open at 00:30.
    private func promptAfterMidnight() async throws -> PromptAfterMidnight {
        let test = try await TestApp(now: "2024-03-13T23:30")
        test.app.timer.taskText = "Clarify noise model"
        await test.app.timer.start()
        let first = try #require(test.app.timer.running)
        try test.clock.set(test.date("2024-03-14T00:00:05"))
        await test.app.idle.sample(idleSeconds: 605, presence: nil)
        try test.clock.set(test.date("2024-03-14T00:30"))
        await test.app.afterChange()
        await test.app.idle.sample(idleSeconds: 1, presence: nil)
        let idleStart = try test.date("2024-03-13T23:50")
        #expect(test.app.idle.prompt?.idleStart == idleStart)
        return PromptAfterMidnight(test: test, first: first, idleStart: idleStart)
    }

    @Test("TM-49 idle from before midnight: Discard stops the entry at the idle start")
    func discardBeforeMidnight() async throws {
        let prompted = try await promptAfterMidnight()
        let (test, first, idleStart) = (prompted.test, prompted.first, prompted.idleStart)
        await test.app.idle.resolve(.discard)
        #expect(try await test.store.entry(first.id)?.end == idleStart)
        #expect(try await test.store.runningEntry() == nil)
    }

    @Test("TM-49 Discard and Continue stops at the idle start and starts the same task now")
    func continueBeforeMidnight() async throws {
        let prompted = try await promptAfterMidnight()
        let (test, first, idleStart) = (prompted.test, prompted.first, prompted.idleStart)
        await test.app.idle.resolve(.discardAndContinue)
        #expect(try await test.store.entry(first.id)?.end == idleStart)
        let current = try #require(try await test.store.runningEntry())
        #expect(current.start == test.clock.now)
        #expect(current.task == "Clarify noise model" && current.id != first.id)
    }

    @Test("TM-49 Keep leaves the entry running")
    func keepBeforeMidnight() async throws {
        let prompted = try await promptAfterMidnight()
        await prompted.test.app.idle.resolve(.keep)
        #expect(try await prompted.test.store.runningEntry() == prompted.first)
    }

    @Test("TM-49 Split stops at the idle start and starts an empty entry there")
    func splitBeforeMidnight() async throws {
        let prompted = try await promptAfterMidnight()
        let (test, first, idleStart) = (prompted.test, prompted.first, prompted.idleStart)
        await test.app.idle.resolve(.split)
        #expect(try await test.store.entry(first.id)?.end == idleStart)
        let current = try #require(try await test.store.runningEntry())
        #expect(current.task.isEmpty && current.projectID == nil)
        #expect(current.start == idleStart)
        #expect(test.router.calls.last == .showTimer(focusTask: true))
    }

    @Test("TM-49 a lock from before midnight stops the entry at the lock time")
    func lockBeforeMidnight() async throws {
        let test = try await TestApp(now: "2024-03-13T23:30")
        test.app.settings.idle.onLockOrSleep = .stop
        await test.app.timer.start()
        let first = try #require(test.app.timer.running)
        try test.clock.set(test.date("2024-03-14T00:30"))
        let lock = try test.date("2024-03-13T23:50")
        await test.app.idle.systemEvent(.lock, at: lock)
        #expect(try await test.store.runningEntry() == nil)
        #expect(try await test.store.entry(first.id)?.end == lock)
    }
}
