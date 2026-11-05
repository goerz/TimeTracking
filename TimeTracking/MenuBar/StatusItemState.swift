// StatusItemState: the inputs of the status item and its menu
// (menubar.md §1, §2).

import Foundation
import TimeTrackingCore

/// The inputs of the status item, gathered from the Timer's state.
struct StatusItemState {
    var running: TimeEntry?
    var label: ProjectLabel
    var mostRecentOther: TimeEntry?
    var lastStoppedToday: TimeEntry?
    var pomodoro: Pomodoro
    /// The synced phase durations in minutes, for the dial's progress.
    var focusMinutes = 25
    var breakMinutes = 5
    var showTimer: Bool
    var showSeconds: Bool
    var showProject: Bool
    var pomodoroDisplay: MenuBarPomodoroDisplay = .both
    var warning: Bool
    var warningLine: String
    /// The recorded show/hide shortcut, `nil` when cleared.
    var showHideKey: MenuKey?
    var appName: String
}
