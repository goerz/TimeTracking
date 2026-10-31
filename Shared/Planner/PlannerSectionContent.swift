// PlannerSectionContent: one Planner section's view, in the Mac's detail
// column and in an iPad tab (spec_planner_projects.md §1.1, spec_ios.md §10.1).

import SwiftUI
import TimeTrackingCore

/// The view of `section`; Projects re-renders every minute for its durations.
struct PlannerSectionContent: View {
    var router: PlannerRouter
    var section: PlannerSection
    var clock: any Clock
    /// Reports' Print… (the Mac's print panel).
    var onPrint: (() -> Void)?

    var body: some View {
        switch section {
        case .calendar:
            CalendarView(model: router.calendar)
        case .reports:
            ReportsView(model: router.reports, onPrint: onPrint)
        case .projects:
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                ProjectsView(model: router.projects, now: clock.now)
            }
        case .clientsAndAreas:
            ClientsAreasView(model: router.projects.clientsAndAreas, projects: router.projects)
        case .activity:
            ActivityView(model: router.activity)
        }
    }
}
