// ActivityEndReason: why a block ended (activity_tracking.md §2.2).

/// Why a block ended: a presence state that ended it, or `split`,
/// `maxLength`, or `stopped`.
public enum ActivityEndReason: String, Sendable, Hashable, CaseIterable {
    case idle
    case locked
    case asleep
    case otherUser
    case paused
    /// The work changed; for a background block, attention came back.
    case split
    case maxLength
    /// The agent stopped running.
    case stopped
}
