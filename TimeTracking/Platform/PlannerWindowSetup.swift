// PlannerWindowSetup: the Planner window's frame autosave and identifier
// (spec_planner_projects.md §1.1).

import AppKit

/// Configures the Planner's `NSWindow` once it hosts the view.
enum PlannerWindowSetup {
    /// The window's identifier, by which `SectionMenuVisibility` finds it.
    static let identifier = "planner"

    /// The frame is restored across launches; the identifier names the window.
    static func configure(_ window: NSWindow) {
        window.setFrameAutosaveName("Planner")
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
    }
}
