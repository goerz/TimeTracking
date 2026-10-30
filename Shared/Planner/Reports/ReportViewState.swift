// ReportViewState: what the Reports section stores per device
// (spec_planner_reports.md §9).

import Foundation
import TimeTrackingCore

/// The lower card's segmented control.
nonisolated enum ReportCard: String, Codable, Sendable {
    case breakdown
    case entries
}

/// The entry list's sortable columns.
nonisolated enum EntryListColumn: String, Codable, Sendable, CaseIterable {
    case date
    case start
    case stop
    case duration
    case client
    case project
    case task
}

/// Filters, granularity, stack key, levels, sorts, and the card.
nonisolated struct ReportViewState: Codable, Equatable, Sendable {
    var filters = ReportFilters()
    /// `nil` is Automatic.
    var granularity: Granularity?
    var stack: StackKind = .area
    var levels: [GroupKey] = [.area, .project, .task]
    var tableSort: ReportColumn = .loggedTime
    var tableAscending = false
    var listSort: EntryListColumn = .date
    var listAscending = false
    var card: ReportCard = .breakdown
}
