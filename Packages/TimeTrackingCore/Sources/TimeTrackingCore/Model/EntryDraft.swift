// EntryDraft and EntryChange: inputs of the entry writes (data_and_sync.md §7.1).

public import Foundation

/// A new stopped (or, for imports and tests, running) entry.
public struct EntryDraft: Hashable, Sendable {
    /// The id to use; a new random id when `nil`.
    public var id: EntryID?
    public var projectID: ProjectID?
    public var task: String
    public var start: Date
    public var end: Date?
    /// The IANA zone; the writing device's zone when `nil`.
    public var timeZone: String?

    public init(
        id: EntryID? = nil,
        projectID: ProjectID?,
        task: String,
        start: Date,
        end: Date?,
        timeZone: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.task = task
        self.start = start
        self.end = end
        self.timeZone = timeZone
    }
}

/// The fields `update(_:_:)` changes; `nil` leaves a field as it is.
public struct EntryChange: Hashable, Sendable {
    /// `.some(nil)` clears the project.
    public var projectID: ProjectID??
    public var task: String?
    public var start: Date?
    /// Setting an end stops a running entry; entries are never reopened.
    public var end: Date?

    public init(projectID: ProjectID?? = nil, task: String? = nil, start: Date? = nil, end: Date? = nil) {
        self.projectID = projectID
        self.task = task
        self.start = start
        self.end = end
    }
}
