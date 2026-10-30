// PhoneNotifications: the iOS app's local notifications, scheduled ahead of
// time because the app is not running when they fire (spec_ios.md §8).

import Foundation

/// A notification category; its raw value is the category identifier and
/// the identifier of its single pending request.
enum NotificationCategory: String, CaseIterable, Sendable {
    case pomodoroFocusDone
    case pomodoroBreakDone
    case longRunning
    case syncAdjusted

    /// The actions of §8, in order.
    var actions: [NotificationAction] {
        switch self {
        case .pomodoroFocusDone: [.startBreak, .skipBreak]
        case .pomodoroBreakDone: [.startFocus, .endPomodoro]
        case .longRunning: [.keep, .stop]
        case .syncAdjusted: []
        }
    }

    /// The interruption level of §8.
    var level: NotificationLevel {
        switch self {
        case .pomodoroFocusDone, .pomodoroBreakDone: .timeSensitive
        case .longRunning: .active
        case .syncAdjusted: .passive
        }
    }
}

enum NotificationLevel: Sendable {
    case passive
    case active
    case timeSensitive
}

/// A notification action; its raw value is the action identifier.
enum NotificationAction: String, CaseIterable, Sendable {
    case startBreak
    case skipBreak
    case startFocus
    case endPomodoro
    case keep
    case stop

    var title: String {
        switch self {
        case .startBreak: "Start Break"
        case .skipBreak: "Skip Break"
        case .startFocus: "Start Focus"
        case .endPomodoro: "End Pomodoro"
        case .keep: "Keep"
        case .stop: "Stop"
        }
    }
}

/// The bundled phase-end sounds.
enum NotificationSound: String, Sendable {
    case focusEnd = "FocusEnd.wav"
    case breakEnd = "BreakEnd.wav"
}

/// One notification, delivered at `date` (`nil`: at once).
struct ScheduledNotification: Equatable, Sendable {
    var category: NotificationCategory
    var title: String
    var body: String
    var date: Date?
    var sound: NotificationSound?
    /// Opens this entry's edit sheet when tapped (`syncAdjusted`).
    var entryID: String?
}

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
