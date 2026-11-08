// TrackerPresence: the presence of current.json, its state and since when
// (activity_tracking.md §4.4).

public import Foundation

/// The presence state and when it began.
public struct TrackerPresence: Sendable, Hashable {
    public var state: TrackerPresenceState
    /// The time of the event or input that set the state.
    public var since: Date
    public var lastInput: Date?

    public init(state: TrackerPresenceState, since: Date, lastInput: Date? = nil) {
        self.state = state
        self.since = since
        self.lastInput = lastInput
    }
}
