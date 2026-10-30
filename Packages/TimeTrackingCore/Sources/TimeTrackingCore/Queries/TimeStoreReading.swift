// The reading protocols of the query layer (spec_data_and_sync.md §7.2 to §7.4).

public import Foundation

/// Entry queries for the Timer list, Calendar, pickers, and scripts.
public protocol TimeStoreReading: Sendable {
    func runningEntry() async throws -> TimeEntry?
    /// The earliest start of the live entries sharing the entry's root.
    func chainStart(of id: EntryID) async throws -> Date
    func entry(_ id: EntryID) async throws -> TimeEntry?
    /// Entries intersecting `interval`, by start.
    func entries(in interval: DateInterval, includeDeleted: Bool) async throws -> [TimeEntry]
    /// Entries whose `day` is `day`, by start.
    func entries(on day: TrackingDay) async throws -> [TimeEntry]
    /// `count` days ending at `ending`, newest first, empty days included.
    func days(ending: TrackingDay, count: Int) async throws -> [DayGroup]
    /// Entries starting before `before`, newest first.
    func recentEntries(before: Date?, limit: Int) async throws -> [TimeEntry]
    func lastStoppedEntry(excluding: EntryID?) async throws -> TimeEntry?
    /// Active projects by their latest entry start, most recent first.
    func recentProjects(limit: Int) async throws -> [ProjectID]
    func overlaps(for draft: EntryDraft, excluding: EntryID?) async throws -> [TimeEntry]
    func overlappingEntries(in interval: DateInterval) async throws -> [(TimeEntry, TimeEntry)]
    func distinctTasks(projectID: ProjectID?, prefix: String, limit: Int) async throws -> [TaskSuggestion]
    func projectsByTask(matching text: String, since: Date) async throws -> [ProjectID]
    func recentCombinations(limit: Int) async throws -> [(ProjectID?, String)]
    func consistencyIssues() async throws -> [ConsistencyIssue]
}

/// Client, area, project, and device queries.
public protocol StructureReading: Sendable {
    /// Live clients, alphabetical by folded name.
    func clients(includeRetired: Bool) async throws -> [Client]
    /// Live areas of `client` (all clients when `nil`) by client, order, name.
    func areas(of client: ClientID?, includeRetired: Bool) async throws -> [Area]
    func projects(filter: ProjectFilter) async throws -> [ProjectRow]
    func project(_ id: ProjectID) async throws -> Project?
    func projectTree(includeArchived: Bool) async throws -> [ClientNode]
    /// Fuzzy on project, area, and client names; active projects.
    func searchProjects(_ query: String, limit: Int) async throws -> [ProjectRow]
    func devices() async throws -> [Device]
}

/// Report aggregation for Reports and the tool.
public protocol Reporting: Sendable {
    /// The report tree; the root is the grand total.
    func report(_ query: ReportQuery) async throws -> ReportNode
    /// Per period, seconds per first-level key (stacked bars).
    func series(_ query: ReportQuery) async throws -> [(TrackingPeriod, [GroupKeyValue: Int])]
    func entries(matching query: ReportQuery) async throws -> [TimeEntry]
}

/// Store changes for views.
public protocol StoreObserving: Sendable {
    /// A new stream of changes after commit; each access is one subscriber.
    var changes: AsyncStream<StoreChange> { get }

    func recentAdjustments(limit: Int) async -> [EntryAdjustment]
}
