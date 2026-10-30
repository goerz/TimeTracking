// SourceReport: what a resolver found out about a source during a tick
// (spec_activity_tracking.md §2.3, §4.4).

import TimeTrackingCore

/// A source's status as one resolver saw it; the engine applies it to the board.
nonisolated struct SourceReport: Hashable, Sendable {
    var id: String
    var status: TrackerSourceStatus
    var reason: String

    init(_ id: String, _ status: TrackerSourceStatus, _ reason: String = "") {
        self.id = id
        self.status = status
        self.reason = reason
    }
}
