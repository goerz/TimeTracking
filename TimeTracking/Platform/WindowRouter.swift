// WindowRouter: showing the Mini Timer, the main window, and Settings
// (spec_timer.md §1.3, §8.3; spec_menubar.md §2.2, §4).

import AppKit
import os
import SwiftUI
import TimeTrackingCore

/// The live `AppRouting`: AppKit for the Mini Timer, the SwiftUI actions
/// captured from a view for the main window and Settings.
final class WindowRouter: AppRouting {
    let miniTimerWindow: MiniTimerController
    weak var app: AppModel?
    /// Captured from a scene's environment (`RouterActions`).
    var openSettingsAction: OpenSettingsAction?
    var openWindowAction: OpenWindowAction? {
        didSet { openPending() }
    }

    /// Scenes asked for before any view handed over `openWindowAction`.
    private var pendingWindowIDs: [String] = []

    init(miniTimerWindow: MiniTimerController) {
        self.miniTimerWindow = miniTimerWindow
    }

    private static let logger = Logging.logger(category: "App")

    /// The Mini Timer: brought forward, or
    /// opened the first time.
    func showTimer(focusTask: Bool) {
        if miniTimerWindow.window == nil {
            NSApp.activate()
            open(id: "timer")
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
        open(id: MainWindowSetup.sceneID)
    }

    /// Before the main window's view has handed over its actions (early in
    /// a launch), the request waits for them.
    private func open(id: String) {
        guard let openWindowAction else {
            if !pendingWindowIDs.contains(id) {
                pendingWindowIDs.append(id)
            }
            return
        }
        openWindowAction(id: id)
    }

    /// The actions arrive in a view's `onAppear`, inside a SwiftUI update
    /// that would drop a window opened there; the next turn opens it.
    private func openPending() {
        guard openWindowAction != nil, !pendingWindowIDs.isEmpty else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self, let openWindowAction else {
                return
            }
            let ids = pendingWindowIDs
            pendingWindowIDs = []
            for id in ids {
                Self.logger.notice("Opening \(id, privacy: .public) at launch")
                openWindowAction(id: id)
            }
        }
    }

    /// Where the Settings window's `@AppStorage` reads its last pane.
    var paneDefaults: UserDefaults = .standard

    func openSettings(pane: SettingsPane?) {
        if let pane {
            paneDefaults.set(pane.rawValue, forKey: SettingsPane.storageKey)
        }
        NSApp.activate()
        guard let openSettingsAction else {
            Self.logger.fault("No openSettings action")
            return
        }
        openSettingsAction()
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
