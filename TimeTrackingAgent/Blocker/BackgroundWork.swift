// BackgroundWork: assigning background items to blocks and to background
// stretches (activity_tracking.md §2.7).

import Foundation
import TimeTrackingCore

/// Assigns the time of background items by where it falls: inside a
/// block's range to that block's `bg`, elsewhere to a background stretch.
///
/// Every Mac sample, attentive or not, credits each of its background items
/// with the time up to the next Mac sample, at most `creditCap`; another
/// device's use during the Mac's attention counts for its covered time. A
/// block lists the items with at least `minimumSeconds` in its range.
/// Outside the blocks, the pieces form stretches: a gap of `idle_close` or
/// more, a block, or local midnight separates them. A stretch keeps the
/// items with at least `minimumSeconds` and spans their pieces; without
/// such an item it is not recorded. Without `flush`, a stretch whose last
/// piece ended less than `idle_close` before `until` is still open and not
/// recorded yet.
nonisolated enum BackgroundWork {
    /// The least time a background item needs to be listed.
    static let minimumSeconds = 300
    /// The most one sample credits.
    static let creditCap = Blocker.defaultCreditCap

    /// A stretch for the block log, with the context map of its items.
    struct Stretch: Hashable, Sendable {
        var stretch: ActivityBackgroundStretch
        var contexts: [String: String]
    }

    /// The background items of each block (by id) and of the open block,
    /// the contexts they add, and the stretches outside the blocks.
    struct Result: Sendable {
        var blockItems: [ActivityBlock.ID: [ActivityItem]] = [:]
        var openItems: [ActivityItem] = []
        var contexts: [String: String] = [:]
        var stretches: [Stretch] = []
    }

    /// Where the day's stream ends and how it is cut: `until` is now for
    /// today; `flush` closes everything (a past day, a replay).
    struct Frame: Sendable {
        var until: Date?
        var flush: Bool
        var idleClose: TimeInterval
        var timeZone: TimeZone
        var mac: String
    }

    /// A credited interval of one background item.
    struct Piece: Hashable, Sendable {
        var start: Date
        var end: Date
        var item: SampleItem
        var device: String

        var seconds: Int {
            Int(end.timeIntervalSince(start).rounded())
        }
    }

    /// Assigns the background time of `samples` (the Mac's live samples of
    /// the day, oldest first) and of `covered` (other devices' use during
    /// the Mac's attention) to `blocks`, the open block from `openStart` to
    /// `frame.until`, and stretches.
    static func assign(
        samples: [Sample],
        covered: [TimelineStretch],
        blocks: [ActivityBlock],
        openStart: Date?,
        frame: Frame
    ) -> Result {
        let (until, flush, idleClose, timeZone, mac) = (frame.until, frame.flush, frame.idleClose, frame.timeZone, frame.mac)
        let pieces = credited(samples, end: flush ? nil : until, mac: mac)
            + covered.map { Piece(start: $0.start, end: $0.end, item: $0.item, device: $0.device) }
        var ranges = blocks.map { (id: Optional($0.id), interval: DateInterval(start: $0.start, end: max($0.start, $0.end))) }
        if let openStart, let until, until > openStart {
            ranges.append((id: nil, interval: DateInterval(start: openStart, end: until)))
        }
        ranges.sort { $0.interval.start < $1.interval.start }

        var result = Result()
        var inside: [ActivityBlock.ID?: [Piece]] = [:]
        var outside: [Piece] = []
        for piece in pieces where piece.end > piece.start {
            var start = piece.start
            for range in ranges where range.interval.end > start && range.interval.start < piece.end {
                if range.interval.start > start {
                    outside.append(clipped(piece, start, range.interval.start))
                }
                inside[range.id, default: []].append(clipped(piece, max(start, range.interval.start), min(piece.end, range.interval.end)))
                start = min(piece.end, range.interval.end)
            }
            if start < piece.end {
                outside.append(clipped(piece, start, piece.end))
            }
        }
        for (id, members) in inside {
            let items = summed(members).filter { $0.seconds >= minimumSeconds }
            if let id {
                result.blockItems[id] = items
            } else {
                result.openItems = items
            }
        }
        for piece in pieces where result.contexts[piece.item.context] == nil {
            result.contexts[piece.item.context] = piece.item.app
        }
        let stretchEnd = flush ? nil : until.map { $0.addingTimeInterval(-idleClose) }
        result.stretches = groups(
            outside.flatMap { splitAtMidnight($0, timeZone: timeZone) },
            ranges: ranges.map(\.interval),
            idleClose: idleClose,
            timeZone: timeZone
        ).compactMap { group in
            guard let last = group.map(\.end).max(), stretchEnd.map({ last <= $0 }) ?? true else {
                return nil
            }
            return stretch(of: group, timeZone: timeZone, contexts: result.contexts)
        }
        return result
    }

    /// Each sample's background items credited up to the next sample (at
    /// most `creditCap`); the last sample up to `end`, or not at all.
    static func credited(_ samples: [Sample], end: Date?, mac: String) -> [Piece] {
        var result: [Piece] = []
        for (index, sample) in samples.enumerated() where !sample.secondaries.isEmpty {
            let next = index + 1 < samples.count ? samples[index + 1].time : (end ?? sample.time)
            let length = min(creditCap, max(0, next.timeIntervalSince(sample.time)))
            guard length > 0 else {
                continue
            }
            for item in sample.secondaries {
                result.append(Piece(start: sample.time, end: sample.time.addingTimeInterval(length), item: item, device: mac))
            }
        }
        return result
    }

    private static func clipped(_ piece: Piece, _ start: Date, _ end: Date) -> Piece {
        var result = piece
        result.start = start
        result.end = end
        return result
    }

    /// `piece` cut at every local midnight within it.
    private static func splitAtMidnight(_ piece: Piece, timeZone: TimeZone) -> [Piece] {
        var result: [Piece] = []
        var start = piece.start
        while start < piece.end {
            let midnight = ActivityTimestamp.nextMidnight(after: start, timeZone: timeZone)
            let end = min(piece.end, midnight)
            result.append(clipped(piece, start, end))
            start = end
        }
        return result
    }

    /// The pieces in runs: a new run starts after a gap of `idleClose` or
    /// more, at a block, or on another local date.
    private static func groups(_ pieces: [Piece], ranges: [DateInterval], idleClose: TimeInterval, timeZone: TimeZone) -> [[Piece]] {
        var result: [[Piece]] = []
        var end = Date.distantPast
        for piece in pieces.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            let day = ActivityTimestamp.startOfDay(piece.start, timeZone: timeZone)
            let separated = result.isEmpty || piece.start.timeIntervalSince(end) >= idleClose
                || ranges.contains { $0.start >= end && $0.start <= piece.start }
                || result.last.flatMap(\.first).map { ActivityTimestamp.startOfDay($0.start, timeZone: timeZone) != day } ?? false
            if separated {
                result.append([piece])
            } else {
                result[result.count - 1].append(piece)
            }
            end = max(end, piece.end)
        }
        return result
    }

    /// The stretch of one run, or `nil` when no item reaches `minimumSeconds`.
    private static func stretch(of group: [Piece], timeZone: TimeZone, contexts: [String: String]) -> Stretch? {
        let items = summed(group).filter { $0.seconds >= minimumSeconds }
        let kept = Set(items.map { ItemKey(context: $0.context, subject: $0.subject, detail: $0.detail, device: $0.device) })
        let members = group.filter { kept.contains(key(of: $0)) }
        guard let start = members.map(\.start).min(), let end = members.map(\.end).max() else {
            return nil
        }
        let stretch = ActivityBackgroundStretch(
            start: start,
            end: end,
            items: items,
            utcOffset: timeZone.secondsFromGMT(for: start)
        )
        return Stretch(stretch: stretch, contexts: contexts.filter { context, _ in stretch.contexts.contains(context) })
    }

    /// Seconds per item and device, in order of first appearance.
    private static func summed(_ pieces: [Piece]) -> [ActivityItem] {
        var result: [ActivityItem] = []
        var index: [ItemKey: Int] = [:]
        for piece in pieces.sorted(by: { $0.start < $1.start }) {
            let key = key(of: piece)
            if let position = index[key] {
                result[position].seconds += piece.seconds
            } else {
                index[key] = result.count
                result.append(ActivityItem(
                    context: key.context,
                    subject: key.subject,
                    detail: key.detail,
                    seconds: piece.seconds,
                    device: piece.device
                ))
            }
        }
        return result
    }

    private static func key(of piece: Piece) -> ItemKey {
        var key = piece.item.key
        key.device = piece.device
        return key
    }
}
