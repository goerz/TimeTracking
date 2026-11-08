// ActivityChange: what changed in the activity folders (data_and_sync.md §6).

/// A change reported by `ActivityReading.changes`.
public enum ActivityChange: Sendable, Hashable {
    /// The date file of `day` was written, added, or removed.
    case blocks(day: TrackingDay)
    /// `current.json` was rewritten or removed.
    case currentState
    /// `settings.toml` changed; `settings` already reflects it.
    case settings
}
