// PhonePomodoroModel: the iOS Pomodoro, persisted in the device settings
// with its notifications scheduled ahead (spec_ios.md §2.8, §8;
// spec_timer_window.md §5).

import Foundation
import Observation
import TimeTrackingCore

/// Drives the library's `Pomodoro` with the clock and the synced durations.
/// Every transition is persisted and schedules the phase's notification; a
/// replay at launch turns passed phase ends into the over-states and never
/// changes an entry.
@Observable
final class PhonePomodoroModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let scheduler: NotificationScheduling
    @ObservationIgnored let settings: PhoneSettings
    /// The running entry's task, for the "Focus done" body.
    @ObservationIgnored var currentTask: () -> String = { "" }
    /// Called after every transition (widgets end their timeline at phase ends).
    @ObservationIgnored var onTransition: () -> Void = {}
    /// Wakes the model at a phase end while the app runs; replaced in tests.
    @ObservationIgnored var sleepUntil: @Sendable (Date) async throws -> Void = { date in
        try await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
    }

    @ObservationIgnored private var phaseTask: Task<Void, Never>?

    private(set) var pomodoro: Pomodoro
    private(set) var focusMinutes = SyncedSettingKey<Int>.pomodoroFocusMinutes.defaultValue
    private(set) var breakMinutes = SyncedSettingKey<Int>.pomodoroBreakMinutes.defaultValue

    init(store: TimeStore, clock: any Clock, scheduler: NotificationScheduling, settings: PhoneSettings) {
        self.store = store
        self.clock = clock
        self.scheduler = scheduler
        self.settings = settings
        self.pomodoro = settings.device[.pomodoroState]
    }

    var state: PomodoroState {
        pomodoro.state
    }

    func loadSettings() async {
        focusMinutes = await (try? store.value(.pomodoroFocusMinutes)) ?? focusMinutes
        breakMinutes = await (try? store.value(.pomodoroBreakMinutes)) ?? breakMinutes
    }

    func setFocusMinutes(_ minutes: Int) async {
        focusMinutes = min(max(minutes, 1), 180)
        try? await store.set(.pomodoroFocusMinutes, focusMinutes)
    }

    func setBreakMinutes(_ minutes: Int) async {
        breakMinutes = min(max(minutes, 1), 60)
        try? await store.set(.pomodoroBreakMinutes, breakMinutes)
    }

    func actions(isRunning: Bool) -> [PomodoroAction] {
        pomodoro.actions(isRunning: isRunning)
    }

    /// A user action from the button, its menu, or a notification.
    func perform(_ action: PomodoroAction, isRunning: Bool) {
        let effects = pomodoro.perform(
            action,
            at: clock.now,
            focus: TimeInterval(focusMinutes * 60),
            break: TimeInterval(breakMinutes * 60),
            isRunning: isRunning
        )
        transitioned(effects, scheduling: true)
    }

    /// Replays the persisted state whenever the process runs (§2.8 item 2):
    /// a passed phase end becomes the over-state; with nothing running the
    /// Pomodoro ends and its pending notifications are removed.
    func replay(isRunning: Bool) {
        pomodoro = settings.device[.pomodoroState]
        var effects = pomodoro.advance(to: clock.now)
        if !isRunning {
            effects += pomodoro.runningEntryEnded()
        }
        transitioned(effects, scheduling: false)
    }

    /// The running entry changed, here or on another device.
    func runningChanged(isRunning: Bool) {
        guard !isRunning else {
            return
        }
        transitioned(pomodoro.runningEntryEnded(), scheduling: false)
    }

    /// A phase end passed while the app runs.
    func tick() {
        transitioned(pomodoro.advance(to: clock.now), scheduling: false)
    }

    private func transitioned(_ effects: [PomodoroEffect], scheduling: Bool) {
        settings.device[.pomodoroState] = pomodoro
        if effects.contains(.removeNotifications) {
            scheduler.remove([.pomodoroFocusDone, .pomodoroBreakDone])
        }
        if scheduling {
            schedulePhaseNotification()
        }
        arm()
        onTransition()
    }

    /// The notification of the phase that just started, at its end.
    private func schedulePhaseNotification() {
        let sounds = settings.pomodoroSounds
        switch pomodoro.state {
        case let .focus(end):
            let task = currentTask()
            let subject = task.isEmpty ? "" : " on \(task)"
            scheduler.schedule(ScheduledNotification(
                category: .pomodoroFocusDone,
                title: "Focus done",
                body: "\(focusMinutes) minutes\(subject). Time for a break.",
                date: end,
                sound: sounds ? .focusEnd : nil
            ))
        case let .onBreak(end):
            scheduler.schedule(ScheduledNotification(
                category: .pomodoroBreakDone,
                title: "Break over",
                body: "Ready for the next focus?",
                date: end,
                sound: sounds ? .breakEnd : nil
            ))
        case .off, .focusOver, .breakOver:
            break
        }
    }

    private func arm() {
        phaseTask?.cancel()
        phaseTask = nil
        let end: Date
        switch pomodoro.state {
        case let .focus(phaseEnd), let .onBreak(phaseEnd):
            end = phaseEnd
        case .off, .focusOver, .breakOver:
            return
        }
        let sleep = sleepUntil
        phaseTask = Task { [weak self] in
            do {
                try await sleep(end)
            } catch {
                return
            }
            self?.tick()
        }
    }
}
