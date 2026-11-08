// PresenceEvent: the system events that take a Sample at once
// (activity_tracking.md §2.4, §3.4).

import TimeTrackingCore

/// The presence events that refine timing between ticks (§3.4).
nonisolated enum PresenceEvent: String, Hashable, Sendable, CaseIterable {
    case lock
    case unlock
    case sleep
    case wake
    case displaySleep = "display_sleep"
    case displayWake = "display_wake"
    case userSwitch = "user_switch"
    case userReturn = "user_return"

    /// Whether the event ends the open block at its time (§2.7).
    var closesBlock: Bool {
        switch self {
        case .lock, .sleep, .displaySleep, .userSwitch:
            true
        case .unlock, .wake, .displayWake, .userReturn:
            false
        }
    }

    /// The presence state the event sets, if it sets one.
    var state: TrackerPresenceState? {
        switch self {
        case .lock:
            .locked
        case .sleep:
            .asleep
        case .displaySleep:
            .idle
        case .userSwitch:
            .otherUser
        case .unlock, .wake, .displayWake, .userReturn:
            nil
        }
    }
}
