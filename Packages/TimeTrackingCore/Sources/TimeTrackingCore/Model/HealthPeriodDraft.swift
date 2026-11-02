// HealthPeriodDraft: a sleep stretch or a workout as the Apple Health import
// reads it, before it becomes a health period (spec_data_and_sync.md §1.9).

public import Foundation

/// The values of a health period the import sets.
public struct HealthPeriodDraft: Hashable, Sendable {
    public var interval: DateInterval
    /// A workout's activity type name; see `HealthPeriod.activity`.
    public var activity: String?
    /// A workout's distance in whole meters.
    public var distance: Int?

    public init(_ interval: DateInterval, activity: String? = nil, distance: Int? = nil) {
        self.interval = interval
        self.activity = activity
        self.distance = distance
    }
}
