// PhonePomodoroModel: the iOS Pomodoro, persisted in the device settings
// with its notifications scheduled ahead (spec_ios.md §2.8, §8;
// spec_timer_window.md §5).

import Foundation
import TimeTrackingCore

/// Every transition is persisted and a user action schedules the phase's
/// notification; a replay at launch turns passed phase ends into the
/// over-states and never changes an entry.
final class PhonePomodoroModel: PomodoroDriver {
    let scheduler: NotificationScheduling
    let settings: PhoneSettings
    /// Called after every transition (widgets end their timeline at phase ends).
    var onTransition: () -> Void = {}

    init(store: TimeStore, clock: any Clock, scheduler: NotificationScheduling, settings: PhoneSettings) {
        self.scheduler = scheduler
        self.settings = settings
        super.init(store: store, clock: clock, pomodoro: settings.device[.pomodoroState])
    }

    /// Replays the persisted state whenever the process runs (§2.8 item 2):
    /// a passed phase end becomes the over-state; with nothing running the
    /// Pomodoro ends and its pending notifications are removed.
    func replay(isRunning: Bool) {
        resume(from: settings.device[.pomodoroState], isRunning: isRunning)
    }

    override func transitioned(_ effects: [PomodoroEffect], byAction: Bool) {
        settings.device[.pomodoroState] = pomodoro
        if effects.contains(.removeNotifications) {
            scheduler.remove([.pomodoroFocusDone, .pomodoroBreakDone])
        }
        if byAction {
            schedulePhaseNotification()
        }
        super.transitioned(effects, byAction: byAction)
        onTransition()
    }

    /// The notification of the phase that just started, at its end.
    private func schedulePhaseNotification() {
        let sounds = settings.pomodoroSounds
        switch pomodoro.state {
        case let .focus(end):
            let text = PomodoroNotificationText.focusDone(minutes: focusMinutes, task: currentTask())
            scheduler.schedule(ScheduledNotification(
                category: .pomodoroFocusDone,
                title: text.title,
                body: text.body,
                date: end,
                sound: sounds ? .focusEnd : nil
            ))
        case let .onBreak(end):
            let text = PomodoroNotificationText.breakOver
            scheduler.schedule(ScheduledNotification(
                category: .pomodoroBreakDone,
                title: text.title,
                body: text.body,
                date: end,
                sound: sounds ? .breakEnd : nil
            ))
        case .off, .focusOver, .breakOver:
            break
        }
    }
}
