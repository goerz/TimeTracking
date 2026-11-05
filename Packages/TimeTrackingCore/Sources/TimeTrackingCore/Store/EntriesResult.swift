// EntriesResult: the entries the tool's `entries` lists, with their day
// subtotals (automation.md §3.6).

public import Foundation

/// Entries of a range with their day subtotals.
public struct EntriesResult: Hashable, Sendable {
    /// The range; `nil` for all time or `--running`.
    public var range: DayRange?
    public var listings: [EntryListing]
    public var now: Date
    /// Seconds of all listed entries, the running one up to `now`.
    public var totalSeconds: Int
    /// Per day of the listed entries' starts, in listing order.
    public var days: [(day: TrackingDay, seconds: Int)]

    public init(range: DayRange?, listings: [EntryListing], now: Date, calendar: TrackingCalendar) {
        self.range = range
        self.listings = listings
        self.now = now
        self.totalSeconds = listings.reduce(0) { $0 + $1.entry.seconds(at: now) }
        var days: [(day: TrackingDay, seconds: Int)] = []
        for listing in listings {
            let day = calendar.day(containing: listing.entry.start)
            if days.last?.day == day {
                days[days.count - 1].seconds += listing.entry.seconds(at: now)
            } else {
                days.append((day, listing.entry.seconds(at: now)))
            }
        }
        self.days = days
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.range == rhs.range && lhs.listings == rhs.listings && lhs.now == rhs.now
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(range)
        hasher.combine(listings)
    }
}
