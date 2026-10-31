// SectionMenuVisibility: the section menu exists only while the Planner is
// in front (spec_timer_window.md §9).

import AppKit

/// Hides the main menu's section menu (Project, Calendar, Report, or
/// Activity) unless the key window is the Planner or one of its sheets or
/// popovers. SwiftUI keeps a menu whose items are all conditional as an
/// empty title, so the menu bar item is hidden here; SwiftUI updates the
/// same item when the title changes, and the check runs after every event,
/// so a rebuilt menu is hidden too. The key window decides, not the main
/// window: the Timer window does not become main.
@MainActor
enum SectionMenuVisibility {
    private static var observer: NSObjectProtocol?

    static func start() {
        guard observer == nil else {
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didUpdateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { apply() }
        }
    }

    private static func apply() {
        var window = NSApp.keyWindow
        while let owner = window?.sheetParent ?? window?.parent {
            window = owner
        }
        let hidden = window?.identifier?.rawValue != PlannerWindowSetup.identifier
        let titles = PlannerSection.menuTitles
        for item in NSApp.mainMenu?.items ?? [] where titles.contains(item.title) && item.isHidden != hidden {
            item.isHidden = hidden
        }
    }
}
