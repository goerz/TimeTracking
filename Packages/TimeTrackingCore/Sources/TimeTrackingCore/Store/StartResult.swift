// StartResult: the result of the tool's `start` and `continue`
// (automation.md §3.5).

import Foundation

/// The result of `start` and `continue`.
public struct StartResult: Hashable, Sendable {
    public var entry: EntryListing
    /// The entry that was running and is now stopped.
    public var stopped: EntryListing?
}
