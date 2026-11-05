// ActivityChange: what changed in the activity folders (data_and_sync.md §6).

/// A change reported by `ActivityReading.changes`.
public enum ActivityChange: Sendable, Hashable {
    /// A month file of the block log was added, appended to, or removed.
    case blocks(month: String)
    /// `current.json` was rewritten or removed.
    case currentState
    /// `settings.toml` changed; `exclusions` already reflects it.
    case settings
}
