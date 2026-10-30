// ActivitySource: where a block came from (spec_data_and_sync.md §6,
// spec_activity_tracking.md §4.2).

/// The `src` of a block: sampled live on a Mac, backfilled from the
/// Knowledge store, or merged from another device's events.
public enum ActivitySource: String, Sendable, Hashable, Codable, CaseIterable {
    case live
    case knowledge
    case device
}
