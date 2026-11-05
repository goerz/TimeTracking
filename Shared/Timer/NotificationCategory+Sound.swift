// NotificationCategory+Sound: what a notification plays on the Mac and iOS
// (timer.md §5.2, §10; ios.md §2.8).

import UserNotifications

extension NotificationCategory {
    /// `bundled`, or the default sound. The Pomodoro's categories have no
    /// default: without a bundled sound "Play a sound" is off, so they are
    /// silent.
    func notificationSound(_ bundled: NotificationSound?) -> UNNotificationSound? {
        if let bundled {
            return UNNotificationSound(named: UNNotificationSoundName(bundled.rawValue))
        }
        switch self {
        case .pomodoroFocusDone, .pomodoroBreakDone: return nil
        default: return .default
        }
    }
}
