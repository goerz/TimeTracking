// Pasteboard: ⌘C in the sections' tables (projects.md §2.5,
// reports.md §7) and the ⌥ state of clicks.

import AppKit

/// Writes plain text to the general pasteboard.
enum Pasteboard {
    static func copy(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
