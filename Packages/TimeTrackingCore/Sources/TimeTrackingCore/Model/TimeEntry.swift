// TimeEntry: a tracked interval (spec_data_and_sync.md §1.4, §1.5).

public import Foundation

/// A time entry. Duration is `end - start` (`now - start` while running),
/// never stored or rounded. Live entries never cross a midnight of their
/// `timeZone`.
public struct TimeEntry: Identifiable, Hashable, Sendable {
    public var id: EntryID
    /// `nil` is "no project".
    public var projectID: ProjectID?
    /// Free text, trimmed, may be empty.
    public var task: String
    public var start: Date
    /// `nil` while running.
    public var end: Date?
    /// IANA identifier of the creating device's zone; decides the day.
    public var timeZone: String
    /// The creating device.
    public var deviceID: DeviceID
    /// For a split piece, the id of the chain's first piece.
    public var splitRootID: EntryID?
    /// The local date of `start` in `timeZone`.
    public var day: TrackingDay
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(
        id: EntryID = EntryID(),
        projectID: ProjectID?,
        task: String,
        start: Date,
        end: Date?,
        timeZone: String,
        deviceID: DeviceID,
        splitRootID: EntryID? = nil,
        day: TrackingDay? = nil,
        createdAt: Date,
        modifiedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.task = task
        self.start = start
        self.end = end
        self.timeZone = timeZone
        self.deviceID = deviceID
        self.splitRootID = splitRootID
        self.day = day ?? TrackingCalendar(timeZoneIdentifier: timeZone).day(containing: start)
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }

    public var isRunning: Bool {
        end == nil
    }

    public var isDeleted: Bool {
        deletedAt != nil
    }

    /// The id of the chain this entry belongs to (`splitRootID ?? id`).
    public var rootID: EntryID {
        splitRootID ?? id
    }

    /// The entry's zone, or the current one for an unknown identifier.
    public var zone: TimeZone {
        TimeZone(identifier: timeZone) ?? .current
    }

    /// Whole seconds from start to end, or to `now` while running.
    public func seconds(at now: Date) -> Int {
        max(0, Int((end ?? now).timeIntervalSince(start).rounded(.down)))
    }

    /// The interval up to `now` while running.
    public func interval(at now: Date) -> DateInterval {
        DateInterval(start: start, end: max(start, end ?? now))
    }
}
