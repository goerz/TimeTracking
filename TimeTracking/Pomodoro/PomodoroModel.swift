// PomodoroModel: the Pomodoro over the running entry, with its notifications
// (timer.md §5, §10).

import Foundation
import TimeTrackingCore

/// The Mac Pomodoro: device-local and in memory; it posts each phase's
/// notification when the phase ends.
final class PomodoroModel: PomodoroDriver {
    let notifier: NotificationPosting
    let settings: AppSettings

    init(store: TimeStore, clock: any Clock, notifier: NotificationPosting, settings: AppSettings) {
        self.notifier = notifier
        self.settings = settings
        super.init(store: store, clock: clock)
    }

    /// ⇧⌘P: Start Pomodoro or Cancel Pomodoro.
    func toggle(isRunning: Bool) {
        perform(pomodoro.state.isOn ? .cancel : .start, isRunning: isRunning)
    }

    /// ⌃⌘P: the next step (End Focus Now, Start Break, End Break Now, Start Focus).
    func nextPhase(isRunning: Bool) {
        if let action = pomodoro.nextPhaseAction {
            perform(action, isRunning: isRunning)
        }
    }

    override func transitioned(_ effects: [PomodoroEffect], byAction: Bool) {
        apply(effects)
        super.transitioned(effects, byAction: byAction)
    }

    private func apply(_ effects: [PomodoroEffect]) {
        let sounds = settings.pomodoroSounds
        for effect in effects {
            switch effect {
            case .notifyFocusDone:
                let text = PomodoroNotificationText.focusDone(minutes: focusMinutes, task: currentTask())
                notifier.post(NotificationRequest(
                    category: .pomodoroFocusDone,
                    title: text.title,
                    body: text.body,
                    sound: sounds ? .focusEnd : nil
                ))
            case .notifyBreakOver:
                let text = PomodoroNotificationText.breakOver
                notifier.post(NotificationRequest(
                    category: .pomodoroBreakDone,
                    title: text.title,
                    body: text.body,
                    sound: sounds ? .breakEnd : nil
                ))
            case .removeNotifications:
                notifier.remove([.pomodoroFocusDone, .pomodoroBreakDone])
            }
        }
    }
}
