// TrackerState: the parsed current.json of the tracker agent
// (spec_activity_tracking.md §4.4, spec_data_and_sync.md §6).

public import Foundation

/// The tracker's current state: the open block, the primary item, presence,
/// and health, rewritten by the agent on every tick.
public struct TrackerState: Sendable, Hashable {
    public var format: Int
    /// The recording Mac's name.
    public var device: String
    /// The open block summarized as of the last tick, or `nil`.
    public var openBlock: TrackerOpenBlock?
    /// The primary item, `nil` while idle.
    public var primary: TrackerPrimaryItem?
    public var presence: TrackerPresence
    public var health: TrackerHealth

    public init(
        device: String,
        openBlock: TrackerOpenBlock?,
        primary: TrackerPrimaryItem?,
        presence: TrackerPresence,
        health: TrackerHealth,
        format: Int = 1
    ) {
        self.format = format
        self.device = device
        self.openBlock = openBlock
        self.primary = primary
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

    /// The open block as an `ActivityBlock` with `isOpen`, ending at the
    /// last tick, with the offset of `timeZone` at its start.
    public func activityBlock(timeZone: TimeZone) -> ActivityBlock? {
        guard let openBlock else {
            return nil
        }
        return ActivityBlock(
            start: openBlock.start,
            end: max(openBlock.start, health.lastTick),
            activeSeconds: openBlock.activeSeconds,
            devices: openBlock.devices.map { device in
                ActivityDeviceTime(name: device.name, seconds: device.seconds, isRecordingMac: device.name == self.device)
            },
            groupKey: openBlock.groupKey,
            groupShare: openBlock.groupShare,
            items: openBlock.items,
            utcOffset: timeZone.secondsFromGMT(for: openBlock.start),
            background: openBlock.background,
            reconstructedSeconds: openBlock.reconstructedSeconds,
            isOpen: true
        )
    }
}

/// The open block of `current.json`, without an end.
public struct TrackerOpenBlock: Sendable, Hashable {
    public var start: Date
    public var activeSeconds: Int
    /// The active seconds per device, most first.
    public var devices: [ActivityDeviceTime]
    public var groupKey: String
    public var groupShare: Double
    public var items: [ActivityItem]
    public var background: [ActivityItem]
    public var reconstructedSeconds: Int

    public init(
        start: Date,
        activeSeconds: Int,
        devices: [ActivityDeviceTime],
        groupKey: String,
        groupShare: Double,
        items: [ActivityItem],
        background: [ActivityItem] = [],
        reconstructedSeconds: Int = 0
    ) {
        self.start = start
        self.activeSeconds = activeSeconds
        self.devices = devices
        self.groupKey = groupKey
        self.groupShare = groupShare
        self.items = items
        self.background = background
        self.reconstructedSeconds = reconstructedSeconds
    }
}

/// The primary item `[context, subject, detail]` of `current.json`.
public struct TrackerPrimaryItem: Sendable, Hashable {
    public var context: String
    public var subject: String
    public var detail: String

    public init(context: String, subject: String, detail: String = "") {
        self.context = context
        self.subject = subject
        self.detail = detail
    }
}

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

/// The presence states of the tracker.
public enum TrackerPresenceState: String, Sendable, Hashable, Codable, CaseIterable {
    case active
    case passive
    case idle
    case locked
    case asleep
    case otherUser = "other_user"
}

/// The health record: the last tick, the agent version, and every source.
public struct TrackerHealth: Sendable, Hashable {
    public var lastTick: Date
    public var version: String
    public var sources: [TrackerSourceHealth]

    public init(lastTick: Date, version: String, sources: [TrackerSourceHealth]) {
        self.lastTick = lastTick
        self.version = version
        self.sources = sources
    }
}

/// The health of one source.
public struct TrackerSourceHealth: Sendable, Hashable, Identifiable {
    /// The source id, e.g. `terminal` or `shared_folder`.
    public var id: String
    public var name: String
    public var status: TrackerSourceStatus
    /// Why the source is not `active`; empty otherwise.
    public var reason: String

    public init(id: String, name: String, status: TrackerSourceStatus, reason: String = "") {
        self.id = id
        self.name = name
        self.status = status
        self.reason = reason
    }
}

/// The status a source reports.
public enum TrackerSourceStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case active
    case fallback
    case off
}
