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

    /// Where the Settings window's `@AppStorage` reads its last pane.
    var paneDefaults: UserDefaults = .standard

    func openSettings(pane: SettingsPane?) {
        if let pane {
            paneDefaults.set(pane.rawValue, forKey: SettingsPane.storageKey)
        }
        NSApp.activate()
        openSettingsAction?()
    }

    func openPlanner() {
        NSApp.activate()
        openWindowAction?(id: "planner")
    }
}

/// What `ActivationPolicy` needs of the application; tests pass a fake.
protocol ActivationTarget: AnyObject {
    var keyWindowTarget: (any KeyWindowTarget)? { get }

    func activationPolicy() -> NSApplication.ActivationPolicy
    @discardableResult
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool
    func activate()
}

/// What `ActivationPolicy` needs of a window.
protocol KeyWindowTarget: AnyObject {
    var isVisible: Bool { get }

    func makeKeyAndOrderFront(_ sender: Any?)
}

extension NSApplication: ActivationTarget {
    var keyWindowTarget: (any KeyWindowTarget)? {
        keyWindow
    }
}

extension NSWindow: KeyWindowTarget {}

/// Applies "Show Dock icon" (spec_menubar.md §4).
enum ActivationPolicy {
    static func apply(showDockIcon: Bool, keyWindow: (any KeyWindowTarget)?, application: any ActivationTarget = NSApp) {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        guard application.activationPolicy() != policy else {
            return
        }
        let window = keyWindow ?? application.keyWindowTarget
        application.setActivationPolicy(policy)
        if !showDockIcon, let window, window.isVisible {
            // Switching to accessory deactivates the app; keep the window key.
            application.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }
}
