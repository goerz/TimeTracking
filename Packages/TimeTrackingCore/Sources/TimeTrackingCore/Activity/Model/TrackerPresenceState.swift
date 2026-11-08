// TrackerPresenceState: the presence state of a Sample and of the tracker
// (activity_tracking.md §2.2, §3.4).

/// The state of a Sample and of the tracker's presence (§2.2, §3.4).
public enum TrackerPresenceState: String, Sendable, Hashable, CaseIterable {
    case active
    case passive
    case idle
    case locked
    case asleep
    case otherUser
    /// A Focus paused collection on an iPhone or iPad (§6.2); never the Mac's.
    case paused

    /// Whether the state is attention: `active` or `passive`.
    public var isAttentive: Bool {
        self == .active || self == .passive
    }

    /// The reason a Sample in this state ends the open block with, or
    /// `nil` for a state that doesn't end one (§2.7).
    public var endReason: ActivityEndReason? {
        switch self {
        case .locked: .locked
        case .asleep: .asleep
        case .otherUser: .otherUser
        case .paused: .paused
        case .active, .passive, .idle: nil
        }
    }
}

/// A state is encoded as its raw value, the case name (`otherUser`).
extension TrackerPresenceState: Codable {}
