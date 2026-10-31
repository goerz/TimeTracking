// NotificationPosting: posting and removing the Mac app's notifications,
// with a recorder for tests and UI testing (spec_timer_window.md §10).

import Foundation

/// Posts and removes notifications; `UNUserNotificationCenter` in the app,
/// a recorder in tests.
@MainActor
protocol NotificationPosting: NotificationAuthorizing {
    /// Requests authorization once (at the first start of an entry).
    func requestAuthorization()
    func post(_ request: NotificationRequest)
    /// Removes pending and delivered notifications of `categories`.
    func remove(_ categories: [NotificationCategory])
}

/// Keeps what was posted (tests, UI testing).
@MainActor
final class RecordingNotifier: NotificationPosting {
    private(set) var posted: [NotificationRequest] = []
    private(set) var removed: [NotificationCategory] = []
    private(set) var authorizationRequests = 0

    func requestAuthorization() {
        authorizationRequests += 1
    }

    func post(_ request: NotificationRequest) {
        posted.append(request)
    }

    func remove(_ categories: [NotificationCategory]) {
        removed += categories
    }
}
