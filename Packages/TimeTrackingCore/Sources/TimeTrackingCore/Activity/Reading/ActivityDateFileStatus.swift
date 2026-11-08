// ActivityDateFileStatus: whether a date file of the block log can be read
// on this device (activity_tracking.md §4.1; automation.md §3.12).

/// A date file present, missing, or held by iCloud Drive only as a placeholder.
public enum ActivityDateFileStatus: String, Sendable, Hashable {
    case present
    case missing
    /// iCloud Drive holds only a placeholder; its download was asked for.
    case notDownloaded
}
