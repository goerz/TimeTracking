// SourceReport: what a resolver found out about a source during a tick
// (activity_tracking.md §3.5, §4.4).

import TimeTrackingCore

/// A source's status as one resolver saw it; the engine applies it to the board.
nonisolated struct SourceReport: Hashable, Sendable {
    var id: SourceID
    var status: TrackerSourceStatus
    var reason: String

    init(_ id: SourceID, _ status: TrackerSourceStatus, _ reason: String = "") {
        self.id = id
        self.status = status
        self.reason = reason
    }
}
