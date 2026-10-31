// SectionMenuContent: the section menu's items, on the Mac and the iPad
// (spec_timer_window.md §9).

import SwiftUI
import TimeTrackingCore

/// The commands of the Planner's section, in the menu titled
/// `MenuState.sectionMenuTitle`. The menu always lists them, as SwiftUI
/// menus do; they are enabled only while the Planner is in front.
struct SectionMenuContent: View {
    var router: PlannerRouter
    var state: MenuState

    var body: some View {
        switch state.section {
        case .projects: ProjectMenuContent(model: router.projects, state: state)
        case .calendar: CalendarMenuContent(model: router.calendar, state: state)
        case .reports: ReportMenuContent(model: router.reports, enabled: state.reportCommands)
        case .activity: ActivityMenuContent(model: router.activity, enabled: state.activityCommands)
        }
    }
}
