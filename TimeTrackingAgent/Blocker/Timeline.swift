// Timeline: one list of blocks for the user across the Mac, iPhone and
// iPad, and synced Safari history (spec_activity_tracking.md §2.8).

import Foundation
import TimeTrackingCore

/// The rank of a block's source and the arithmetic of claimed time.
///
/// The Mac's own blocks (`live` and `knowledge`) rank highest, then
/// `device` blocks from the iOS app, then synced Safari history. A source
/// only covers the time that no higher-ranked block claims.
nonisolated enum Timeline {
    static let mac = 2
    static let device = 1
    static let remote = 0

    /// The rank of `block` on the Mac named `mac`.
    static func rank(_ block: ActivityBlock, mac name: String) -> Int {
        if block.device == name {
            return mac
        }
        return block.source == .device ? device : remote
    }

    /// Whether `interval` shares more than an instant with one of `claimed`.
    static func overlaps(_ interval: DateInterval, _ claimed: [DateInterval]) -> Bool {
        claimed.contains { $0.start < interval.end && $0.end > interval.start }
    }

    /// The parts of `interval` outside every one of `claimed`, in order.
    static func free(_ interval: DateInterval, outside claimed: [DateInterval]) -> [DateInterval] {
        var pieces = [interval]
        for claim in claimed.sorted(by: { $0.start < $1.start }) {
            pieces = pieces.flatMap { piece -> [DateInterval] in
                guard claim.start < piece.end, claim.end > piece.start else {
                    return [piece]
                }
                var rest: [DateInterval] = []
                if claim.start > piece.start {
                    rest.append(DateInterval(start: piece.start, end: claim.start))
                }
                if claim.end < piece.end {
                    rest.append(DateInterval(start: claim.end, end: piece.end))
                }
                return rest
            }
        }
        return pieces
    }

    /// `block` without the claimed time: one block per free part, its
    /// seconds and those of `detailItems` scaled by the part's share of the
    /// block's length; parts shorter than `minBlock` are dropped.
    static func clipped(
        _ block: ActivityBlock,
        detailItems: [ActivityItem],
        outside claimed: [DateInterval],
        minBlock: TimeInterval
    ) -> [(block: ActivityBlock, detailItems: [ActivityItem])] {
        let whole = DateInterval(start: block.start, end: max(block.start, block.end))
        let length = whole.duration
        guard length > 0 else {
            return []
        }
        return free(whole, outside: claimed).compactMap { part in
            guard part.duration >= minBlock else {
                return nil
            }
            let share = part.duration / length
            func scaled(_ items: [ActivityItem]) -> [ActivityItem] {
                items.compactMap { item in
                    let seconds = Int((Double(item.seconds) * share).rounded())
                    guard seconds > 0 else {
                        return nil
                    }
                    return ActivityItem(context: item.context, subject: item.subject, detail: item.detail, seconds: seconds)
                }
            }
            let active = Int((Double(block.activeSeconds) * share).rounded())
            guard active > 0 else {
                return nil
            }
            let piece = ActivityBlock(
                start: part.start,
                end: part.end,
                activeSeconds: active,
                device: block.device,
                groupKey: block.groupKey,
                groupShare: block.groupShare,
                items: scaled(block.items),
                utcOffset: block.utcOffset,
                source: block.source,
                background: scaled(block.background)
            )
            return (piece, scaled(detailItems))
        }
    }
}
