// TrackerSourceHealth: one source's status in the health record
// (activity_tracking.md §3.5).

/// The health of one source.
public struct TrackerSourceHealth: Sendable, Hashable, Identifiable {
    /// The source id, e.g. `terminal` or `shared_folder`.
    public var id: String
    public var name: String
    public var status: TrackerSourceStatus
    /// Why the source is not `active`; empty otherwise.
    public var reason: String

    public init(id: String, name: String, status: TrackerSourceStatus, reason: String = "") {
        self.id = id
        self.name = name
        self.status = status
        self.reason = reason
    }
}
