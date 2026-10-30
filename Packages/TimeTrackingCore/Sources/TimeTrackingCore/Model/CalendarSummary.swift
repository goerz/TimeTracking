// CalendarSummary: the summary strip and the day headers' totals
// (spec_planner_calendar.md §1.1, §1.4).

public import Foundation

/// The figures over the visible days.
public struct CalendarSummary: Sendable, Hashable {
    /// One project's tracked time in the strip.
    public struct Segment: Sendable, Hashable, Identifiable {
        public var projectID: ProjectID?
        /// "Noise Model", or "No project".
        public var name: String
        /// The area color, `nil` for no project.
        public var color: String?
        public var seconds: Int

        public var id: String {
            projectID?.rawValue ?? "none"
        }
    }

    /// The totals of one day's columns.
    public struct DayTotals: Sendable, Hashable {
        public var activity: Int
        public var tracked: Int
        public var calendar: Int

        /// "6h 38m · 2h 21m · 1h" for the visible columns.
        public func text(columns: [CalendarColumn]) -> [String] {
            columns.map { column in
                switch column {
                case .activity: ActivityText.duration(activity)
                case .tracked: ActivityText.duration(tracked)
                case .calendar: ActivityText.duration(calendar)
                }
            }
        }
    }

    /// Tracked time by project, largest first.
    public var segments: [Segment]
    public var tracked: Int
    /// Time blocks only.
    public var blocks: Int
    /// The tracker's active time.
    public var activity: Int
    public var days: [TrackingDay: DayTotals]

    /// Sums `entries` (the running one up to `now`), activity blocks' `a`,
    /// and time blocks clipped to each day.
    public init(
        days: [TrackingDay],
        calendar: TrackingCalendar,
        entries: [EntryListing],
        activity: [ActivityBlock],
        timeBlocks: [DateInterval],
        now: Date
    ) {
        var totals: [TrackingDay: DayTotals] = [:]
        var byProject: [ProjectID?: Segment] = [:]
        let shown = Set(days)
        for day in days {
            totals[day] = DayTotals(activity: 0, tracked: 0, calendar: 0)
        }
        for listing in entries where shown.contains(listing.entry.day) {
            let seconds = listing.entry.seconds(at: now)
            totals[listing.entry.day]?.tracked += seconds
            let key = listing.entry.projectID
            var segment = byProject[key] ?? Segment(
                projectID: key,
                name: listing.project?.name ?? "No project",
                color: listing.area?.color,
                seconds: 0
            )
            segment.seconds += seconds
            byProject[key] = segment
        }
        for block in activity {
            if let day = TrackingDay(block.localDay), shown.contains(day) {
                totals[day]?.activity += block.activeSeconds
            }
        }
        for day in days {
            let interval = calendar.interval(of: day)
            totals[day]?.calendar = timeBlocks.reduce(0) { sum, block in
                sum + max(0, Int(min(block.end, interval.end).timeIntervalSince(max(block.start, interval.start))))
            }
        }
        self.days = totals
        self.segments = byProject.values.sorted { ($1.seconds, $0.name) < ($0.seconds, $1.name) }
        self.tracked = totals.values.reduce(0) { $0 + $1.tracked }
        self.blocks = totals.values.reduce(0) { $0 + $1.calendar }
        self.activity = totals.values.reduce(0) { $0 + $1.activity }
    }

    /// "Noise Model 2h 15m" for a hovered segment.
    public static func tooltip(_ segment: Segment) -> String {
        "\(segment.name) \(ActivityText.duration(segment.seconds))"
    }
}
