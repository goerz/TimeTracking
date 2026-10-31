// NotificationCategory: the iOS app's local notification categories,
// actions, sounds, and the notifications scheduled ahead of time because
// the app is not running when they fire (spec_ios.md §8).

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
        case .keep: "Keep Running"
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
