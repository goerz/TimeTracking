// ActivityEndReason+Phrase: how a block summary says why a block ended
// (activity_tracking.md §2.8).

extension ActivityEndReason {
    /// How a summary says why the block ended (activity_tracking.md §2.8).
    public var phrase: String {
        switch self {
        case .idle: "went idle"
        case .locked: "screen locked"
        case .asleep: "Mac slept"
        case .otherUser: "user switched"
        case .paused: "Focus paused collection"
        case .split: "moved on to other work"
        case .maxLength: "reached its longest length"
        case .stopped: "tracker stopped"
        }
    }
}
