// Value types returned by the reading queries (spec_data_and_sync.md §7.2).

public import Foundation

/// One day of the Timer list: its entries, newest first, and the total.
public struct DayGroup: Hashable, Sendable {
    public var day: TrackingDay
    public var entries: [TimeEntry]
    /// The running entry counted to the query time.
    public var totalSeconds: Int
    public var includesRunning: Bool

    public init(day: TrackingDay, entries: [TimeEntry], totalSeconds: Int, includesRunning: Bool) {
        self.day = day
        self.entries = entries
        self.totalSeconds = totalSeconds
        self.includesRunning = includesRunning
    }
}

/// An autocompletion candidate for the task field.
public struct TaskSuggestion: Hashable, Sendable {
    /// The most recent spelling of the task.
    public var task: String
    public var projectID: ProjectID?
    public var lastUsed: Date
    public var useCount: Int

    public init(task: String, projectID: ProjectID?, lastUsed: Date, useCount: Int) {
        self.task = task
        self.projectID = projectID
        self.lastUsed = lastUsed
        self.useCount = useCount
    }
}

/// Which projects `projects(filter:)` returns.
public struct ProjectFilter: Hashable, Sendable {
    public enum State: String, Sendable, CaseIterable {
        case active
        case archived
        case all
    }

    public var state: State
    // swiftlint:disable:next discouraged_optional_collection
    public var clientIDs: Set<ClientID>?
    // swiftlint:disable:next discouraged_optional_collection
    public var areaIDs: Set<AreaID>?
    /// Folded substring of the project, area, or client name.
    public var search: String?

    // swiftlint:disable:next discouraged_optional_collection
    public init(state: State = .active, clientIDs: Set<ClientID>? = nil, areaIDs: Set<AreaID>? = nil, search: String? = nil) {
        self.state = state
        self.clientIDs = clientIDs
        self.areaIDs = areaIDs
        self.search = search
    }
}

/// A project with its client, area, and usage.
public struct ProjectRow: Identifiable, Hashable, Sendable {
    public var project: Project
    /// `nil` when the area has not arrived or is tombstoned.
    public var area: Area?
    public var client: Client?
    public var entryCount: Int
    /// The latest start of a live entry.
    public var lastUsed: Date?
    /// Live entries, the running one to the query time.
    public var totalSeconds: Int

    public init(project: Project, area: Area?, client: Client?, entryCount: Int, lastUsed: Date?, totalSeconds: Int) {
        self.project = project
        self.area = area
        self.client = client
        self.entryCount = entryCount
        self.lastUsed = lastUsed
        self.totalSeconds = totalSeconds
    }

    public var id: ProjectID {
        project.id
    }

    /// The area's color.
    public var color: String? {
        area?.color
    }
}

/// A client with its areas and their projects (`projectTree(includeArchived:)`).
public struct ClientNode: Identifiable, Hashable, Sendable {
    public var client: Client
    public var areas: [AreaNode]

    public init(client: Client, areas: [AreaNode]) {
        self.client = client
        self.areas = areas
    }

    public var id: ClientID {
        client.id
    }
}

/// An area with its projects, alphabetical.
public struct AreaNode: Identifiable, Hashable, Sendable {
    public var area: Area
    public var projects: [Project]

    public init(area: Area, projects: [Project]) {
        self.area = area
        self.projects = projects
    }

    public var id: AreaID {
        area.id
    }
}

/// A problem `consistencyIssues()` reports; integrity is reported, never repaired.
public enum ConsistencyIssue: Hashable, Sendable {
    /// What kind of record has a duplicate name.
    public enum Kind: String, Sendable {
        case client
        case area
        case project
    }

    /// A running entry starting more than 5 minutes ahead of this device's clock.
    case runningInFuture(EntryID, start: Date)
    /// A live entry references a project that is unknown or tombstoned.
    case unknownProject(EntryID, projectID: ProjectID)
    /// A live project's area is unknown or tombstoned (orphaned project).
    case projectWithoutArea(ProjectID, areaID: AreaID)
    /// A live area's client is unknown or tombstoned.
    case areaWithoutClient(AreaID, clientID: ClientID)
    /// Live records of one kind share a folded name within their scope.
    case duplicateName(Kind, name: String, ids: [UUID])
}
