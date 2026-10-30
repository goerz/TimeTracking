// Pomodoro: the focus and break state machine laid over the running entry
// (spec_timer_window.md §5.3). It never starts, stops, or splits entries.

public import Foundation

/// The Pomodoro phase. Phase ends are absolute times, so a Mac that sleeps
/// through one wakes into overtime.
public enum PomodoroState: Hashable, Sendable, Codable {
    case off
    case focus(end: Date)
    /// Focus ended at `end`; "Start Break" is pending.
    case focusOver(end: Date)
    case onBreak(end: Date)
    /// The break ended at `end`; "Start Focus" is pending.
    case breakOver(end: Date)

    /// The end of the current or just-ended phase.
    public var phaseEnd: Date? {
        switch self {
        case .off: nil
        case let .focus(end), let .focusOver(end), let .onBreak(end), let .breakOver(end): end
        }
    }

    public var isOn: Bool {
        self != .off
    }

    /// Whether a phase ended and waits for confirmation.
    public var isPendingConfirmation: Bool {
        switch self {
        case .focusOver, .breakOver: true
        default: false
        }
    }

    /// Focus or focus over (the focus glyph), as opposed to break.
    public var isFocusPhase: Bool {
        switch self {
        case .focus, .focusOver: true
        default: false
        }
    }
}

/// The user actions of §5.3 and the menus of `spec_menubar.md` §2.3.
public enum PomodoroAction: String, Hashable, Sendable, CaseIterable {
    case start
    case endFocusNow
    case startBreak
    case skipBreak
    case endBreakNow
    case startFocus
    case cancel

    /// The menu title.
    public var title: String {
        switch self {
        case .start: "Start Pomodoro"
        case .endFocusNow: "End Focus Now"
        case .startBreak: "Start Break"
        case .skipBreak: "Skip Break"
        case .endBreakNow: "End Break Now"
        case .startFocus: "Start Focus"
        case .cancel: "Cancel Pomodoro"
        }
    }
}

/// What the owner does after a transition.
public enum PomodoroEffect: Hashable, Sendable {
    /// Post "Focus done" (`pomodoroFocusDone`).
    case notifyFocusDone
    /// Post "Break over" (`pomodoroBreakDone`).
    case notifyBreakOver
    /// Remove pending and delivered Pomodoro notifications.
    case removeNotifications
}

/// The state machine. Value type: the Mac keeps it in memory, iOS persists it.
public struct Pomodoro: Hashable, Sendable, Codable {
    public private(set) var state: PomodoroState

    public init(state: PomodoroState = .off) {
        self.state = state
    }

    /// The actions the state allows, in menu order (`spec_menubar.md` §2.3).
    public func actions(isRunning: Bool) -> [PomodoroAction] {
        switch state {
        case .off: isRunning ? [.start] : []
        case .focus: [.endFocusNow, .cancel]
        case .focusOver: [.startBreak, .skipBreak, .cancel]
        case .onBreak: [.endBreakNow, .cancel]
        case .breakOver: [.startFocus, .cancel]
        }
    }

    /// The action of "Next Pomodoro Phase" (⌃⌘P), if any.
    public var nextPhaseAction: PomodoroAction? {
        switch state {
        case .off: nil
        case .focus: .endFocusNow
        case .focusOver: .startBreak
        case .onBreak: .endBreakNow
        case .breakOver: .startFocus
        }
    }

    /// Performs `action` if the state allows it; durations in seconds.
    @discardableResult
    public mutating func perform(
        _ action: PomodoroAction,
        at now: Date,
        focus: TimeInterval,
        break breakDuration: TimeInterval,
        isRunning: Bool
    ) -> [PomodoroEffect] {
        guard actions(isRunning: isRunning).contains(action) else {
            return []
        }
        switch action {
        case .start, .skipBreak, .endBreakNow, .startFocus:
            state = .focus(end: now + focus)
        case .endFocusNow, .startBreak:
            state = .onBreak(end: now + breakDuration)
        case .cancel:
            state = .off
            return [.removeNotifications]
        }
        return [.removeNotifications]
    }

    /// Moves a phase whose end has passed into its confirmation state.
    @discardableResult
    public mutating func advance(to now: Date) -> [PomodoroEffect] {
        switch state {
        case let .focus(end) where now >= end:
            state = .focusOver(end: end)
            return [.notifyFocusDone]
        case let .onBreak(end) where now >= end:
            state = .breakOver(end: end)
            return [.notifyBreakOver]
        default:
            return []
        }
    }

    /// Nothing runs any more (stop, discard, idle Discard): the Pomodoro ends.
    @discardableResult
    public mutating func runningEntryEnded() -> [PomodoroEffect] {
        guard state.isOn else {
            return []
        }
        state = .off
        return [.removeNotifications]
    }

    /// The app quits.
    public mutating func reset() {
        state = .off
    }

    /// Seconds left in the phase (negative in overtime), or `nil` when off.
    public func remaining(at now: Date) -> Int? {
        guard let end = state.phaseEnd else {
            return nil
        }
        let interval = end.timeIntervalSince(now)
        return interval >= 0 ? Int(interval.rounded(.up)) : -Int((-interval).rounded(.down))
    }

    /// The fraction of the phase that has passed, 0 to 1, or `nil` when off.
    /// The phase length is the current duration setting (in seconds), at
    /// least the time remaining, so a setting changed mid-phase never
    /// shows a negative fraction.
    public func progress(at now: Date, focus: TimeInterval, break breakDuration: TimeInterval) -> Double? {
        guard let remaining = remaining(at: now) else {
            return nil
        }
        if state.isPendingConfirmation || remaining <= 0 {
            return 1
        }
        let length = max(state.isFocusPhase ? focus : breakDuration, TimeInterval(remaining), 1)
        return min(max(1 - TimeInterval(remaining) / length, 0), 1)
    }

    /// The Pomodoro button's countdown while on: `m:ss` (`h:mm:ss` from an
    /// hour) counting down, `+m:ss` counting up in overtime.
    public func countdownText(at now: Date) -> String? {
        guard let remaining = remaining(at: now) else {
            return nil
        }
        if state.isPendingConfirmation || remaining < 0 {
            return DurationText.overtime(-min(remaining, 0))
        }
        return DurationText.countdown(remaining)
    }

    /// The Pomodoro button's accessibility label and tooltip: "Pomodoro",
    /// "Focus 24:59", "Break 4:30", "Focus +1:20".
    public func buttonTitle(at now: Date) -> String {
        guard let text = countdownText(at: now) else {
            return "Pomodoro"
        }
        return (state.isFocusPhase ? "Focus " : "Break ") + text
    }

    /// The pending confirmation button's title, if any.
    public var confirmationTitle: String? {
        switch state {
        case .focusOver: PomodoroAction.startBreak.title
        case .breakOver: PomodoroAction.startFocus.title
        default: nil
        }
    }
}
