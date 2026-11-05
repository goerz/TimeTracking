// MenuBarPomodoroDisplay: what the status item shows during a Pomodoro
// (menubar.md §1.1, §6).

import Foundation

/// The "During a Pomodoro" setting: the elapsed time, the countdown, or both.
enum MenuBarPomodoroDisplay: String, Codable, Sendable, CaseIterable {
    /// "Timer and countdown": the elapsed time, then the countdown segment.
    case both
    /// "Countdown only": the countdown segment takes the elapsed time's place.
    case countdown
    /// "Timer only": no countdown in the menu bar; the menu still shows it.
    case timer
}
