// MainWindowSetup: the main window's scene id, frame autosave, and
// identifier (projects.md §1.1).

import AppKit

/// Configures the main window's `NSWindow` once it hosts the view.
enum MainWindowSetup {
    /// The scene and window identifier. "planner" and the autosave name
    /// "Planner" predate the one window and are kept, so the saved frame
    /// and the window's restoration state carry over.
    static let sceneID = "planner"
    private static let frameAutosaveName = "Planner"

    /// The frame is restored across launches; the identifier names the window.
    static func configure(_ window: NSWindow) {
        window.setFrameAutosaveName(frameAutosaveName)
        window.identifier = NSUserInterfaceItemIdentifier(sceneID)
    }
}
