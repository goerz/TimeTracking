// PlannerSection+Menu: each section's menu title and sidebar key
// (spec_timer_window.md §9).

import SwiftUI

extension PlannerSection {
    /// The section menu's title, named for what the section's commands act on.
    var menuTitle: String {
        switch self {
        case .projects: "Project"
        case .calendar: "Calendar"
        case .reports: "Report"
        case .activity: "Activity"
        }
    }

    /// ⌘2 to ⌘5 in the sidebar (Mac) or tab bar (iPad), after the Timer's ⌘1.
    var mainWindowKey: KeyEquivalent {
        KeyEquivalent(Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 2)))
    }
}
