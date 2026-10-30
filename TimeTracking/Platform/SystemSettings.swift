// SystemSettings: opening System Settings panes, Finder, and the pasteboard
// for the settings panes (spec_activity_tracking.md §7.4, spec_timer_window.md §8.1).

import AppKit

/// Workspace actions of the settings panes.
enum SystemSettings {
    /// A Privacy & Security pane, e.g. `Privacy_Accessibility`.
    static func openPrivacy(_ anchor: String) {
        open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"))
    }

    /// The app's Notifications settings.
    static func openNotifications() {
        let id = Bundle.main.bundleIdentifier ?? ""
        open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)"))
    }

    /// "Show Tracker in Finder": reveals `TimeTrackingAgent.app`.
    static func revealAgent() {
        reveal(Bundle.main.bundleURL.appending(path: "Contents/Library/LoginItems/TimeTrackingAgent.app"))
    }

    static func open(_ url: URL?) {
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    static func reveal(_ url: URL?) {
        if let url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
