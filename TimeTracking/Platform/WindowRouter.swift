// WindowRouter: showing the Mini Timer, the main window, and Settings
// (spec_timer.md §1.3, §8.3; spec_menubar.md §2.2, §4).

import AppKit
import SwiftUI
import TimeTrackingCore

/// The live `AppRouting`: AppKit for the Mini Timer once it exists,
/// SwiftUI's default `openWindow` and `openSettings` for the scenes.
///
/// SwiftUI windows open only through these actions, which SwiftUI normally
/// hands to the views it shows. Most callers here are not SwiftUI views
/// (the AppKit status item, the Dock tile, the global shortcut,
/// notifications, URLs, the launch itself), so the router can't take the
/// actions from a view. It used to borrow them from the main window's view,
/// which forced that window open at every launch and left every caller
/// unable to open anything when the window didn't appear.
final class WindowRouter: AppRouting {
    let miniTimerWindow: MiniTimerController
    weak var app: AppModel?

    init(miniTimerWindow: MiniTimerController) {
        self.miniTimerWindow = miniTimerWindow
    }

    /// The Mini Timer: brought forward, or
    /// opened the first time.
    func showTimer(focusTask: Bool) {
        if miniTimerWindow.window == nil {
            NSApp.activate()
            Self.openWindow(id: "timer")
        } else {
            miniTimerWindow.show()
        }
        if focusTask {
            app?.miniTimer.focusTaskField()
        }
    }

    /// ⌥⌘R: hides the app while the Mini
    /// Timer is key, else shows it.
    func toggleTimer() {
        if NSApp.isActive, miniTimerWindow.isKey {
            miniTimerWindow.hide()
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
        Self.openWindow(id: MainWindowSetup.sceneID)
    }

    /// Where the Settings window's `@AppStorage` reads its last pane.
    var paneDefaults: UserDefaults = .standard

    func openSettings(pane: SettingsPane?) {
        if let pane {
            paneDefaults.set(pane.rawValue, forKey: SettingsPane.storageKey)
        }
        NSApp.activate()
        Self.scenes.openSettings()
    }

    /// Opens the scene `id`; also before the router exists (the main
    /// window with a launch's failure).
    static func openWindow(id: String) {
        scenes.openWindow(id: id)
    }

    /// The default environment, made here instead of read from a view.
    /// Apple's documentation calls creating `EnvironmentValues` yourself
    /// atypical, because its values (color scheme, text size) are defaults
    /// that don't follow the system; it doesn't say what `openWindow` and
    /// `openSettings` do in it. On macOS 27 they open the app's scenes with
    /// no window on screen, also during launch, which is all the router
    /// needs: the actions act for the whole app, not for one window (the
    /// ones once borrowed from the main window kept working after it
    /// closed). Should a later SwiftUI stop this, nothing opens, every time,
    /// and every UI test that opens a window fails; the documented
    /// alternative is a `MenuBarExtra` whose label hands its actions over
    /// (it can't show the Pomodoro glyph or the styled menu header).
    private static var scenes: EnvironmentValues {
        EnvironmentValues()
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
