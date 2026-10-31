// NotificationScheduling: scheduling and removing the iOS app's local
// notifications, with a recorder for tests and UI testing (spec_ios.md §8).

import Foundation

/// Schedules and removes notifications: `UNUserNotificationCenter` in the
/// app, a recorder in tests and under `-UITesting`.
@MainActor
protocol NotificationScheduling: NotificationAuthorizing {
    /// Replaces the pending request of the notification's category.
    func schedule(_ notification: ScheduledNotification)
    /// Removes pending and delivered notifications of `categories`.
    func remove(_ categories: [NotificationCategory])
    /// Whether the user denied notifications (Settings shows a hint).
    func isDenied() async -> Bool
}

/// Keeps what was scheduled (tests, UI testing).
@MainActor
final class RecordingScheduler: NotificationScheduling {
    private(set) var scheduled: [ScheduledNotification] = []
    private(set) var removed: [NotificationCategory] = []
    private(set) var authorizationRequests = 0
    var denied = false

    /// The pending request of `category`, as the notification center keeps one per category.
    func pending(_ category: NotificationCategory) -> ScheduledNotification? {
        scheduled.last { $0.category == category }
    }

    func requestAuthorization() {
        authorizationRequests += 1
    }

    func schedule(_ notification: ScheduledNotification) {
        scheduled.removeAll { $0.category == notification.category }
        scheduled.append(notification)
    }

    func remove(_ categories: [NotificationCategory]) {
        removed += categories
        scheduled.removeAll { categories.contains($0.category) }
    }

    func isDenied() -> Bool {
        denied
    }
}
