// TrackerSourceStatus: the statuses a source reports (activity_tracking.md §3.5).

/// The status a source reports.
public enum TrackerSourceStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case active
    case fallback
    case off
}
