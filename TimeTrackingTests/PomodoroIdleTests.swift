// The Pomodoro, idle prompt, reminders, notifications, and the tracker
// onboarding (spec_timer.md §5 to §8, §10).

import Foundation
import Testing
import TimeTrackingCore
import UserNotifications
@testable import TimeTracking

@MainActor
struct PomodoroIdleTests {
    @Test("TM-23 the Pomodoro button counts down, then +0:00 at focusEnd with Focus done and Start Break; the label keeps the elapsed time")
    func focusDone() async throws {
        let test = try await TestApp()
        test.app.pomodoro.sleepUntil = { _ in try await Task.sleep(for: .seconds(3600)) }
        test.app.timer.taskText = "Clarify noise model"
        await test.app.timer.start()
        test.app.perform(.start)
        let pomodoro = test.app.pomodoro
        #expect(pomodoro.pomodoro.countdownText(at: test.clock.now) == "25:00")
        test.clock.advance(by: 25 * 60)
        pomodoro.tick()
        #expect(pomodoro.pomodoro.countdownText(at: test.clock.now) == "+0:00")
        #expect(pomodoro.pomodoro.confirmationTitle == "Start Break")
        let posted = try #require(test.notifier.posted.last)
        #expect(posted.category == .pomodoroFocusDone)
        #expect(posted.title == "Focus done")
        #expect(posted.body == "25 minutes on Clarify noise model. Time for a break.")
        #expect(posted.sound == .focusEnd)
        // The timer label keeps counting the elapsed time.
        #expect(test.app.timer.timerText(at: test.clock.now) == "0:25:00")
    }

    @Test("TM-24 through focus, break, and focus the store holds one running entry and no stopped entry")
    func entriesUntouched() async throws {
        let test = try await TestApp()
        test.app.pomodoro.sleepUntil = { _ in try await Task.sleep(for: .seconds(3600)) }
        await test.app.timer.start()
        test.app.perform(.start)
        test.clock.advance(by: 25 * 60)
        test.app.pomodoro.tick()
        test.app.perform(.startBreak)
        test.clock.advance(by: 5 * 60)
        test.app.pomodoro.tick()
        test.app.perform(.startFocus)
        let entries = try await test.store.entries(on: TrackingDay(year: 2024, month: 3, day: 14))
        #expect(entries.count == 1)
        let allRunning = entries.allSatisfy(\.isRunning)
        #expect(allRunning)
        #expect(test.app.pomodoro.state == .focus(end: test.clock.now + 25 * 60))
    }

    @Test("TM-25 stopping the entry ends the Pomodoro and removes its notifications; a new entry keeps it")
    func endsWithEntry() async throws {
        let test = try await TestApp()
        test.app.pomodoro.sleepUntil = { _ in try await Task.sleep(for: .seconds(3600)) }
        await test.app.timer.start()
        test.app.perform(.start)
        await test.app.newEntry()
        #expect(test.app.pomodoro.state.isOn)
        await test.app.stopEntry()
        #expect(test.app.pomodoro.state == .off)
        #expect(test.notifier.removed.suffix(2) == [.pomodoroFocusDone, .pomodoroBreakDone])
    }

    @Test("TM-26 a focus duration change during focus keeps focusEnd and applies from the next phase")
    func durationChange() async throws {
        let test = try await TestApp()
        test.app.pomodoro.sleepUntil = { _ in try await Task.sleep(for: .seconds(3600)) }
        await test.app.timer.start()
        test.app.perform(.start)
        let end = test.app.pomodoro.state.phaseEnd
        await test.app.pomodoro.setFocusMinutes(50)
        #expect(test.app.pomodoro.state.phaseEnd == end)
        #expect(try await test.store.value(.pomodoroFocusMinutes) == 50)
        // A wake after focusEnd lands in focusOver and notifies.
        test.clock.advance(by: 40 * 60)
        test.app.pomodoro.tick()
        #expect(try test.app.pomodoro.state == .focusOver(end: #require(end)))
        #expect(test.notifier.posted.last?.category == .pomodoroFocusDone)
        test.app.perform(.skipBreak)
        #expect(test.app.pomodoro.state == .focus(end: test.clock.now + 50 * 60))
    }

    @Test("TM-27 TM-28 the prompt opens at the next input with Idle since; Keep, Discard, Discard and Continue, Split act per §6.3")
    func idlePrompt() async throws {
        for option in IdleOption.allCases {
            let test = try await TestApp(now: "2024-03-14T14:00")
            let projects = try await test.projects(["Paper"])
            test.app.timer.taskText = "Clarify noise model"
            await test.app.timer.setProject(projects[0].id)
            await test.app.timer.start()
            let running = try #require(test.app.timer.running)
            let idle = test.app.idle
            var shown: [Bool] = []
            idle.showTimer = { shown.append($0) }
            idle.isAppActive = { false }
            // Input stops at 14:02; 23 minutes later it resumes.
            try test.clock.set(test.date("2024-03-14T14:12:05"))
            await idle.sample(idleSeconds: 605, presence: nil)
            #expect(idle.prompt == nil)
            try test.clock.set(test.date("2024-03-14T14:25"))
            await idle.sample(idleSeconds: 1, presence: nil)
            let prompt = try #require(idle.prompt)
            #expect(try prompt.idleStart == (test.date("2024-03-14T14:02")))
            #expect(prompt.runningText == "Running: Clarify noise model · Paper")
            #expect(idle.sinceText(at: test.clock.now) == "Idle since \(LocalDateText.time(prompt.idleStart)) (23 minutes).")
            #expect(test.notifier.posted.last?.category == .idle)
            #expect(shown == [false])
            await idle.resolve(option)
            #expect(idle.prompt == nil)
            let stopped = try await test.store.entry(running.id)
            let current = try await test.store.runningEntry()
            switch option {
            case .keep:
                #expect(stopped?.isRunning == true)
            case .discard:
                #expect(stopped?.end == prompt.idleStart)
                #expect(current == nil)
            case .discardAndContinue:
                #expect(stopped?.end == prompt.idleStart)
                #expect(current?.start == test.clock.now)
                #expect(current?.task == "Clarify noise model" && current?.projectID == projects[0].id)
            case .split:
                #expect(stopped?.end == prompt.idleStart)
                #expect(current?.start == prompt.idleStart)
                #expect(current?.task.isEmpty == true && current?.projectID == nil)
                #expect(shown.last == true)
            }
        }
    }

    @Test("TM-29 Stop the entry at that moment stops at the lock time; shutdown stops at the shutdown time")
    func lockAndShutdown() async throws {
        let test = try await TestApp()
        await test.app.timer.start()
        test.app.settings.idle.onLockOrSleep = .stop
        test.clock.advance(by: 600)
        let lock = test.clock.now
        await test.app.idle.systemEvent(.lock, at: lock)
        #expect(try await test.store.runningEntry() == nil)
        #expect(try await test.store.lastStoppedEntry(excluding: nil)?.end == lock)
        await test.app.timer.start()
        test.clock.advance(by: 60)
        await test.app.idle.systemEvent(.shutdown, at: test.clock.now)
        #expect(try await test.store.runningEntry() == nil)
    }

    @Test("TM-30 a reminder arrives 10 min after a stop at 10:00 on a weekday; Snooze suppresses it")
    func reminders() async throws {
        // 2024-03-12 is a Tuesday.
        let test = try await TestApp(now: "2024-03-12T09:50")
        test.app.settings.reminders.isEnabled = true
        await test.app.timer.start()
        try test.clock.set(test.date("2024-03-12T10:00"))
        await test.app.timer.stop()
        try test.clock.set(test.date("2024-03-12T10:09"))
        #expect(await !(test.app.reminders.check()))
        try test.clock.set(test.date("2024-03-12T10:10"))
        #expect(await test.app.reminders.check())
        let posted = try #require(test.notifier.posted.last)
        #expect(posted.title == "Nothing is being tracked")
        #expect(try posted.body == "Last entry stopped at \(LocalDateText.time(test.date("2024-03-12T10:00"))).")
        test.app.reminders.snooze()
        try test.clock.set(test.date("2024-03-12T10:30"))
        #expect(await !(test.app.reminders.check()))
        try test.clock.set(test.date("2024-03-12T11:10"))
        #expect(await test.app.reminders.check())
        // Locked: none.
        test.app.reminders.isLocked = { true }
        try test.clock.set(test.date("2024-03-12T12:00"))
        #expect(await !(test.app.reminders.check()))
    }

    @Test("TM-32 each notification category offers exactly its actions; Settings reopens on the last pane shown")
    func categoriesAndPane() throws {
        #expect(NotificationCategory.pomodoroFocusDone.actions.map(\.title) == ["Start Break", "Skip Break"])
        #expect(NotificationCategory.pomodoroBreakDone.actions.map(\.title) == ["Start Focus", "End Pomodoro"])
        #expect(NotificationCategory.idle.actions.map(\.title) == ["Keep", "Discard", "Discard and Continue", "Split"])
        #expect(NotificationCategory.reminder.actions.map(\.title) == ["Start New", "Continue Latest", "Snooze"])
        let category = UserNotifications.category(.idle)
        #expect(category.actions.map(\.identifier) == ["keep", "discard", "discardAndContinue", "split"])
        // The pane selection is stored under one key that the Settings view reads.
        let router = WindowRouter(miniTimerWindow: MiniTimerController(settings: AppSettings.ephemeral()))
        #expect(router.paneDefaults == .standard)
        let suite = "PomodoroIdleTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        router.paneDefaults = defaults
        router.openSettings(pane: .reminders)
        #expect(defaults.string(forKey: SettingsPane.storageKey) == "reminders")
        router.openSettings(pane: nil)
        #expect(defaults.string(forKey: SettingsPane.storageKey) == "reminders")
        let symbols = SettingsPane.allCases.map(\.symbol)
        #expect(symbols == ["gearshape", SymbolName.pomodoro, "moon.zzz", "bell", "calendar", "keyboard", "waveform.path.ecg"])
    }

    @Test(
        "TM-34 the alert's Open at login checkbox is on by default; checked, either button registers the app; never under -UITesting"
    )
    func onboardingOpenAtLogin() async throws {
        for openSettings in [true, false] {
            let test = try await TestApp()
            test.app.showTrackerOnboardingIfNeeded()
            #expect(test.app.onboardingOpensAtLogin)
            test.app.answerTrackerOnboarding(openSettings: openSettings)
            #expect(test.loginItem.changes == [true])
            #expect(test.app.tracker.opensAtLogin)
            #expect(test.agent.registerCalls == 0)
        }
        let unchecked = try await TestApp()
        unchecked.app.showTrackerOnboardingIfNeeded()
        unchecked.app.onboardingOpensAtLogin = false
        unchecked.app.answerTrackerOnboarding(openSettings: false)
        #expect(unchecked.loginItem.changes.isEmpty)
        #expect(!unchecked.app.tracker.opensAtLogin)
        // The alert gets the checkbox's default and applies its answer.
        let presented = try await TestApp()
        var shown: (name: String, checked: Bool)?
        presented.app.onboardingPresenter = { name, checked, answer in
            shown = (name, checked)
            answer(false, false)
        }
        presented.app.showTrackerOnboardingIfNeeded()
        presented.app.presentTrackerOnboarding()
        #expect(shown?.name == presented.app.tracker.bundles.appName)
        #expect(shown?.checked == true)
        #expect(presented.loginItem.changes.isEmpty)
        #expect(!presented.app.showsTrackerOnboarding)
        #expect(presented.app.settings.trackerOnboardingPrompted)
        #expect(AppDelegate.appLoginItem(uiTesting: true) is FakeAppLoginItem)
        #expect(AppDelegate.appLoginItem(uiTesting: false) is MainAppLoginItem)
    }

    @Test("TM-34 under -UITesting the agent registration is in memory, so the first-launch alert registers nothing real")
    func uiTestingAgent() throws {
        let identity = try AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])
        #expect(AppDelegate.agentService(identity: identity, uiTesting: true, realAgent: false) is FakeAgentService)
        #expect(AppDelegate.agentService(identity: identity, uiTesting: true, realAgent: true) is LoginItemAgentService)
        #expect(AppDelegate.agentService(identity: identity, uiTesting: false, realAgent: false) is LoginItemAgentService)
        #expect(AppDelegate.agentService(identity: nil, uiTesting: false, realAgent: false) is FakeAgentService)
    }

    @Test("TM-33 the first-launch alert appears once; Open Tracker Settings opens the Tracker pane; nothing registers until Enable Tracker")
    func onboarding() async throws {
        let test = try await TestApp()
        test.app.showTrackerOnboardingIfNeeded()
        #expect(test.app.showsTrackerOnboarding)
        test.app.answerTrackerOnboarding(openSettings: true)
        #expect(test.router.calls == [.openSettings(.tracker)])
        #expect(test.app.settings.trackerOnboardingPrompted)
        #expect(test.agent.registerCalls == 0)
        // Once per Mac: the device setting survives.
        let again = AppSettings(device: test.app.settings.device)
        #expect(again.trackerOnboardingPrompted)
        test.app.showsTrackerOnboarding = false
        test.app.showTrackerOnboardingIfNeeded()
        #expect(!test.app.showsTrackerOnboarding)
        await test.app.tracker.pressButton()
        #expect(test.agent.registerCalls == 1)
        #expect(test.app.tracker.registration == .enabled)
    }
}
