// SuggestionFeedback: a stored outcome of a project suggestion
// (spec_data_and_sync.md §2.1, spec_planner_calendar.md).

public import Foundation

/// Feedback on one proposal of the suggestion engine. Synced.
public struct SuggestionFeedback: Identifiable, Hashable, Sendable {
    /// Where the proposal came from.
    public enum Source: String, Codable, Sendable {
        case block
        case event
        case fill
    }

    /// What the user did with it.
    public enum Outcome: String, Codable, Sendable {
        case accepted
        case edited
        case skipped
    }

    public var id: FeedbackID
    public var recordedAt: Date
    /// The interval of the query that produced the proposal.
    public var queryStart: Date
    public var queryEnd: Date
    /// The number of activity items in the query.
    public var queryItems: Int
    public var source: Source
    public var blockStart: Date?
    public var blockDevice: String?
    public var proposedProjectID: ProjectID?
    public var proposedTask: String
    public var confidence: Double
    public var outcome: Outcome
    public var chosenProjectID: ProjectID?
    public var chosenTask: String?
    public var entryID: EntryID?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(
        id: FeedbackID = FeedbackID(),
        recordedAt: Date,
        queryStart: Date,
        queryEnd: Date,
        queryItems: Int,
        source: Source,
        blockStart: Date? = nil,
        blockDevice: String? = nil,
        proposedProjectID: ProjectID?,
        proposedTask: String,
        confidence: Double,
        outcome: Outcome,
        chosenProjectID: ProjectID? = nil,
        chosenTask: String? = nil,
        entryID: EntryID? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.queryStart = queryStart
        self.queryEnd = queryEnd
        self.queryItems = queryItems
        self.source = source
        self.blockStart = blockStart
        self.blockDevice = blockDevice
        self.proposedProjectID = proposedProjectID
        self.proposedTask = proposedTask
        self.confidence = confidence
        self.outcome = outcome
        self.chosenProjectID = chosenProjectID
        self.chosenTask = chosenTask
        self.entryID = entryID
        self.createdAt = createdAt ?? recordedAt
        self.modifiedAt = modifiedAt ?? recordedAt
        self.deletedAt = deletedAt
    }
}
