// ProjectScope: the clients, areas, and projects checked in a filter's
// tree, and the tree with its tri-state check boxes and search
// (spec_projects.md §2.4, spec_reports.md §3).

import Foundation

/// A choice of clients, areas, and projects: a project is in scope when it,
/// its area, or its client is chosen. A chosen client or area also covers
/// its later areas and projects.
public struct ProjectScope: Hashable, Codable, Sendable {
    public var clients: Set<ClientID>
    public var areas: Set<AreaID>
    public var projects: Set<ProjectID>

    public init(clients: Set<ClientID> = [], areas: Set<AreaID> = [], projects: Set<ProjectID> = []) {
        self.clients = clients
        self.areas = areas
        self.projects = projects
    }

    public var isEmpty: Bool {
        clients.isEmpty && areas.isEmpty && projects.isEmpty
    }

    /// Whether a project of `area` and `client` is in scope.
    public func contains(project: ProjectID, area: AreaID?, client: ClientID?) -> Bool {
        projects.contains(project) || area.map(areas.contains) ?? false || client.map(clients.contains) ?? false
    }

    public func contains(_ row: ProjectRow) -> Bool {
        contains(project: row.id, area: row.project.areaID, client: row.client?.id)
    }

    func contains(_ node: ProjectScopeNode) -> Bool {
        switch node {
        case let .client(id): clients.contains(id)
        case let .area(id): areas.contains(id)
        case let .project(id): projects.contains(id)
        }
    }

    mutating func insert(_ node: ProjectScopeNode) {
        switch node {
        case let .client(id): clients.insert(id)
        case let .area(id): areas.insert(id)
        case let .project(id): projects.insert(id)
        }
    }

    public mutating func remove(_ node: ProjectScopeNode) {
        switch node {
        case let .client(id): clients.remove(id)
        case let .area(id): areas.remove(id)
        case let .project(id): projects.remove(id)
        }
    }

    /// The chosen nodes: clients, then areas, then projects.
    public var nodes: [ProjectScopeNode] {
        clients.sorted().map(ProjectScopeNode.client) + areas.sorted().map(ProjectScopeNode.area)
            + projects.sorted().map(ProjectScopeNode.project)
    }
}

/// A client, area, or project of the tree.
public enum ProjectScopeNode: Hashable, Sendable {
    case client(ClientID)
    case area(AreaID)
    case project(ProjectID)
}

/// A check box's state.
public enum CheckState: Sendable {
    case checked
    case mixed
    case unchecked
}

/// The filter's tree: clients by name, each with its areas in order (general
/// first, named after the client), each with its projects by name. Without
/// projects the areas are the leaves.
public struct ProjectScopeTree: Sendable {
    /// One row of the tree.
    public struct Row: Hashable, Sendable, Identifiable {
        public var node: ProjectScopeNode
        public var name: String
        /// "Consulting" or "Consulting · Research", for matching and chips.
        public var path: String
        public var depth: Int
        /// The area's swatch or the project's dot.
        public var color: String?
        /// A retired area or an archived project.
        public var isInactive: Bool

        public var id: ProjectScopeNode {
            node
        }
    }

    /// All rows in tree order.
    public let rows: [Row]
    private let parent: [ProjectScopeNode: ProjectScopeNode]
    private let children: [ProjectScopeNode: [ProjectScopeNode]]

    /// Without `projects` the areas are the leaves (the Projects section's filter).
    public init(clients: [Client], areas: [Area], projects: [ProjectRow] = []) {
        var rows: [Row] = []
        var parent: [ProjectScopeNode: ProjectScopeNode] = [:]
        var children: [ProjectScopeNode: [ProjectScopeNode]] = [:]
        let areasByClient = Dictionary(grouping: areas, by: \.clientID)
        let projectsByArea = Dictionary(grouping: projects, by: \.project.areaID)
        for client in clients.sorted(by: { ($0.name.folded, $0.id) < ($1.name.folded, $1.id) }) {
            let clientNode = ProjectScopeNode.client(client.id)
            rows.append(Row(node: clientNode, name: client.name, path: client.name, depth: 0, isInactive: false))
            let ordered = (areasByClient[client.id] ?? []).sorted { lhs, rhs in
                (lhs.isGeneral ? 0 : 1, lhs.sortOrder, lhs.name.folded) < (rhs.isGeneral ? 0 : 1, rhs.sortOrder, rhs.name.folded)
            }
            for area in ordered {
                let areaNode = ProjectScopeNode.area(area.id)
                let name = area.isGeneral ? client.name : area.name
                let areaPath = area.isGeneral ? client.name : "\(client.name) · \(area.name)"
                rows.append(Row(node: areaNode, name: name, path: areaPath, depth: 1, color: area.color, isInactive: area.isRetired))
                parent[areaNode] = clientNode
                children[clientNode, default: []].append(areaNode)
                let members = (projectsByArea[area.id] ?? []).sorted { ($0.project.name.folded, $0.id) < ($1.project.name.folded, $1.id) }
                for row in members {
                    let node = ProjectScopeNode.project(row.id)
                    rows.append(Row(
                        node: node,
                        name: row.project.name,
                        path: "\(areaPath) · \(row.project.name)",
                        depth: 2,
                        color: row.color,
                        isInactive: row.project.isArchived
                    ))
                    parent[node] = areaNode
                    children[areaNode, default: []].append(node)
                }
            }
        }
        self.rows = rows
        self.parent = parent
        self.children = children
    }

    /// The row of a node.
    public func row(_ node: ProjectScopeNode) -> Row? {
        rows.first { $0.node == node }
    }

    // MARK: Check boxes

    /// On when the node or an ancestor is chosen, mixed when a descendant
    /// is, off otherwise.
    public func state(of node: ProjectScopeNode, in scope: ProjectScope) -> CheckState {
        if scope.contains(node) || ancestors(of: node).contains(where: scope.contains) {
            return .checked
        }
        return descendants(of: node).contains(where: scope.contains) ? .mixed : .unchecked
    }

    /// A click on the node's check box. An unchecked or mixed node becomes
    /// chosen with its descendants; when that completes its parent's
    /// children, the parent is chosen instead. A checked node is unchosen;
    /// when it was covered by an ancestor, the ancestor gives way to the
    /// other children on the path.
    public func toggling(_ node: ProjectScopeNode, in scope: ProjectScope) -> ProjectScope {
        var result = scope
        if state(of: node, in: scope) == .checked {
            if result.contains(node) {
                result.remove(node)
                return result
            }
            var path = [node]
            var current = node
            while let above = parent[current] {
                path.insert(above, at: 0)
                if result.contains(above) {
                    break
                }
                current = above
            }
            result.remove(path[0])
            for index in 0 ..< path.count - 1 {
                for child in children[path[index], default: []] where child != path[index + 1] {
                    result.insert(child)
                }
            }
            return result
        }
        for descendant in descendants(of: node) {
            result.remove(descendant)
        }
        result.insert(node)
        var current = node
        while let above = parent[current], children[above, default: []].allSatisfy(result.contains) {
            for child in children[above, default: []] {
                result.remove(child)
            }
            result.insert(above)
            current = above
        }
        return result
    }

    /// Drops chosen nodes that are not in the tree (deleted, or archived
    /// projects while they are left out).
    public func normalized(_ scope: ProjectScope) -> ProjectScope {
        let known = Set(rows.map(\.node))
        var result = scope
        for node in scope.nodes where !known.contains(node) {
            result.remove(node)
        }
        return result
    }

    // MARK: Search

    /// The rows the search shows: every word of the query occurs in a row's
    /// path (its name and its ancestors' names), case- and
    /// diacritic-insensitively; a matching row shows with its ancestors and
    /// descendants. An empty search shows every row.
    public func rows(matching search: String) -> [Row] {
        let words = search.folded.split(separator: " ").map(String.init)
        guard !words.isEmpty else {
            return rows
        }
        let matching = Set(rows.filter { row in words.allSatisfy { row.path.folded.contains($0) } }.map(\.node))
        var shown = matching
        for node in matching {
            shown.formUnion(ancestors(of: node))
            shown.formUnion(descendants(of: node))
        }
        return rows.filter { shown.contains($0.node) }
    }

    // MARK: Folding

    /// Whether the node has rows below it (a disclosure triangle).
    public func hasChildren(_ node: ProjectScopeNode) -> Bool {
        !children[node, default: []].isEmpty
    }

    /// The rows shown with `collapsed` folded: those of `rows(matching:)`
    /// whose ancestors are all expanded. A search unfolds everything, so
    /// every match shows.
    public func rows(matching search: String, collapsed: Set<ProjectScopeNode>) -> [Row] {
        let matching = rows(matching: search)
        guard search.folded.split(separator: " ").isEmpty else {
            return matching
        }
        return matching.filter { row in !ancestors(of: row.node).contains(where: collapsed.contains) }
    }

    /// The folding a popover opens with: areas with projects are folded
    /// unless some of their projects, but not all, are checked.
    public func initiallyCollapsed(in scope: ProjectScope) -> Set<ProjectScopeNode> {
        Set(rows.lazy.map(\.node).filter { node in
            guard case .area = node, hasChildren(node) else {
                return false
            }
            return state(of: node, in: scope) != .mixed
        })
    }

    // MARK: Helpers

    private func ancestors(of node: ProjectScopeNode) -> [ProjectScopeNode] {
        var result: [ProjectScopeNode] = []
        var current = node
        while let above = parent[current] {
            result.append(above)
            current = above
        }
        return result
    }

    private func descendants(of node: ProjectScopeNode) -> [ProjectScopeNode] {
        children[node, default: []].flatMap { [$0] + descendants(of: $0) }
    }
}
