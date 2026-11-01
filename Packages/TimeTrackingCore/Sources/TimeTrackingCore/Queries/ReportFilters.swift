// ReportFilters: the Reports section's filters, their chips and badge
// (spec_reports.md §3).

import Foundation

/// The filters of Reports, stored per device: the clients, areas, and
/// projects checked in the tree (a project is in scope when it, its area,
/// or its client is checked) with "No project", and archived projects.
/// They combine with AND; an empty tree does not restrict. The toolbar's
/// search is not a filter (`EntryFilter.search`).
public struct ReportFilters: Hashable, Codable, Sendable {
    public var clients: Set<ClientID> = []
    public var areas: Set<AreaID> = []
    public var projects: Set<ProjectID> = []
    /// "No project": entries without a project.
    public var noProject = false
    public var includeArchived = true

    public init(
        clients: Set<ClientID> = [],
        areas: Set<AreaID> = [],
        projects: Set<ProjectID> = [],
        noProject: Bool = false,
        includeArchived: Bool = true
    ) {
        self.clients = clients
        self.areas = areas
        self.projects = projects
        self.noProject = noProject
        self.includeArchived = includeArchived
    }

    /// Only `project` (Show in Reports, `showReports`).
    public static func project(_ id: ProjectID) -> Self {
        Self(projects: [id])
    }

    /// The tree's checked clients, areas, and projects.
    public var scope: ProjectScope {
        get {
            ProjectScope(clients: clients, areas: areas, projects: projects)
        }
        set {
            clients = newValue.clients
            areas = newValue.areas
            projects = newValue.projects
        }
    }

    /// The tree or "No project" restricts.
    public var hasScopeFilter: Bool {
        !scope.isEmpty || noProject
    }

    /// The badge: the number of active kinds (the tree with "No project",
    /// archived excluded).
    public var activeKindCount: Int {
        [hasScopeFilter, !includeArchived].count(where: \.self)
    }

    /// The query filter with the toolbar's `search`.
    public func entryFilter(search: String = "") -> EntryFilter {
        var filter = EntryFilter(includeArchived: includeArchived)
        filter.search = search.trimmed
        if hasScopeFilter {
            filter.scope = scope
            filter.scopeIncludesNone = noProject
        }
        return filter
    }

    /// The tree of the popover: archived projects only while included.
    public func tree(clients: [Client], areas: [Area], projects: [ProjectRow]) -> ProjectScopeTree {
        ProjectScopeTree(clients: clients, areas: areas, projects: includeArchived ? projects : projects.filter { !$0.project.isArchived })
    }

    /// Drops checks that left the tree: deleted clients, areas, and
    /// projects, and archived projects while they are excluded.
    public func normalized(clients: [Client], areas: [Area], projects: [ProjectRow]) -> Self {
        var result = self
        result.scope = tree(clients: clients, areas: areas, projects: projects).normalized(scope)
        return result
    }
}

/// One removable chip right of the Filters button.
public struct ReportFilterChip: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case node(ProjectScopeNode)
        case noProject
        case archived
    }

    public var kind: Kind
    /// "Consulting", "Consulting · Research", "Noise Model", "No project",
    /// "Archived excluded".
    public var text: String

    public var id: Kind {
        kind
    }
}

extension ReportFilters {
    /// A chip per checked client, area, and project in tree order, then No
    /// project and archived excluded.
    public func chips(clients allClients: [Client], areas allAreas: [Area], projects allProjects: [ProjectRow]) -> [ReportFilterChip] {
        let tree = ProjectScopeTree(clients: allClients, areas: allAreas, projects: allProjects)
        var chips = tree.rows.filter { scope.contains($0.node) }.map { ReportFilterChip(kind: .node($0.node), text: $0.path) }
        if noProject {
            chips.append(ReportFilterChip(kind: .noProject, text: "No project"))
        }
        if !includeArchived {
            chips.append(ReportFilterChip(kind: .archived, text: "Archived excluded"))
        }
        return chips
    }

    /// The chip's ×.
    public mutating func remove(_ kind: ReportFilterChip.Kind) {
        switch kind {
        case let .node(node):
            var scope = scope
            scope.remove(node)
            self.scope = scope
        case .noProject:
            noProject = false
        case .archived:
            includeArchived = true
        }
    }
}
