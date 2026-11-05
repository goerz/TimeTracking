// ReportQuery+AllTime: the query over every day an entry can have, behind
// the tool's `entries` and `continue` (automation.md §3.5, §3.6).

import Foundation

extension ReportQuery {
    /// A query over every day an entry can have, for `entries(matching:)`.
    static func allTime(
        // swiftlint:disable:next discouraged_optional_collection
        projects: Set<ProjectID>? = nil,
        filter: EntryFilter = EntryFilter(),
        around interval: DateInterval? = nil
    ) -> Self {
        var filter = filter
        if let projects {
            filter.projects = projects
        }
        let calendar = TrackingCalendar(timeZone: .gmt)
        let days = interval.map { interval in
            calendar.day(containing: interval.start).adding(days: -2) ... calendar.day(containing: interval.end).adding(days: 2)
        } ?? TrackingDay(year: 1970, month: 1, day: 1) ... TrackingDay(year: 9999, month: 12, day: 31)
        return Self(days: days, groupBy: [], granularity: .total, filter: filter)
    }
}
