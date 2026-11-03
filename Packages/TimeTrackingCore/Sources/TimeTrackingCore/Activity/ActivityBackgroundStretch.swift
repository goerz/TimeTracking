// ActivityBackgroundStretch: background work while the user was away
// (spec_activity_tracking.md §2.7, §4.2).

public import Foundation

/// A stretch of background work outside every block: busy coding agents and
/// running jobs while the user was away.
///
/// A stretch lies on one local date and overlaps no block. Its items are
/// background items with their seconds, in order of first appearance.
public struct ActivityBackgroundStretch: Sendable, Hashable, Identifiable {
    /// The start as RFC 3339 with offset, like a block's id.
    public var id: String
    public var start: Date
    public var end: Date
    public var items: [ActivityItem]
    /// Seconds east of UTC of the local times, from the header `tz`.
    public var utcOffset: Int

    public init(start: Date, end: Date, items: [ActivityItem], utcOffset: Int) {
        self.id = ActivityBlock.makeID(start: start, utcOffset: utcOffset)
        self.start = start
        self.end = end
        self.items = items
        self.utcOffset = utcOffset
    }

    /// The local date of the stretch, `YYYY-MM-DD`.
    public var localDay: String {
        LocalTimestamp(date: start, utcOffset: utcOffset).dayKey
    }

    /// The month file the stretch belongs to, `YYYY-MM`.
    public var month: String {
        LocalTimestamp(date: start, utcOffset: utcOffset).monthKey
    }

    /// Every context the stretch mentions.
    public var contexts: [String] {
        var seen = Set<String>()
        return items.map(\.context).filter { seen.insert($0).inserted }
    }

    // `nil` devices means every device, which an empty set cannot express.
    // swiftlint:disable discouraged_optional_collection
    /// The stretch with only the items on `devices`; `nil` when none is left.
    public func part(on devices: Set<String>?) -> Self? {
        guard let devices else {
            return self
        }
        var result = self
        result.items = items.filter { devices.contains($0.device) }
        return result.items.isEmpty ? nil : result
    }
    // swiftlint:enable discouraged_optional_collection
}
