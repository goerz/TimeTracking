// AutomationStatus: the result of the tool's `status` (automation.md §3.5).

public import Foundation

/// The result of `status`.
public struct AutomationStatus: Hashable, Sendable {
    public var running: EntryListing?
    public var today: TrackingDay
    /// Today's total including the running entry's part of today.
    public var todaySeconds: Int
    public var pendingChanges: Int
    public var asOf: Date
}
