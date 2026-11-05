// SystemClock: the wall clock (architecture.md §3.3).

public import Foundation

/// The wall clock of the system.
public struct SystemClock: Clock {
    public init() {}

    public var now: Date {
        Date()
    }
}
