// Report queries and results (spec_data_and_sync.md §7.3).

import Foundation

/// A level of a report breakdown.
public enum GroupKey: String, Codable, Sendable, CaseIterable {
    case client
    case area
    case project
    case task
    case day
}

/// The value of one report node; `nil` ids mean "no client/area/project".
public enum GroupKeyValue: Hashable, Sendable {
    case total
    case client(ClientID?)
    case area(AreaID?)
    case project(ProjectID?)
    /// The trimmed task text, grouped exactly.
    case task(String)
    case day(TrackingDay)
}

/// Which entries a report counts.
public struct EntryFilter: Hashable, Sendable {
    // swiftlint:disable discouraged_optional_collection
    public var clients: Set<ClientID>?
    public var areas: Set<AreaID>?
    public var projects: Set<ProjectID>?
    // swiftlint:enable discouraged_optional_collection
    /// Case-insensitive substring of the task.
    public var taskContains: String?
    public var includeNoProject: Bool
    public var includeArchived: Bool
    /// Only entries without a project (the tool's `--no-project`).
    public var noProjectOnly: Bool
    /// With `clients` set, entries without a project match too ("No client").
    public var clientsIncludeNone = false
    /// With `areas` set, entries without a project match too ("No area").
    public var areasIncludeNone = false
    /// With `projects` set, entries without a project match too ("(no project)").
    public var projectsIncludeNone = false
    /// The Reports filter's tree: entries of projects in scope; combines
    /// with the other rules by AND.
    public var scope: ProjectScope?
    /// With `scope` set, entries without a project match too ("No project").
    public var scopeIncludesNone = false

    // swiftlint:disable discouraged_optional_collection
    public init(
        clients: Set<ClientID>? = nil,
        areas: Set<AreaID>? = nil,
        projects: Set<ProjectID>? = nil,
        taskContains: String? = nil,
        includeNoProject: Bool = true,
        includeArchived: Bool = true,
        noProjectOnly: Bool = false
    ) {
        // swiftlint:enable discouraged_optional_collection
        self.clients = clients
        self.areas = areas
        self.projects = projects
        self.taskContains = taskContains
        self.includeNoProject = includeNoProject
        self.includeArchived = includeArchived
        self.noProjectOnly = noProjectOnly
    }
}

/// A report over whole days.
public struct ReportQuery: Hashable, Sendable {
    public var days: ClosedRange<TrackingDay>
    /// Up to four levels, in order.
    public var groupBy: [GroupKey]
    public var granularity: Granularity
    public var filter: EntryFilter

    public init(
        days: ClosedRange<TrackingDay>,
        groupBy: [GroupKey],
        granularity: Granularity = .total,
        filter: EntryFilter = EntryFilter()
    ) {
        self.days = days
        self.groupBy = groupBy
        self.granularity = granularity
        self.filter = filter
    }
}

/// A node of the report tree; the root is the grand total.
public struct ReportNode: Hashable, Sendable {
    public var key: GroupKeyValue
    /// The name of the client, area, or project, the task text, or the
    /// date; `nil` for "no project" and the root.
    public var name: String?
    /// The area's color for area and project nodes.
    public var color: String?
    /// An archived project's node (Reports shows "(archived)").
    public var isArchived = false
    public var seconds: Int
    public var entryCount: Int
    public var buckets: [TrackingPeriod: Int]
    /// Entries per period.
    public var entryBuckets: [TrackingPeriod: Int]
    public var children: [Self]

    public init(
        key: GroupKeyValue,
        name: String? = nil,
        color: String? = nil,
        seconds: Int = 0,
        entryCount: Int = 0,
        buckets: [TrackingPeriod: Int] = [:],
        entryBuckets: [TrackingPeriod: Int] = [:],
        children: [Self] = []
    ) {
        self.key = key
        self.name = name
        self.color = color
        self.seconds = seconds
        self.entryCount = entryCount
        self.buckets = buckets
        self.entryBuckets = entryBuckets
        self.children = children
    }

    /// The leaves of the fully expanded tree with their ancestors (root
    /// excluded), depth first.
    public var leafPaths: [[Self]] {
        children.flatMap { child in
            child.children.isEmpty ? [[child]] : child.leafPaths.map { [child] + $0 }
        }
    }
}
