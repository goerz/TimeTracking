// ClosedBlock: what the Blocker hands to the logs (spec_activity_tracking.md
// §2.7, §4.2, §4.3).

import TimeTrackingCore

/// A block the Blocker closed: the summary for the block log, the uncut
/// items for the detail log, and the context map for the header.
nonisolated struct ClosedBlock: Hashable, Sendable {
    var block: ActivityBlock
    var detailItems: [ActivityItem]
    var contexts: [String: String]
}
