// DeletedRange: time the user deleted (activity_tracking.md §2.2, §2.6).

public import Foundation

/// A time range the user deleted (§2.6); no Sample inside it is stored again.
public struct DeletedRange: Sendable, Hashable, Codable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public func contains(_ time: Date) -> Bool {
        time >= start && time < end
    }
}
