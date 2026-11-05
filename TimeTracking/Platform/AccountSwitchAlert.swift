// AccountSwitchAlert: the confirmation before a switch to another iCloud
// account empties the store (data_and_sync.md §3.1 item 5).

import AppKit

/// Asks whether to replace this Mac's data with the new account's.
enum AccountSwitchAlert {
    static func confirm() -> Bool {
        let alert = NSAlert()
        alert.messageText = "You signed in to a different iCloud account."
        alert.informativeText = """
        To sync with the new account, the entries, projects, and settings on this Mac are removed and replaced with \
        the new account's data. Export a backup first if you need it. Without replacing, this Mac stops syncing.
        """
        alert.addButton(withTitle: "Replace Data")
        alert.addButton(withTitle: "Stop Syncing")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
