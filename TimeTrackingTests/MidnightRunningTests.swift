// A running entry across real midnight: the split is no change of entry,
// and idle time before it stops the chain at the idle start
// (spec_timer.md §5.3, §6.3, §8.3).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct MidnightRunningTests {
    @Test("TM-47 a split at real midnight changes no running entry: no window shows, the prompt and Pomodoro stay, a typed task stays")
    func midnightSplitIsNoChange() async throws {
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
        try await test.store.checkInvariants()
        await app.afterChange()

        let running = try #require(app.timer.running)
        #expect(running.id != first.id && running.rootID == first.id)
        #expect(test.router.calls == calls)
        #expect(app.idle.prompt == prompt)
        #expect(app.pomodoro.state == phase)
        #expect(app.timer.taskText == "Clarify noise model")
        await app.timer.commitTask()
        #expect(try await test.store.entry(first.id)?.task == "Clarify noise model")
        #expect(try await test.store.runningEntry()?.task == "Clarify noise model")
        // The prompt still acts on the chain.
        await app.idle.resolve(.keep)
        #expect(app.idle.prompt == nil)
        #expect(try await test.store.runningEntry()?.id == running.id)
    }
}
