// SectionRouter+URL: the section URLs (`timetracking://planner/…`) of
// spec_automation.md §6 (Mac: the main window; iPad: the tabs, spec_ios.md
// §6.4).

import Foundation
import TimeTrackingCore

extension SectionRouter {
    /// Shows the section and state a section URL names; `false` for a URL
    /// that is not one.
    @discardableResult
    func open(_ url: TimeTrackingURL, now: Date) async -> Bool {
        switch url {
        case let .calendar(date):
            showCalendar(day: date ?? TrackingCalendar(timeZone: .current).day(containing: now))
        case let .reports(from, to):
            await showReports(range: Self.range(from: from, to: to), filter: ReportFilters())
        case .projects:
            showProjects()
        case let .activity(date):
            showActivity(range: date.map { ReportRange.days($0, $0) })
        case let .project(id):
            await showProject(id)
        case .start, .stop, .continue, .show:
            return false
        }
        return true
    }

    /// `from` and `to` of a reports URL (`to` excluded) as a range.
    static func range(from: TrackingDay?, to: TrackingDay?) -> ReportRange? {
        guard let from else {
            return nil
        }
        let last = to.map { $0.adding(days: -1) } ?? from
        return .days(from, max(from, last))
    }
}
