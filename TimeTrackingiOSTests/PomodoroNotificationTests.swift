// The iOS Pomodoro and the notifications (spec_ios.md §2.8, §8).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingiOS

@MainActor
struct PomodoroNotificationTests {
    @Test(
        "IOS-9 a Pomodoro schedules focusDone at focusEnd; continuing keeps it; stopping ends it and removes notifications"
    )
    func pomodoroLifecycle() async throws {
        let test = try await TestPhone()
        let earlier = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Earlier",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T08:30")
        ))[0]
        await test.model.timer.start()
        test.model.pomodoro.perform(.start, isRunning: true)
        let focusEnd = test.clock.now + 25 * 60
        #expect(test.model.pomodoro.state == .focus(end: focusEnd))
        let scheduled = try #require(test.scheduler.pending(.pomodoroFocusDone))
        #expect(scheduled.date == focusEnd)
        #expect(scheduled.title == "Focus done")

        test.clock.advance(by: 60)
        await test.model.timer.continueEntry(earlier.id)
        await test.model.localWrite()
        #expect(test.model.pomodoro.state == .focus(end: focusEnd))
        #expect(test.scheduler.pending(.pomodoroFocusDone)?.date == focusEnd)

        // A stop on another device arrives as a store change.
        _ = try await test.store.stop(at: test.clock.now)
        await test.model.storeChanged(.runningEntry(nil))
        #expect(test.model.pomodoro.state == .off)
        #expect(test.scheduler.pending(.pomodoroFocusDone) == nil)
        #expect(test.scheduler.removed.contains(.pomodoroFocusDone))
    }

    @Test(
        "IOS-10 a relaunch keeps the Pomodoro and notification; after focusEnd it shows Start Break; replay changes no entry"
    )
    func relaunchReplay() async throws {
        let settings = PhoneSettings.ephemeral()
        let scheduler = RecordingScheduler()
        let first = try await TestPhone(settings: settings, scheduler: scheduler)
        await first.model.timer.start()
        first.model.pomodoro.perform(.start, isRunning: true)
        let focusEnd = first.clock.now + 25 * 60
        let entries = try await first.store.entries(in: DateInterval(start: .distantPast, end: .distantFuture), includeDeleted: true)

        let second = try await TestPhone(store: first.store, settings: settings, scheduler: scheduler)
        #expect(second.model.pomodoro.state == .focus(end: focusEnd))
        #expect(scheduler.pending(.pomodoroFocusDone)?.date == focusEnd)

        second.clock.set(focusEnd + 60)
        second.model.pomodoro.replay(isRunning: true)
        #expect(second.model.pomodoro.state == .focusOver(end: focusEnd))
        #expect(second.model.pomodoro.pomodoro.confirmationTitle == "Start Break")
        let after = try await second.store.entries(in: DateInterval(start: .distantPast, end: .distantFuture), includeDeleted: true)
        #expect(after == entries)
    }

    @Test("IOS-26 longRunning fires at the chain start plus N hours, also for an entry started on the Mac; Keep reschedules; Stop stops")
    func longRunning() async throws {
        let server = InMemorySyncServer()
        let macClock = try ManualClock(TestPhone.date("2024-03-14T09:00"))
        let mac = try await TimeStore.inMemory(clock: macClock, timeZone: .current)
        let started = try await mac.start(projectID: nil, task: "Plan the widget layout", at: macClock.now)
        try await StoreSynchronizer(store: mac, transport: server.transport(for: "mac")).sync()

        let test = try await TestPhone { store in SynchronizerSync(store: store, transport: server.transport(for: "phone")) }
        await test.model.sync?.fetchNow()
        await test.model.fanOut(structureChanged: false)
        let reminder = try #require(test.scheduler.pending(.longRunning))
        #expect(reminder.date == started.start + 4 * 3600)
        #expect(reminder.title == "Still tracking Plan the widget layout?")
        #expect(reminder.body == "Running for 4 hours.")

        test.clock.set(started.start + 4 * 3600)
        await test.model.handleNotification(.longRunning, .keep, entryID: nil)
        #expect(test.scheduler.pending(.longRunning)?.date == test.clock.now + 4 * 3600)

        await test.model.handleNotification(.longRunning, .stop, entryID: nil)
        #expect(try await test.store.runningEntry() == nil)
        #expect(test.scheduler.pending(.longRunning) == nil)
    }

    @Test("IOS-26 the reminder is off by default on the iPad and follows the hours setting")
    func longRunningSettings() async throws {
        #expect(PhoneSettings.ephemeral(isPad: true).longRunningEnabled == false)
        let settings = PhoneSettings.ephemeral()
        #expect(settings.longRunningEnabled)
        settings.longRunningHours = 2
        let test = try await TestPhone(settings: settings)
        await test.model.timer.start()
        #expect(test.scheduler.pending(.longRunning)?.date == test.clock.now + 2 * 3600)
    }

    @Test("IOS-9 the Pomodoro notification actions perform their transitions in the background")
    func notificationActions() async throws {
        let test = try await TestPhone()
        await test.model.timer.start()
        test.model.pomodoro.perform(.start, isRunning: true)
        test.clock.advance(by: 26 * 60)
        await test.model.handleNotification(.pomodoroFocusDone, .startBreak, entryID: nil)
        #expect(test.model.pomodoro.state == .onBreak(end: test.clock.now + 5 * 60))
        #expect(test.scheduler.pending(.pomodoroBreakDone)?.date == test.clock.now + 5 * 60)
        await test.model.handleNotification(.pomodoroBreakDone, .endPomodoro, entryID: nil)
        #expect(test.model.pomodoro.state == .off)
    }
}
