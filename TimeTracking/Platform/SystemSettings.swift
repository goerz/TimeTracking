// SystemSettings: opening System Settings panes, Finder, and a text editor
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

    /// Opens a folder in a Finder window. For the shared `Activity/` folder
    /// this replaces `reveal(_:)`: it lies in the iCloud Drive container
    /// outside `Documents/`, where Finder silently ignores a request to
    /// select an item, but it still opens the folder itself.
    static func showFolder(_ url: URL?) {
        open(url)
    }

    /// Opens a text file in the app the user chose for its type, or in
    /// TextEdit when no app claims it (as for `.toml` on a fresh Mac).
    static func openInEditor(_ url: URL?) {
        guard let url else {
            return
        }
        let workspace = NSWorkspace.shared
        let editor = workspace.urlForApplication(toOpen: url)
            ?? workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
        guard let editor else {
            workspace.open(url)
            return
        }
        workspace.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }
}
