// AppRouting: the window commands other parts of the app call
// (timer.md §1.3, menubar.md §2.2).

import Foundation
import TimeTrackingCore

/// The settings window's panes, in toolbar order (timer.md §8).
enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general
    case pomodoro
    case idle
    case reminders
    case calendar
    case shortcuts
    case tracker

    /// The `UserDefaults` key of the last pane shown.
    static let storageKey = "settings.lastPane"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general: "General"
        case .pomodoro: "Pomodoro"
        case .idle: "Idle"
        case .reminders: "Reminders"
        case .calendar: "Calendar"
        case .shortcuts: "Shortcuts"
        case .tracker: "Tracker"
        }
    }

    var symbol: String {
        switch self {
        case .general: SymbolName.settings
        case .pomodoro: SymbolName.pomodoro
        case .idle: SymbolName.idle
        case .reminders: SymbolName.reminders
        case .calendar: SymbolName.calendar
        case .shortcuts: SymbolName.shortcuts
        case .tracker: SymbolName.activity
        }
    }
}

/// Showing and hiding windows.
@MainActor
protocol AppRouting: AnyObject {
    /// Shows the Mini Timer and activates the app; optionally focuses the task field.
    func showTimer(focusTask: Bool)
    /// The show/hide shortcut: shows the window with the task field focused
    /// unless it is the key window of the active app, which hides the app.
    func toggleTimer()
    /// Shows the main window and activates the app, on `item` or, with
    /// `nil`, on the item it shows.
    func showMainWindow(item: MainSidebarItem?)
    /// Opens Settings, on `pane` or the last pane shown.
    func openSettings(pane: SettingsPane?)
}

/// Records routing calls (tests).
@MainActor
final class RecordingRouter: AppRouting {
    enum Call: Equatable {
        case showTimer(focusTask: Bool)
        case toggleTimer
        case showMainWindow(MainSidebarItem?)
        case openSettings(SettingsPane?)
    }

    private(set) var calls: [Call] = []

    func showTimer(focusTask: Bool) {
        calls.append(.showTimer(focusTask: focusTask))
    }

    func toggleTimer() {
        calls.append(.toggleTimer)
    }

    func showMainWindow(item: MainSidebarItem?) {
        calls.append(.showMainWindow(item))
    }

    func openSettings(pane: SettingsPane?) {
        calls.append(.openSettings(pane))
    }
}
