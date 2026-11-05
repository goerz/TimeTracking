// TimerListDay: the days of the Timer's list (spec_timer.md §3).

public import Foundation
import GRDB

/// One day of the Timer list: its stopped entries, newest first, and the
/// running entry when it belongs to the day and matches the filter. The
/// running entry shows as the day's first row (not selectable, no continue
/// button) and counts toward the total.
public struct TimerListDay: Hashable, Sendable, Identifiable {
    public var day: TrackingDay
    /// The stopped entries, newest first.
    public var rows: [EntryListing]
    /// The seconds of `rows`.
    public var stoppedSeconds: Int
    /// The running entry with its project, client, and area.
    public var runningListing: EntryListing?

    public init(day: TrackingDay, rows: [EntryListing], stoppedSeconds: Int, runningListing: EntryListing?) {
        self.day = day
        self.rows = rows
        self.stoppedSeconds = stoppedSeconds
        self.runningListing = runningListing
    }

    /// The running entry, if it belongs to the day.
    public var running: TimeEntry? {
        runningListing?.entry
    }

    public var id: TrackingDay {
        day
    }

    /// The day total at `now`, the running entry included.
    public func totalSeconds(at now: Date) -> Int {
        stoppedSeconds + (running?.seconds(at: now) ?? 0)
    }
}

extension TimeStore {
    /// The `limit` most recent days with a piece of a live entry, newest
    /// first. An entry lies on every day from its start to its end, so the
    /// entries are read by their end, the latest first, until the rest
    /// cannot reach the days found.
    public func entryDays(limit: Int) throws -> [TrackingDay] {
        let calendar = displayCalendar(timeZone: timeZone())
        let now = clock.now
        var days: Set<TrackingDay> = []
        var latest: [TrackingDay] = []
        try read { database in
            let rows = try Row.fetchCursor(
                database,
                sql: "SELECT * FROM time_entry WHERE deleted_at IS NULL ORDER BY COALESCE(\"end\", ?) DESC, id",
                arguments: [Time.seconds(now)]
            )
            while let row = try rows.next() {
                let entry = TimeEntry(row: row)
                if latest.count >= limit, let last = latest.last, (entry.end ?? now) < calendar.reach(of: last ... last).start {
                    break
                }
                days.formUnion(calendar.pieces(of: entry, at: now).map(\.day))
                latest = Array(days.sorted(by: >).prefix(max(limit, 0)))
            }
        }
        return latest
    }

    /// The Timer's list: the `dayLimit` most recent days with
    /// entries, newest first; empty days are omitted. A non-empty `filter`
    /// keeps entries whose task, project, client, or area contains it (case-
    /// and diacritic-insensitive), and day totals sum what is kept.
    public func timerList(dayLimit: Int, filter: String = "") throws -> [TimerListDay] {
        let days = try entryDays(limit: dayLimit)
        guard let first = days.last, let last = days.first else {
            return []
        }
        let wanted = Set(days)
        let needle = filter.folded
        let calendar = displayCalendar(timeZone: timeZone())
        let listings = try shownListings(days: first ... last, in: calendar)
            .filter { wanted.contains($0.entry.day) && (needle.isEmpty || Self.listing($0, contains: needle)) }
            .anchoringEditors()
        let byDay = Dictionary(grouping: listings, by: \.entry.day)
        return days.compactMap { day in
            let all = byDay[day] ?? []
            let stopped = all.filter { !$0.entry.isRunning }.sorted { ($0.entry.start, $0.id) > ($1.entry.start, $1.id) }
            let running = all.first(where: \.entry.isRunning)
            guard !stopped.isEmpty || running != nil else {
                return nil
            }
            let seconds = stopped.reduce(0) { $0 + $1.entry.seconds(at: clock.now) }
            return TimerListDay(day: day, rows: stopped, stoppedSeconds: seconds, runningListing: running)
        }
    }

    /// The pieces lying on `days` in `calendar`, with their names.
    func shownListings(days: ClosedRange<TrackingDay>, in calendar: TrackingCalendar) throws -> [EntryListing] {
        try listings(for: entries(reaching: days, in: calendar))
            .flatMap { $0.pieces(in: calendar, at: clock.now) }
            .filter { days.contains($0.entry.day) }
    }

    static func listing(_ listing: EntryListing, contains needle: String) -> Bool {
        [listing.entry.task, listing.project?.name, listing.client?.name, listing.area?.name]
            .contains { $0?.folded.contains(needle) ?? false }
    }
}
