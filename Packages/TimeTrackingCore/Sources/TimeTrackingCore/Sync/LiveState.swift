// LiveState: the running entry and each Mac's current activity, mirrored in
// the `live_state` row and the CloudKit record `LiveState`
// (spec_data_and_sync.md §4.1).

public import Foundation

/// The live-update record read by the iPhone and iPad widgets.
public struct LiveState: Hashable, Sendable {
    /// The running part; `nil` when nothing runs.
    public var running: Running?
    /// The last change of the running part, milliseconds.
    public var changedAt: Date?
    /// Each Mac's current activity, keyed by the Mac's device id.
    public var activity: [String: MacActivity]

    public init(running: Running? = nil, changedAt: Date? = nil, activity: [String: MacActivity] = [:]) {
        self.running = running
        self.changedAt = changedAt
        self.activity = activity
    }

    /// The running entry as the widgets show it.
    public struct Running: Hashable, Sendable {
        public var entryID: EntryID
        public var projectID: ProjectID?
        public var task: String
        public var projectName: String?
        public var clientName: String?
        public var areaColor: String?
        /// The chain's earliest start, so the elapsed time survives the midnight split.
        public var chainStart: Date

        public init(
            entryID: EntryID,
            projectID: ProjectID?,
            task: String,
            projectName: String?,
            clientName: String?,
            areaColor: String?,
            chainStart: Date
        ) {
            self.entryID = entryID
            self.projectID = projectID
            self.task = task
            self.projectName = projectName
            self.clientName = clientName
            self.areaColor = areaColor
            self.chainStart = chainStart
        }
    }

    /// One Mac's activity, copied from its `current.json`.
    public struct MacActivity: Hashable, Sendable {
        /// The device name of `current.json`.
        public var device: String
        /// The primary item, `[context, subject, detail]` in JSON; `nil` while idle.
        public var primary: TrackerPrimaryItem?
        /// The open block's group key `g`, or `nil`.
        public var groupKey: String?
        /// The presence state (`active`, `passive`, `idle`, …), or `nil` without `current.json`.
        public var presence: String?
        public var since: Date?
        /// Whether the tracker runs by the rule of the tracker spec §4.4.
        public var agentRunning: Bool
        public var lastTick: Date?
        /// The ids of the sources whose status is not `active`.
        public var health: [String]
        /// The time of this write.
        public var updatedAt: Date

        public init(
            device: String,
            primary: TrackerPrimaryItem?,
            groupKey: String?,
            presence: String?,
            since: Date?,
            agentRunning: Bool,
            lastTick: Date?,
            health: [String],
            updatedAt: Date
        ) {
            self.device = device
            self.primary = primary
            self.groupKey = groupKey
            self.presence = presence
            self.since = since
            self.agentRunning = agentRunning
            self.lastTick = lastTick
            self.health = health
            self.updatedAt = updatedAt
        }
    }

    /// The merge of §4.1: the running part with the later `changedAt` wins;
    /// per Mac the activity with the later `updatedAt` wins; entries present
    /// on one side only are kept. Ties pick the greater JSON text, so every
    /// device merges alike.
    public func merged(with other: Self) -> Self {
        var result = self
        let mine = (changedAt ?? .distantPast, Self.runningJSON(running) ?? "")
        let theirs = (other.changedAt ?? .distantPast, Self.runningJSON(other.running) ?? "")
        if theirs > mine {
            result.running = other.running
            result.changedAt = other.changedAt
        }
        for (device, activity) in other.activity {
            guard let local = result.activity[device] else {
                result.activity[device] = activity
                continue
            }
            if (activity.updatedAt, activity.json) > (local.updatedAt, local.json) {
                result.activity[device] = activity
            }
        }
        return result
    }
}
