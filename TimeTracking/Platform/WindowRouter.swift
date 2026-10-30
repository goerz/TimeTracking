// WindowRouter: showing the Timer window, Settings, and the Planner
// (spec_timer_window.md §1.3, §8.3; spec_menubar.md §2.2, §4).

import AppKit
import SwiftUI

/// The live `AppRouting`: AppKit for the Timer window, the SwiftUI actions
/// captured from a view for Settings and the Planner.
final class WindowRouter: AppRouting {
    let timerWindow: TimerWindowController
    weak var app: AppModel?
    /// Captured from the Timer window's environment.
    var openSettingsAction: OpenSettingsAction?
    var openWindowAction: OpenWindowAction?

    init(timerWindow: TimerWindowController) {
        self.timerWindow = timerWindow
    }

    func showTimer(focusTask: Bool) {
        timerWindow.show()
        if focusTask {
            app?.timer.requestTaskFieldFocus()
        }
    }

    func toggleTimer() {
        if NSApp.isActive, timerWindow.isKey {
            timerWindow.hide()
        } else {
            showTimer(focusTask: true)
        }
    }

    func openSettings(pane: SettingsPane?) {
        if let pane {
            UserDefaults.standard.set(pane.rawValue, forKey: SettingsPane.storageKey)
        }
        NSApp.activate()
        openSettingsAction?()
    }

    func openPlanner() {
        NSApp.activate()
        openWindowAction?(id: "planner")
    }
}

/// Applies "Show Dock icon" (spec_menubar.md §4).
enum ActivationPolicy {
    static func apply(showDockIcon: Bool, keyWindow: NSWindow?) {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else {
            return
        }
        let window = keyWindow ?? NSApp.keyWindow
        NSApp.setActivationPolicy(policy)
        if !showDockIcon, let window, window.isVisible {
            // Switching to accessory deactivates the app; keep the window key.
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }
}
