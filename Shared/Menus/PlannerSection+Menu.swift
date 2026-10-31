// PlannerSection+Menu: the title of each section's menu
// (spec_timer_window.md §9).

import Foundation

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

    /// Every section menu title (the Mac hides the menu by its title).
    static var menuTitles: Set<String> {
        Set(allCases.map(\.menuTitle))
    }
}
