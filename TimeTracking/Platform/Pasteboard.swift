// Pasteboard: ⌘C in the Planner's tables (spec_planner_projects.md §2.5,
// spec_planner_reports.md §7) and the ⌥ state of clicks.

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
