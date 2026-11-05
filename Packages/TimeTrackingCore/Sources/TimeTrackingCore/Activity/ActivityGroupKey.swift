// ActivityGroupKey: the dimensions of an activity aggregate (data_and_sync.md §6).

/// What `ActivityReading.aggregate(in:by:device:)` groups by.
public enum ActivityGroupKey: String, Sendable, Hashable, CaseIterable {
    /// Item seconds per context.
    case context
    /// Item seconds per subject.
    case subject
    /// Active seconds per dominant group key.
    case groupKey
    /// Active seconds per local hour, spread over the hours a block covers.
    case hourOfDay
    /// Active seconds per local date.
    case day
}
