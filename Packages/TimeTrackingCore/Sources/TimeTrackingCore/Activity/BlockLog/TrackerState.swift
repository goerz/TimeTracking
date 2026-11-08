// TrackerState: the parsed current.json of the tracker agent
// (activity_tracking.md §2.2, §4.4; data_and_sync.md §6).

public import Foundation

/// The tracker's current state, `current.json`: the open block, the
/// foreground Item, presence, and health. The local activity loop rewrites
/// it on every tick, the rebuild loop when the open block changes.
public struct TrackerState: Sendable, Hashable {
    /// The open block, with `isOpen`, its end the end of its credited time so far.
    public var block: ActivityBlock?
    /// The latest live Sample's foreground Item; `nil` while the user is not attentive.
    public var foreground: ActivityItem?
    public var presence: TrackerPresence
    public var health: TrackerHealth

    public init(block: ActivityBlock?, foreground: ActivityItem?, presence: TrackerPresence, health: TrackerHealth) {
        self.block = block
        self.foreground = foreground
        self.presence = presence
        self.health = health
    }

    /// The age of the last tick at which the tracker counts as not running.
    public static let notRunningAge: TimeInterval = 120
    /// The age of the last tick at which a running tracker counts as delayed.
    public static let delayedAge: TimeInterval = 90

    /// Whether the tracker runs at `now`: the last tick is younger than 2 minutes.
    public func isRunning(at now: Date) -> Bool {
        now.timeIntervalSince(health.lastTick) < Self.notRunningAge
    }

    /// Whether the tracker runs at `now` but its last tick is 90 seconds old or older.
    public func isDelayed(at now: Date) -> Bool {
        isRunning(at: now) && now.timeIntervalSince(health.lastTick) >= Self.delayedAge
    }
}
