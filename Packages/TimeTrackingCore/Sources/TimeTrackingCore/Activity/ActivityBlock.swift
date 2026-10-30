// ActivityBlock: a closed (or today's open) block of activity
// (spec_data_and_sync.md §6, spec_activity_tracking.md §2.6, §2.7, §4.2).

public import Foundation

/// A block of the block log.
///
/// A block lies on one local date (the tracker closes blocks at midnight).
/// `utcOffset` is the offset of the header `tz` in effect when it was
/// written, so its local hour and date do not depend on the reader's zone.
public struct ActivityBlock: Sendable, Hashable, Identifiable {
    /// `<dev>/<start as RFC 3339 with offset>`, e.g.
    /// `macbook/2026-10-28T09:10:00-04:00`.
    public var id: String
    public var start: Date
    public var end: Date
    /// The active seconds, the sum of item seconds before the summary cut.
    public var activeSeconds: Int
    /// The device name, or `remote` for unattributed synced Safari history.
    public var device: String
    public var source: ActivitySource
    /// The dominant group key and its share.
    public var groupKey: String
    public var groupShare: Double
    /// The summary items and the secondaries (`bg`).
    public var items: [ActivityItem]
    public var background: [ActivityItem]
    /// Today's provisional block from `current.json` (Mac only).
    public var isOpen: Bool
    /// Seconds east of UTC of the local times, from the header `tz`.
    public var utcOffset: Int

    public init(
        start: Date,
        end: Date,
        activeSeconds: Int,
        device: String,
        groupKey: String,
        groupShare: Double,
        items: [ActivityItem],
        utcOffset: Int,
        source: ActivitySource = .live,
        background: [ActivityItem] = [],
        isOpen: Bool = false
    ) {
        self.id = Self.makeID(device: device, start: start, utcOffset: utcOffset)
        self.start = start
        self.end = end
        self.activeSeconds = activeSeconds
        self.device = device
        self.source = source
        self.groupKey = groupKey
        self.groupShare = groupShare
        self.items = items
        self.background = background
        self.isOpen = isOpen
        self.utcOffset = utcOffset
    }

    /// The id of the block of `device` starting at `start`, written with `utcOffset`.
    public static func makeID(device: String, start: Date, utcOffset: Int) -> String {
        "\(device)/\(LocalTimestamp(date: start, utcOffset: utcOffset).text)\(LocalTimestamp.offsetText(utcOffset))"
    }

    /// The local date of the block, `YYYY-MM-DD`.
    public var localDay: String {
        LocalTimestamp(date: start, utcOffset: utcOffset).dayKey
    }

    /// The month file the block belongs to, `YYYY-MM`.
    public var month: String {
        LocalTimestamp(date: start, utcOffset: utcOffset).monthKey
    }

    /// The local start hour, 0 to 23.
    public var localStartHour: Int {
        LocalTimestamp(date: start, utcOffset: utcOffset).hour
    }

    /// Every context the block mentions, items first.
    public var contexts: [String] {
        var seen = Set<String>()
        return (items + background).map(\.context).filter { seen.insert($0).inserted }
    }
}
