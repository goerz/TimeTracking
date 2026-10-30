// MenuCommand: what an item of the status item's menu does, and its symbol
// (spec_menubar.md §2, spec_design.md §5).

import TimeTrackingCore

/// What a menu item does.
enum MenuCommand: Hashable {
    case openTrackerSettings
    case new
    case continueLatest
    case stop
    case pomodoro(PomodoroAction)
    case showTimer
    case openPlanner
    case settings
    case quit
}

extension MenuCommand {
    /// The item's SF Symbol (spec_design.md §5), or `nil` for none.
    var symbol: String? {
        switch self {
        case .new: "plus"
        case .continueLatest: "play.fill"
        case .stop: "stop.fill"
        // The phase glyph for the items that start a phase.
        case .pomodoro(.start), .pomodoro(.startFocus): AppSymbol.pomodoro
        case .pomodoro(.startBreak): AppSymbol.pomodoroBreak
        case .showTimer: "stopwatch"
        case .openPlanner: "calendar"
        case .settings: "gearshape"
        case .openTrackerSettings: "waveform.path.ecg"
        case .pomodoro, .quit: nil
        }
    }
}
