// AppRouting: the window commands other parts of the app call
// (spec_timer_window.md §13, spec_menubar.md §2.2).

import Foundation
import TimeTrackingCore

/// The settings window's panes, in toolbar order (spec_timer_window.md §8).
enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general
    case pomodoro
    case idle
    case reminders
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
        case .shortcuts: SymbolName.shortcuts
        case .tracker: SymbolName.activity
        }
    }
}

/// Showing and hiding windows.
@MainActor
protocol AppRouting: AnyObject {
    /// Shows the Timer window and activates the app; optionally focuses the task field.
    func showTimer(focusTask: Bool)
    /// The show/hide shortcut: shows the window with the task field focused
    /// unless it is the key window of the active app, which hides the app.
    func toggleTimer()
    /// Opens Settings, on `pane` or the last pane shown.
    func openSettings(pane: SettingsPane?)
    /// Opens the Planner on its last section.
    func openPlanner()
}

/// Records routing calls (tests).
@MainActor
final class RecordingRouter: AppRouting {
    enum Call: Equatable {
        case showTimer(focusTask: Bool)
        case toggleTimer
        case openSettings(SettingsPane?)
        case openPlanner
    }

    private(set) var calls: [Call] = []

    func showTimer(focusTask: Bool) {
        calls.append(.showTimer(focusTask: focusTask))
    }

    func toggleTimer() {
        calls.append(.toggleTimer)
    }

    func openSettings(pane: SettingsPane?) {
        calls.append(.openSettings(pane))
    }

    func openPlanner() {
        calls.append(.openPlanner)
    }
}
