// ReportFilters: the Reports section's filter kinds, their chips, badge,
// and narrowing (spec_planner_reports.md §3).

import Foundation

/// The filters of Reports, stored per device. Kinds combine with AND,
/// choices within a kind with OR; an empty kind does not restrict.
public struct ReportFilters: Hashable, Codable, Sendable {
    public var clients: Set<ClientID> = []
    /// "No client": entries without a project.
    public var noClient = false
    public var areas: Set<AreaID> = []
    /// "No area": entries without a project.
    public var noArea = false
    public var projects: Set<ProjectID> = []
    /// "(no project)".
    public var noProject = false
    /// Matched as a folded substring of the task.
    public var task = ""
    public var includeArchived = true

    public init(
        clients: Set<ClientID> = [],
        noClient: Bool = false,
        areas: Set<AreaID> = [],
        noArea: Bool = false,
        projects: Set<ProjectID> = [],
        noProject: Bool = false,
        task: String = "",
        includeArchived: Bool = true
    ) {
        self.clients = clients
        self.noClient = noClient
        self.areas = areas
        self.noArea = noArea
        self.projects = projects
        self.noProject = noProject
        self.task = task
        self.includeArchived = includeArchived
    }

    /// Only `project` (Show in Reports, `showReports`).
    public static func project(_ id: ProjectID) -> Self {
        Self(projects: [id])
    }

    public var hasClientFilter: Bool {
        !clients.isEmpty || noClient
    }

    public var hasAreaFilter: Bool {
        !areas.isEmpty || noArea
    }

    public var hasProjectFilter: Bool {
        !projects.isEmpty || noProject
    }

    public var hasTaskFilter: Bool {
        !task.trimmed.isEmpty
    }

    /// The badge: the number of active kinds.
    public var activeKindCount: Int {
        [hasClientFilter, hasAreaFilter, hasProjectFilter, hasTaskFilter, !includeArchived].count(where: \.self)
    }

    /// The query filter.
    public var entryFilter: EntryFilter {
        var filter = EntryFilter(
            clients: hasClientFilter ? clients : nil,
            areas: hasAreaFilter ? areas : nil,
            projects: hasProjectFilter ? projects : nil,
            taskContains: hasTaskFilter ? task.trimmed : nil,
            includeArchived: includeArchived
        )
        filter.clientsIncludeNone = noClient
        filter.areasIncludeNone = noArea
        filter.projectsIncludeNone = noProject
        return filter
    }

    /// Removes choices that left their lists through narrowing: areas of
    /// unchosen clients, projects outside the chosen clients and areas, and
    /// archived projects while they are excluded.
    public func narrowed(areas allAreas: [Area], projects allProjects: [ProjectRow]) -> Self {
        var result = self
        if !clients.isEmpty {
            let allowed = Set(allAreas.filter { clients.contains($0.clientID) }.map(\.id))
            result.areas = areas.intersection(allowed)
        }
        let visible = result.visibleProjects(allProjects)
        result.projects = projects.intersection(Set(visible.map(\.id)))
        return result
    }

    /// The Project list: projects narrowed by the chosen clients and areas,
    /// archived ones only while included.
    public func visibleProjects(_ rows: [ProjectRow]) -> [ProjectRow] {
        rows.filter { row in
            (includeArchived || !row.project.isArchived)
                && (clients.isEmpty || row.client.map { clients.contains($0.id) } ?? false)
                && (areas.isEmpty || areas.contains(row.project.areaID))
        }
    }

    /// The Area chips: areas narrowed to the chosen clients.
    public func visibleAreas(_ areas: [Area]) -> [Area] {
        clients.isEmpty ? areas : areas.filter { clients.contains($0.clientID) }
    }
}

/// One removable chip right of the Filters button.
public struct ReportFilterChip: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case client
        case area
        case project
        case task
        case archived
    }

    public var kind: Kind
    /// "Client: Consulting", "Project: 2", "Task: noise", "Archived excluded".
    public var text: String

    public var id: Kind {
        kind
    }
}

extension ReportFilters {
    /// The chips, in kind order, with names from the given structure.
    public func chips(clients allClients: [Client], areas allAreas: [Area], projects allProjects: [ProjectRow]) -> [ReportFilterChip] {
        func describe(_ names: [String], count: Int, none: Bool, noneName: String) -> String {
            let total = count + (none ? 1 : 0)
            guard total == 1 else {
                return String(total)
            }
            return none ? noneName : names.first ?? "1"
        }
        var chips: [ReportFilterChip] = []
        if hasClientFilter {
            let names = allClients.filter { clients.contains($0.id) }.map(\.name)
            chips.append(ReportFilterChip(
                kind: .client,
                text: "Client: " + describe(names, count: clients.count, none: noClient, noneName: "No client")
            ))
        }
        if hasAreaFilter {
            let names = allAreas.filter { areas.contains($0.id) }.map(\.name)
            chips.append(ReportFilterChip(
                kind: .area,
                text: "Area: " + describe(names, count: areas.count, none: noArea, noneName: "No area")
            ))
        }
        if hasProjectFilter {
            let names = allProjects.filter { projects.contains($0.id) }.map(\.project.name)
            chips.append(ReportFilterChip(
                kind: .project,
                text: "Project: " + describe(names, count: projects.count, none: noProject, noneName: "(no project)")
            ))
        }
        if hasTaskFilter {
            chips.append(ReportFilterChip(kind: .task, text: "Task: \(task.trimmed)"))
        }
        if !includeArchived {
            chips.append(ReportFilterChip(kind: .archived, text: "Archived excluded"))
        }
        return chips
    }

    /// The chip's ×.
    public mutating func remove(_ kind: ReportFilterChip.Kind) {
        switch kind {
        case .client:
            clients = []
            noClient = false
        case .area:
            areas = []
            noArea = false
        case .project:
            projects = []
            noProject = false
        case .task:
            task = ""
        case .archived:
            includeArchived = true
        }
    }
}
