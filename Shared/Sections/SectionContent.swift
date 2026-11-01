// SectionContent: one section's view, in the Mac's detail
// column and in an iPad tab (spec_projects.md §1.1, spec_ios.md §10.1).

import SwiftUI
import TimeTrackingCore

/// The view of `section`; Projects re-renders every minute for its durations.
struct SectionContent: View {
    var router: SectionRouter
    var section: MainSection
    var clock: any Clock

    var body: some View {
        switch section {
        case .calendar:
            CalendarView(model: router.calendar)
        case .reports:
            ReportsView(model: router.reports)
        case .projects:
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                ProjectsView(model: router.projects, now: clock.now)
            }
        case .activity:
            ActivityView(model: router.activity)
        }
    }
}
