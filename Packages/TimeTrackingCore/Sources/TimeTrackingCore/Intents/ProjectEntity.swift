// ProjectEntity: a project for Shortcuts, Siri, and Spotlight
// (spec_automation.md §5).

public import AppIntents
public import Foundation

/// A project, identified by its UUID.
public struct ProjectEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Project"
    public static let defaultQuery = ProjectEntityQuery()

    public let id: UUID
    @Property(title: "Name") public var name: String
    @Property(title: "State") public var state: ProjectStateValue
    @Property(title: "Area") public var area: String
    @Property(title: "Client") public var client: String
    @Property(title: "Last Entry") public var lastEntryAt: Date?
    /// The area's `#RRGGBB` color.
    public var areaColor: String

    public init(_ row: ProjectRow) {
        self.id = row.project.id.uuid
        self.areaColor = row.area?.color ?? "#808080"
        self.name = row.project.name
        self.state = row.project.isArchived ? .archived : .active
        self.area = row.area?.name ?? ""
        self.client = row.client?.name ?? ""
        self.lastEntryAt = row.lastUsed
    }

    public var projectID: ProjectID {
        ProjectID(id)
    }

    /// The name, with "Client · Area" as subtitle.
    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(client) · \(area)")
    }
}

/// A project's state.
public enum ProjectStateValue: String, AppEnum {
    case active
    case archived

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Project State"
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .active: "Active",
        .archived: "Archived",
    ]
}

/// Finds projects by id, by name (prefix, then substring), and by state,
/// client, and area; suggests active projects by recency. Archived
/// projects appear only when a query asks for them.
public struct ProjectEntityQuery: EntityStringQuery, EntityPropertyQuery {
    /// One condition of a Find query.
    public enum Condition: Sendable {
        case nameContains(String)
        case nameIs(String)
        case state(ProjectStateValue)
        case client(String)
        case area(String)
    }

    /// The metadata processor reads these builders from their source; they
    /// are never mutated.
    public nonisolated(unsafe) static var properties = QueryProperties {
        Property(\ProjectEntity.$name) {
            EqualToComparator { Condition.nameIs($0) }
            ContainsComparator { Condition.nameContains($0) }
        }
        Property(\ProjectEntity.$state) {
            EqualToComparator { Condition.state($0) }
        }
        Property(\ProjectEntity.$client) {
            EqualToComparator { Condition.client($0) }
        }
        Property(\ProjectEntity.$area) {
            EqualToComparator { Condition.area($0) }
        }
    }

    public nonisolated(unsafe) static var sortingOptions = SortingOptions {
        SortableBy(\ProjectEntity.$name)
        SortableBy(\ProjectEntity.$lastEntryAt)
    }

    @Dependency private var environment: IntentEnvironment

    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [ProjectEntity] {
        let wanted = Set(identifiers)
        return try await Self.rows(environment).filter { wanted.contains($0.project.id.uuid) }.map(ProjectEntity.init)
    }

    public func entities(matching string: String) async throws -> [ProjectEntity] {
        try await Self.matching(string, in: Self.rows(environment)).map(ProjectEntity.init)
    }

    public func suggestedEntities() async throws -> [ProjectEntity] {
        try await Self.suggested(Self.rows(environment)).map(ProjectEntity.init)
    }

    public func entities(
        matching comparators: [Condition],
        mode: ComparatorMode,
        sortedBy: [EntityQuerySort<ProjectEntity>],
        limit: Int?
    ) async throws -> [ProjectEntity] {
        let rows = try await Self.rows(environment)
        var entities = Self.filter(rows, comparators, all: mode == .and).map(ProjectEntity.init)
        for sort in sortedBy.reversed() {
            let ascending = sort.order == .ascending
            if sort.by == \ProjectEntity.$lastEntryAt {
                entities = entities.stableSorted { lhs, rhs in
                    let left = lhs.lastEntryAt ?? .distantPast
                    let right = rhs.lastEntryAt ?? .distantPast
                    return ascending ? left < right : left > right
                }
            } else {
                entities = entities.stableSorted { ascending ? $0.name.folded < $1.name.folded : $0.name.folded > $1.name.folded }
            }
        }
        return limit.map { Array(entities.prefix($0)) } ?? entities
    }

    // MARK: Logic (tested without the App Intents runtime)

    static func rows(_ environment: IntentEnvironment) async throws -> [ProjectRow] {
        let service = try await environment.automation()
        return try await service.projects(state: .all)
    }

    /// Active projects whose name starts with `string`, then those
    /// containing it, each by recency.
    public static func matching(_ string: String, in rows: [ProjectRow]) -> [ProjectRow] {
        let needle = string.folded
        let active = suggested(rows)
        guard !needle.isEmpty else {
            return active
        }
        let prefix = active.filter { $0.project.name.folded.hasPrefix(needle) }
        let substring = active.filter { !$0.project.name.folded.hasPrefix(needle) && $0.project.name.folded.contains(needle) }
        return prefix + substring
    }

    /// Active projects, most recently used first.
    public static func suggested(_ rows: [ProjectRow]) -> [ProjectRow] {
        rows.filter { !$0.project.isArchived }.stableSorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
    }

    /// The rows meeting all (or any) conditions; archived projects only
    /// when a condition asks for the archived state.
    public static func filter(_ rows: [ProjectRow], _ conditions: [Condition], all: Bool) -> [ProjectRow] {
        let wantsArchived = conditions.contains { condition in
            if case .state(.archived) = condition {
                return true
            }
            return false
        }
        let candidates = wantsArchived ? rows : rows.filter { !$0.project.isArchived }
        guard !conditions.isEmpty else {
            return candidates
        }
        return candidates.filter { row in
            let results = conditions.map { condition in
                switch condition {
                case let .nameContains(text): row.project.name.folded.contains(text.folded)
                case let .nameIs(text): row.project.name.folded == text.folded
                case let .state(state): (row.project.isArchived ? ProjectStateValue.archived : .active) == state
                case let .client(name): row.client?.name.folded == name.folded
                case let .area(name): row.area?.name.folded == name.folded
                }
            }
            return all ? results.allSatisfy(\.self) : results.contains(true)
        }
    }
}
