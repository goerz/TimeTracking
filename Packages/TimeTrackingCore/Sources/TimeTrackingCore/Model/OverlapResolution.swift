// OverlapResolution: the trim/overlap/cancel choice, with CalendarLane's
// side-by-side lanes and CalendarCoverage's coverage of blocks by entries
// (spec_calendar.md §2.6, §3.1, §3.3).

public import Foundation

/// An entry a change would overlap.
public struct OverlapNeighbor: Sendable, Hashable {
    public var id: EntryID
    /// The entry's task, or its project name, or "No task".
    public var title: String
    public var interval: DateInterval

    public init(id: EntryID, title: String, interval: DateInterval) {
        self.id = id
        self.title = title
        self.interval = interval
    }
}

/// The popover of §2.6.
public struct OverlapPrompt: Sendable, Hashable {
    /// The neighbor with the largest overlap.
    public var neighbor: OverlapNeighbor
    public var overlapSeconds: Int
    /// The changed interval shortened to abut the neighbors, or `nil` when
    /// less than a minute would remain (Trim is then unavailable).
    public var trimmed: DateInterval?
    /// The change as asked (Overlap).
    public var proposed: DateInterval

    /// `Overlaps "Standup" (11:00 to 11:30) by 12 min.`
    public func text(in zone: TimeZone) -> String {
        let format = { (date: Date) in
            let local = LocalTimestamp(date: date, utcOffset: zone.secondsFromGMT(for: date))
            return ActivityText.clock(hour: local.hour, minute: local.minute)
        }
        let minutes = max(1, Int((Double(overlapSeconds) / 60).rounded()))
        return "Overlaps \"\(neighbor.title)\" (\(format(neighbor.interval.start)) to \(format(neighbor.interval.end))) by \(minutes) min."
    }
}

/// What a drawing, move, resize, or duplicate does about overlaps.
public enum OverlapResolution: Sendable, Hashable {
    /// No overlap: store as is.
    case clear(DateInterval)
    /// 1 minute or less: shortened without asking.
    case trimmedSilently(DateInterval)
    /// Ask Trim / Overlap / Cancel.
    case ask(OverlapPrompt)

    /// The resolution of changing an entry to `interval` next to `neighbors`.
    public static func resolve(_ interval: DateInterval, neighbors: [OverlapNeighbor]) -> Self {
        let overlapping = neighbors.compactMap { neighbor -> (OverlapNeighbor, TimeInterval)? in
            let overlap = interval.overlapDuration(with: neighbor.interval)
            return overlap > 0 ? (neighbor, overlap) : nil
        }
        guard let largest = overlapping.max(by: { $0.1 < $1.1 }) else {
            return .clear(interval)
        }
        let trimmed = CalendarCoverage.uncovered(interval, by: overlapping.map(\.0.interval))
            .max { $0.duration < $1.duration }
            .flatMap { $0.duration >= CalendarEditing.minimumLength ? $0 : nil }
        if largest.1 <= 60, overlapping.allSatisfy({ $0.1 <= 60 }), let trimmed {
            return .trimmedSilently(trimmed)
        }
        return .ask(OverlapPrompt(neighbor: largest.0, overlapSeconds: Int(largest.1.rounded()), trimmed: trimmed, proposed: interval))
    }
}

/// Where a card sits among overlapping cards (§2.6).
public struct CalendarLane: Sendable, Hashable {
    /// 0-based position from the left.
    public var index: Int
    /// The number of lanes of its cluster; the card is 1/count wide.
    public var count: Int

    public init(index: Int, count: Int) {
        self.index = index
        self.count = count
    }

    /// Lanes for intervals drawn side by side in start order; a cluster
    /// is a run of transitively overlapping intervals.
    public static func assign<ID: Hashable>(_ items: [(id: ID, interval: DateInterval)]) -> [ID: Self] {
        let sorted = items.sorted { ($0.interval.start, $0.interval.end) < ($1.interval.start, $1.interval.end) }
        var result: [ID: Self] = [:]
        var cluster: [(ID, Int)] = []
        var laneEnds: [Date] = []
        var clusterEnd = Date.distantPast
        func flush() {
            for (id, lane) in cluster {
                result[id] = Self(index: lane, count: laneEnds.count)
            }
            cluster = []
            laneEnds = []
        }
        for item in sorted {
            if item.interval.start >= clusterEnd {
                flush()
            }
            let lane = laneEnds.firstIndex { $0 <= item.interval.start } ?? laneEnds.count
            if lane == laneEnds.count {
                laneEnds.append(item.interval.end)
            } else {
                laneEnds[lane] = item.interval.end
            }
            cluster.append((item.id, lane))
            clusterEnd = max(clusterEnd, item.interval.end)
        }
        flush()
        return result
    }

    /// The ids of items overlapping at least one other ("⚠ 2 overlaps").
    public static func overlapping<ID: Hashable>(_ items: [(id: ID, interval: DateInterval)]) -> Set<ID> {
        var result = Set<ID>()
        for (index, item) in items.enumerated() {
            for other in items[(index + 1)...] where item.interval.start < other.interval.end && other.interval.start < item.interval.end {
                result.insert(item.id)
                result.insert(other.id)
            }
        }
        return result
    }
}

/// Coverage of an interval by others (§3.1, §3.3).
public enum CalendarCoverage {
    /// The parts of `interval` covered by none of `others`, in order.
    public static func uncovered(_ interval: DateInterval, by others: [DateInterval]) -> [DateInterval] {
        var pieces = [interval]
        for other in others {
            pieces = pieces.flatMap { piece -> [DateInterval] in
                guard other.start < piece.end, other.end > piece.start else {
                    return [piece]
                }
                var rest: [DateInterval] = []
                if other.start > piece.start {
                    rest.append(DateInterval(start: piece.start, end: other.start))
                }
                if other.end < piece.end {
                    rest.append(DateInterval(start: other.end, end: piece.end))
                }
                return rest
            }
        }
        return pieces
    }

    /// The parts of `interval` covered by `others` (dimmed in the Activity column).
    public static func covered(_ interval: DateInterval, by others: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        var cursor = interval.start
        for piece in uncovered(interval, by: others) {
            if piece.start > cursor {
                result.append(DateInterval(start: cursor, end: piece.start))
            }
            cursor = piece.end
        }
        if cursor < interval.end {
            result.append(DateInterval(start: cursor, end: interval.end))
        }
        return result
    }

    /// A block's longest untracked stretch, clamped at now (§3.3).
    public static func longestUntracked(_ interval: DateInterval, entries: [DateInterval], now: Date) -> DateInterval? {
        guard interval.start < now else {
            return nil
        }
        let clamped = DateInterval(start: interval.start, end: min(interval.end, now))
        return uncovered(clamped, by: entries).filter { $0.duration > 0 }.max { $0.duration < $1.duration }
    }
}
