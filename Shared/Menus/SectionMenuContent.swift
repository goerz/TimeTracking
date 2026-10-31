// SectionMenuContent: the section menu's items, on the Mac and the iPad
// (spec_timer_window.md §9).

import SwiftUI
import TimeTrackingCore

/// The commands of the Planner section shown, in the menu titled
/// `MenuState.sectionMenuTitle`. Without the Planner in front the menu is
/// empty (and the Mac hides it).
struct SectionMenuContent: View {
    var router: PlannerRouter
    var state: MenuState

    var body: some View {
        if state.plannerKey {
            switch state.section {
            case .projects: ProjectMenuContent(model: router.projects, state: state)
            case .calendar: CalendarMenuContent(model: router.calendar, state: state)
            case .reports: ReportMenuContent(model: router.reports, enabled: state.reportCommands)
            case .activity: ActivityMenuContent(model: router.activity, enabled: state.activityCommands)
            }
        }
    }
}
