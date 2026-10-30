// PomodoroModel: the Pomodoro over the running entry, with its notifications
// (spec_timer_window.md §5, §10).

import Foundation
import Observation
import TimeTrackingCore

/// Drives the library's `Pomodoro` state machine with the clock, the synced
/// durations, and notifications. Device-local and in memory.
@Observable
final class PomodoroModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let notifier: NotificationPosting
    @ObservationIgnored let settings: AppSettings
    /// The running entry's task, for the "Focus done" body.
    @ObservationIgnored var currentTask: () -> String = { "" }
    /// Wakes the model at a phase end; replaced in tests.
    @ObservationIgnored var sleepUntil: @Sendable (Date) async throws -> Void = { date in
        try await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
    }

    @ObservationIgnored private var phaseTask: Task<Void, Never>?

    private(set) var pomodoro = Pomodoro()
    /// Synced focus duration in minutes (1 to 180).
    private(set) var focusMinutes = SyncedSettingKey<Int>.pomodoroFocusMinutes.defaultValue
    /// Synced break duration in minutes (1 to 60).
    private(set) var breakMinutes = SyncedSettingKey<Int>.pomodoroBreakMinutes.defaultValue

    init(store: TimeStore, clock: any Clock, notifier: NotificationPosting, settings: AppSettings) {
        self.store = store
        self.clock = clock
        self.notifier = notifier
        self.settings = settings
    }

    var state: PomodoroState {
        pomodoro.state
    }

    /// Reads the synced durations.
    func loadSettings() async {
        focusMinutes = await (try? store.value(.pomodoroFocusMinutes)) ?? focusMinutes
        breakMinutes = await (try? store.value(.pomodoroBreakMinutes)) ?? breakMinutes
    }

    /// Changes a synced duration; it applies from the next phase.
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

    /// Performs a user action (button, menu, notification).
    func perform(_ action: PomodoroAction, isRunning: Bool) {
        let effects = pomodoro.perform(
            action,
            at: clock.now,
            focus: TimeInterval(focusMinutes * 60),
            break: TimeInterval(breakMinutes * 60),
            isRunning: isRunning
        )
        apply(effects)
        schedule()
    }

    /// ⇧⌘P: Start Pomodoro or Cancel Pomodoro.
    func toggle(isRunning: Bool) {
        perform(pomodoro.state.isOn ? .cancel : .start, isRunning: isRunning)
    }

    /// ⌃⌘P: Next Pomodoro Phase.
    func nextPhase(isRunning: Bool) {
        if let action = pomodoro.nextPhaseAction {
            perform(action, isRunning: isRunning)
        }
    }

    /// Checks the clock; called at phase ends, at wake, and by tests.
    func tick() {
        apply(pomodoro.advance(to: clock.now))
        schedule()
    }

    /// The running entry changed; nothing running ends the Pomodoro.
    func runningChanged(isRunning: Bool) {
        guard !isRunning else {
            return
        }
        apply(pomodoro.runningEntryEnded())
        schedule()
    }

    /// The app quits.
    func reset() {
        pomodoro.reset()
        phaseTask?.cancel()
    }

    private func schedule() {
        phaseTask?.cancel()
        phaseTask = nil
        guard case let .focus(end) = pomodoro.state else {
            if case let .onBreak(end) = pomodoro.state {
                arm(at: end)
            }
            return
        }
        arm(at: end)
    }

    private func arm(at end: Date) {
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

    private func apply(_ effects: [PomodoroEffect]) {
        let sounds = settings.pomodoroSounds
        for effect in effects {
            switch effect {
            case .notifyFocusDone:
                let task = currentTask()
                let subject = task.isEmpty ? "" : " on \(task)"
                notifier.post(NotificationRequest(
                    category: .pomodoroFocusDone,
                    title: "Focus done",
                    body: "\(focusMinutes) minutes\(subject). Time for a break.",
                    sound: sounds ? .focusEnd : nil
                ))
            case .notifyBreakOver:
                notifier.post(NotificationRequest(
                    category: .pomodoroBreakDone,
                    title: "Break over",
                    body: "Ready for the next focus?",
                    sound: sounds ? .breakEnd : nil
                ))
            case .removeNotifications:
                notifier.remove([.pomodoroFocusDone, .pomodoroBreakDone])
            }
        }
    }
}
