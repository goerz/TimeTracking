// ReportSnapshot: everything the Reports section shows for one range and
// filter, computed in one pass (spec_reports.md §4 to §6).

public import Foundation

/// What the chart's segments stack by.
public enum StackKind: String, Codable, Sendable, CaseIterable {
    case unstacked = "none"
    case client
    case area
    case project

    public var title: String {
        switch self {
        case .unstacked: "None"
        case .client: "Client"
        case .area: "Area"
        case .project: "Project"
        }
    }
}

/// The color of a stack key.
public enum StackColor: Hashable, Sendable {
    /// The accent color (stack by None).
    case accent
    /// One of the eight client colors: blue, orange, green, pink, purple,
    /// teal, yellow, brown.
    case palette(Int)
    /// An area color, already at the project's lightness step; hatched from
    /// the seventh project of an area.
    case area(String, hatched: Bool)
    /// "No client", "No area", "No project".
    case gray
}

/// One key of the stack and legend.
public struct StackKey: Hashable, Sendable, Identifiable {
    public var value: GroupKeyValue
    public var name: String
    public var color: StackColor

    public var id: GroupKeyValue {
        value
    }
}

/// One segment of a bar.
public struct StackSegment: Hashable, Sendable {
    public var key: StackKey
    public var seconds: Int
}

/// One bar of the chart.
public struct ChartBucket: Hashable, Sendable, Identifiable {
    public var period: TrackingPeriod
    /// The bucket's days inside the range.
    public var days: ClosedRange<TrackingDay>
    /// Cut by the range's edge.
    public var isPartial: Bool
    /// Starts after today: an empty slot without bar or label.
    public var isFuture: Bool
    /// Non-zero segments in stack order.
    public var segments: [StackSegment]
    public var total: Int
    /// Days of the bucket up to today.
    public var pastDayCount: Int
    /// The two x-axis lines: "Mon" / "10/26", "W44" / "Oct 26 – Nov 1",
    /// "Oct" / "2026", "2026".
    public var label: [String]
    /// The tooltip's first line: "Monday, October 26", "Week 44 · Oct 26 –
    /// Nov 1", "October 2026", "2026".
    public var title: String
    /// "partial week (3 days)".
    public var partialNote: String?

    public var id: TrackingDay {
        period.start
    }

    /// Week, month, and year tooltips: the total over the past days.
    public var averagePerDay: Int? {
        guard period.granularity != .day else {
            return nil
        }
        return pastDayCount == 0 ? 0 : total / pastDayCount
    }
}

/// The chart card's data.
public struct ReportChart: Hashable, Sendable {
    /// The resolved granularity (never `total`).
    public var granularity: Granularity
    public var buckets: [ChartBucket]
    /// The keys present, in stack order; empty for None.
    public var legend: [StackKey]
    /// The y axis's top in whole hours, at least 1.
    public var axisHours: Int
    /// The average-per-day rule (day granularity only).
    public var averageLine: Int?
    /// Every n-th x label is shown (more than 31 buckets).
    public var labelStride: Int
}

/// The four tiles.
public struct ReportSummary: Hashable, Sendable {
    public var loggedSeconds: Int
    public var entryCount: Int
    /// The running entry is among the matching entries.
    public var includesRunning: Bool
    /// Days with a positive sum.
    public var daysWithEntries: Int
    /// The range's days up to today ("of N").
    public var elapsedDays: Int

    /// Logged time over the days with entries; 0 without any.
    public var averagePerDay: Int {
        daysWithEntries == 0 ? 0 : loggedSeconds / daysWithEntries
    }
}

/// The entry list: matching entries (narrowed to a node's key path) and
/// their total.
public struct ReportEntryList: Hashable, Sendable {
    public var listings: [EntryListing]
    /// The stopped entries' seconds.
    public var stoppedSeconds: Int

    /// The footer total; the running entry counts to `now`.
    public func totalSeconds(at now: Date) -> Int {
        stoppedSeconds + listings.reduce(0) { $0 + ($1.entry.isRunning ? $1.entry.seconds(at: now) : 0) }
    }
}

/// What Reports asks for.
public struct ReportRequest: Hashable, Sendable {
    public var days: ClosedRange<TrackingDay>
    public var today: TrackingDay
    /// Breakdown levels, one to four.
    public var levels: [GroupKey]
    /// `nil` is Automatic.
    public var granularity: Granularity?
    public var stack: StackKind
    public var filter: EntryFilter
    /// A breakdown node's key path that narrows the entry list.
    public var entryPath: [GroupKeyValue]
    /// Whether to list the entries (the list, the Entries export).
    public var includeEntries: Bool

    public init(
        days: ClosedRange<TrackingDay>,
        today: TrackingDay,
        levels: [GroupKey] = [.area, .project, .task],
        granularity: Granularity? = nil,
        stack: StackKind = .area,
        filter: EntryFilter = EntryFilter(),
        entryPath: [GroupKeyValue] = [],
        includeEntries: Bool = true
    ) {
        self.days = days
        self.today = today
        self.levels = levels
        self.granularity = granularity
        self.stack = stack
        self.filter = filter
        self.entryPath = entryPath
        self.includeEntries = includeEntries
    }

    /// The breakdown's query (the CLI's `report` for the same range,
    /// filters, and levels).
    public var query: ReportQuery {
        ReportQuery(days: days, groupBy: levels, granularity: .total, filter: filter)
    }
}

/// Tiles, chart, breakdown, and entry list of one request.
public struct ReportSnapshot: Hashable, Sendable {
    public var request: ReportRequest
    public var summary: ReportSummary
    public var chart: ReportChart
    /// The breakdown in each level's "by name" order.
    public var tree: ReportNode
    public var entries: ReportEntryList
    /// Lightness steps of projects within their areas (chart and bars).
    public var projectSteps: [ProjectID: Int]
    /// The query time.
    public var now: Date

    /// The Breakdown (CSV) export.
    public var breakdownCSV: String {
        ReportCSVWriter.breakdownCSV(tree, levels: request.levels)
    }

    /// The Entries (CSV) export: the listed entries by start.
    public func entriesCSV(timeZone: TimeZone = .current) -> String {
        ReportCSVWriter.entriesCSV(
            entries.listings.sorted { ($0.entry.start, $0.id) < ($1.entry.start, $1.id) },
            now: now,
            timeZone: timeZone
        )
    }
}

extension Granularity {
    /// Automatic: Day up to 31 days, Week up to 182, Month up to 1,096, Year
    /// beyond.
    public static func automatic(dayCount: Int) -> Self {
        switch dayCount {
        case ...31: .day
        case ...182: .week
        case ...1096: .month
        default: .year
        }
    }

    public var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .total: "Total"
        }
    }
}
