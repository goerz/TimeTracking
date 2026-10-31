// NotificationCategory: the Mac app's notification categories, actions,
// sounds, and requests (spec_timer_window.md §10).

import Foundation

/// A notification category; its raw value is the category identifier and
/// the identifier of its single pending request.
enum NotificationCategory: String, CaseIterable, Sendable {
    case pomodoroFocusDone
    case pomodoroBreakDone
    case idle
    case reminder
    /// The banner of a start, stop, or continue from a URL (spec_automation.md §6).
    case tracking

    /// Exactly the actions of §10, in order.
    var actions: [NotificationAction] {
        switch self {
        case .pomodoroFocusDone: [.startBreak, .skipBreak]
        case .pomodoroBreakDone: [.startFocus, .endPomodoro]
        case .idle: [.keep, .discard, .discardAndContinue, .split]
        case .reminder: [.startNew, .continueLatest, .snooze]
        case .tracking: []
        }
    }
}

/// A notification action; its raw value is the action identifier.
enum NotificationAction: String, CaseIterable, Sendable {
    case startBreak
    case skipBreak
    case startFocus
    case endPomodoro
    case keep
    case discard
    case discardAndContinue
    case split
    case startNew
    case continueLatest
    case snooze

    var title: String {
        switch self {
        case .startBreak: "Start Break"
        case .skipBreak: "Skip Break"
        case .startFocus: "Start Focus"
        case .endPomodoro: "End Pomodoro"
        case .keep: "Keep"
        case .discard: "Discard"
        case .discardAndContinue: "Discard and Continue"
        case .split: "Split"
        case .startNew: "Start New"
        case .continueLatest: "Continue Latest"
        case .snooze: "Snooze"
        }
    }
}

/// The bundled phase-end sounds.
enum NotificationSound: String, Sendable {
    case focusEnd = "FocusEnd.wav"
    case breakEnd = "BreakEnd.wav"
}

/// One notification to post.
struct NotificationRequest: Equatable, Sendable {
    var category: NotificationCategory
    var title: String
    var body: String
    /// A bundled sound, or `nil` for the default sound.
    var sound: NotificationSound?
}
