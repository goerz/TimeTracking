// PomodoroDriver: the Pomodoro over the running entry, shared by the Mac and
// iOS models (timer.md §5, ios.md §2.8).

import Foundation
import Observation
import TimeTrackingCore

/// Drives the library's `Pomodoro` state machine with the clock and the
/// synced durations, and wakes itself at phase ends. The platform models
/// subclass it and override `transitioned(_:byAction:)` for notifications
/// and persistence.
@Observable
class PomodoroDriver {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    /// The running entry's task, for the "Focus done" body.
    @ObservationIgnored var currentTask: () -> String = { "" }
    /// Wakes the model at a phase end while the app runs; replaced in tests.
    @ObservationIgnored var sleepUntil: @Sendable (Date) async throws -> Void = { date in
        try await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
    }

    @ObservationIgnored private var phaseTask: Task<Void, Never>?

    private(set) var pomodoro: Pomodoro
    /// Synced focus duration in minutes (`SyncedSettingKey.range`).
    private(set) var focusMinutes = SyncedSettingKey<Int>.pomodoroFocusMinutes.defaultValue
    /// Synced break duration in minutes.
    private(set) var breakMinutes = SyncedSettingKey<Int>.pomodoroBreakMinutes.defaultValue

    init(store: TimeStore, clock: any Clock, pomodoro: Pomodoro = Pomodoro()) {
        self.store = store
        self.clock = clock
        self.pomodoro = pomodoro
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
        focusMinutes = SyncedSettingKey<Int>.pomodoroFocusMinutes.clamped(minutes)
        try? await store.set(.pomodoroFocusMinutes, focusMinutes)
    }

    func setBreakMinutes(_ minutes: Int) async {
        breakMinutes = SyncedSettingKey<Int>.pomodoroBreakMinutes.clamped(minutes)
        try? await store.set(.pomodoroBreakMinutes, breakMinutes)
    }

    func actions(isRunning: Bool) -> [PomodoroAction] {
        pomodoro.actions(isRunning: isRunning)
    }

    /// A user action from the button, a menu, or a notification.
    func perform(_ action: PomodoroAction, isRunning: Bool) {
        let effects = pomodoro.perform(
            action,
            at: clock.now,
            focus: TimeInterval(focusMinutes * 60),
            break: TimeInterval(breakMinutes * 60),
            isRunning: isRunning
        )
        transitioned(effects, byAction: true)
    }

    /// A phase end passed: called at the wake, by the platform, and by tests.
    func tick() {
        transitioned(pomodoro.advance(to: clock.now), byAction: false)
    }

    /// The running entry changed, here or on another device; nothing
    /// running ends the Pomodoro.
    func runningChanged(isRunning: Bool) {
        guard !isRunning else {
            return
        }
        transitioned(pomodoro.runningEntryEnded(), byAction: false)
    }

    /// Continues from a saved state: a passed phase end becomes the
    /// over-state; with nothing running the Pomodoro ends.
    func resume(from saved: Pomodoro, isRunning: Bool) {
        pomodoro = saved
        var effects = pomodoro.advance(to: clock.now)
        if !isRunning {
            effects += pomodoro.runningEntryEnded()
        }
        transitioned(effects, byAction: false)
    }

    /// Ends the Pomodoro without effects (the app quits).
    func reset() {
        pomodoro.reset()
        phaseTask?.cancel()
    }

    /// Called after every transition; `byAction` when a user action caused
    /// it. Overrides handle the effects, then call this, which arms the wake
    /// at the phase end.
    func transitioned(_: [PomodoroEffect], byAction _: Bool) {
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
