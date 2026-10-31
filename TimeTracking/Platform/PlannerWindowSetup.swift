// PlannerWindowSetup: the Planner window's frame autosave and identifier
// (spec_planner_projects.md §1.1).

import AppKit

/// Configures the Planner's `NSWindow` once it hosts the view.
enum PlannerWindowSetup {
    /// The frame is restored across launches; the identifier names the window.
    static func configure(_ window: NSWindow) {
        window.setFrameAutosaveName("Planner")
        window.identifier = NSUserInterfaceItemIdentifier("planner")
    }
}
