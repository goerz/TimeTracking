// ClosedBlock: what the Blocker hands to the logs (spec_activity_tracking.md
// §2.6, §2.7, §4.2, §4.3).

import TimeTrackingCore

/// A block the Blocker closed: the summary for the block log, the uncut
/// items for the detail log, and the context map for the header.
nonisolated struct ClosedBlock: Hashable, Sendable {
    var block: ActivityBlock
    var detailItems: [ActivityItem]
    var contexts: [String: String]
    /// Whether this block is the previous block of the same stream with a
    /// short block merged into it (same start, so the same id): the
    /// previous line is replaced, not kept.
    var replacesPrevious = false

    /// `closed` (one stream, oldest first) with every replaced block
    /// removed, for producers that write a batch at once.
    static func resolved(_ closed: [Self]) -> [Self] {
        var result: [Self] = []
        for block in closed {
            if block.replacesPrevious, let index = result.lastIndex(where: { $0.block.id == block.block.id }) {
                result.remove(at: index)
            }
            var kept = block
            kept.replacesPrevious = false
            result.append(kept)
        }
        return result
    }
}
