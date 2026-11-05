// MenuCommand: what an item of the status item's menu does, and its symbol
// (menubar.md §2, design.md §5).

import TimeTrackingCore

/// What a menu item does.
enum MenuCommand: Hashable {
    case openTrackerSettings
    case new
    case continueLatest
    case stop
    case pomodoro(PomodoroAction)
    case showTimer
    case openMainWindow
    case settings
    case quit
}

extension MenuCommand {
    /// The item's SF Symbol (design.md §5), or `nil` for none.
    var symbol: String? {
        switch self {
        case .new: SymbolName.add
        case .continueLatest: SymbolName.start
        case .stop: SymbolName.stop
        // The phase glyph for the items that start a phase.
        case .pomodoro(.start), .pomodoro(.startFocus): SymbolName.pomodoro
        case .pomodoro(.startBreak): SymbolName.pomodoroBreak
        case .showTimer: SymbolName.timer
        case .openMainWindow: SymbolName.mainWindow
        case .settings: SymbolName.settings
        case .openTrackerSettings: SymbolName.activity
        case .pomodoro, .quit: nil
        }
    }
}
