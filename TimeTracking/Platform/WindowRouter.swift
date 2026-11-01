// WindowRouter: showing the Mini Timer, the main window, and Settings
// (spec_timer_window.md §1.3, §8.3; spec_menubar.md §2.2, §4).

import AppKit
import SwiftUI

/// The live `AppRouting`: AppKit for the Mini Timer, the SwiftUI actions
/// captured from a view for the main window and Settings.
final class WindowRouter: AppRouting {
    let timerWindow: TimerWindowController
    weak var app: AppModel?
    /// Captured from the Timer window's environment.
    var openSettingsAction: OpenSettingsAction?
    var openWindowAction: OpenWindowAction?

    init(timerWindow: TimerWindowController) {
        self.timerWindow = timerWindow
    }

    /// The Mini Timer (the former Timer window): brought forward, or
    /// opened the first time.
    func showTimer(focusTask: Bool) {
        if timerWindow.window == nil {
            NSApp.activate()
            openWindowAction?(id: "timer")
        } else {
            timerWindow.show()
        }
        if focusTask {
            app?.miniTimer.focusTaskField()
        }
    }

    /// ⌥⌘R, as for the former Timer window: hides the app while the Mini
    /// Timer is key, else shows it.
    func toggleTimer() {
        if NSApp.isActive, timerWindow.isKey {
            timerWindow.hide()
        } else {
            showTimer(focusTask: true)
        }
    }

    /// The main window on `item`, or on its current item (the Dock tile,
    /// the menu bar).
    func showMainWindow(item: MainSidebarItem?) {
        if let item {
            app?.mainItem = item
        }
        NSApp.activate()
        openWindowAction?(id: MainWindowSetup.sceneID)
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
