// Observation events and entry adjustments (spec_data_and_sync.md §3.3, §7.4).

public import Foundation

/// A change the store reports after commit.
public enum StoreChange: Hashable, Sendable {
    /// Entries changed; an empty set means "re-read" (another process).
    case entries(Set<EntryID>)
    case runningEntry(TimeEntry?)
    /// Clients, areas, projects, or devices changed.
    case structure
    case settings(Set<String>)
    case liveState
    /// Sleep or workout periods changed (§1.9).
    case health
    case sync(SyncStatus)
    /// The pass or conflict resolution changed entries created on this device.
    case adjusted([EntryAdjustment])
}

/// One change the invariant pass or conflict resolution made to an entry.
public struct EntryAdjustment: Hashable, Sendable {
    public enum Reason: String, Sendable {
        case splitAtMidnight
        case stoppedByLaterStart
        case removedByLaterStart
        case replacedByRemoteEdit
        case deletedRemotely
        case restoredRemotely
    }

    public var entryID: EntryID
    public var reason: Reason
    public var before: TimeEntry?
    public var after: TimeEntry?
    /// The entry that caused it (the later start), if any.
    public var causingEntryID: EntryID?
    /// The device that created the causing entry or sent the remote change.
    public var causingDeviceID: DeviceID?
    public var time: Date

    public init(
        entryID: EntryID,
        reason: Reason,
        before: TimeEntry?,
        after: TimeEntry?,
        causingEntryID: EntryID? = nil,
        causingDeviceID: DeviceID? = nil,
        time: Date
    ) {
        self.entryID = entryID
        self.reason = reason
        self.before = before
        self.after = after
        self.causingEntryID = causingEntryID
        self.causingDeviceID = causingDeviceID
        self.time = time
    }
}
