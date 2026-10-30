// The structure listings and writes of the tool (spec_automation.md §3.8, §3.9).

import Foundation

extension AutomationService {
    /// How `projects` sorts.
    public enum ProjectSort: String, Sendable, CaseIterable {
        case name
        case client
        case area
        case lastEntry = "last-entry"
    }

    /// Projects by state, client, and area; default order client, area, name.
    public func projects(
        state: ProjectFilter.State = .active,
        client: String? = nil,
        area: String? = nil,
        sort: ProjectSort = .client
    ) async throws(AutomationError) -> [ProjectRow] {
        let store = store
        var clientID: ClientID?
        if let client {
            clientID = try await store.resolveClient(client).id
        }
        // swiftlint:disable:next discouraged_optional_collection
        var areaIDs: Set<AreaID>?
        if let area {
            areaIDs = try await self.areaIDs(named: area, client: clientID)
        }
        let rows = try await run {
            try await store.projects(filter: ProjectFilter(state: state, clientIDs: clientID.map { [$0] }, areaIDs: areaIDs))
        }
        let areaOrder = try await run { try await store.areas(of: nil, includeRetired: true) }
            .enumerated().reduce(into: [AreaID: Int]()) { $0[$1.element.id] = $1.offset }
        // swiftlint:disable:next large_tuple
        func key(_ row: ProjectRow) -> (String, Int, String) {
            (row.client?.name.folded ?? "\u{10FFFF}", areaOrder[row.project.areaID] ?? .max, row.project.name.folded)
        }
        let ordered = rows.sorted { key($0) < key($1) }
        switch sort {
        case .client:
            return ordered
        case .name:
            return ordered.stableSorted { $0.project.name.folded < $1.project.name.folded }
        case .area:
            return ordered.stableSorted { ($0.area?.name.folded ?? "") < ($1.area?.name.folded ?? "") }
        case .lastEntry:
            return ordered.stableSorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        }
    }

    /// Clients alphabetically with their area and active project counts.
    public func clients() async throws(AutomationError) -> [ClientSummary] {
        let store = store
        return try await run {
            let areas = try await store.areas(of: nil, includeRetired: true)
            let projects = try await store.projects(filter: ProjectFilter(state: .active))
            return try await store.clients(includeRetired: true).map { client in
                ClientSummary(
                    client: client,
                    areaCount: areas.count { $0.clientID == client.id },
                    activeProjectCount: projects.count { $0.client?.id == client.id }
                )
            }
        }
    }

    /// Areas by client; retired areas only with `includeRetired`.
    public func areas(client: String? = nil, includeRetired: Bool = false) async throws(AutomationError) -> [AreaSummary] {
        let store = store
        var clientID: ClientID?
        if let client {
            clientID = try await store.resolveClient(client).id
        }
        return try await run {
            let clients = try await Dictionary(
                store.clients(includeRetired: true).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let projects = try await store.projects(filter: ProjectFilter(state: .active))
            return try await store.areas(of: clientID, includeRetired: includeRetired).map { area in
                AreaSummary(area: area, client: clients[area.clientID], activeProjectCount: projects.count { $0.project.areaID == area.id })
            }
        }
    }

    // MARK: Writes

    /// Creates an active project in `area` (of `client` when given).
    public func createProject(_ name: String, area: String, client: String?) async throws(AutomationError) -> ProjectRow {
        let store = store
        let area = try await store.resolveArea(area, client: client)
        let project = try await run { try await store.createProject(ProjectDraft(areaID: area.id, name: name)) }
        return try await row(project.id)
    }

    /// Archives a project; refuses one already archived.
    public func archiveProject(_ reference: String, client: String?) async throws(AutomationError) -> ProjectRow {
        let store = store
        let row = try await store.resolveProject(reference, client: client, includeArchived: true)
        guard !row.project.isArchived else {
            throw .refused("Project \"\(row.project.name)\" is archived already.")
        }
        try await run { try await store.archive(row.project.id) }
        return try await self.row(row.project.id)
    }

    /// Unarchives a project; refuses an active one.
    public func unarchiveProject(_ reference: String, client: String?) async throws(AutomationError) -> ProjectRow {
        let store = store
        let row = try await store.resolveProject(reference, client: client, includeArchived: true)
        guard row.project.isArchived else {
            throw .refused("Project \"\(row.project.name)\" is active already.")
        }
        try await run { try await store.restoreProject(row.project.id) }
        return try await self.row(row.project.id)
    }

    /// Renames a project; refuses a name taken in its client.
    public func renameProject(_ reference: String, to name: String, client: String?) async throws(AutomationError) -> ProjectRow {
        let store = store
        let row = try await store.resolveProject(reference, client: client, includeArchived: true)
        try await run { try await store.updateProject(row.project.id, ProjectChange(name: name)) }
        return try await self.row(row.project.id)
    }

    /// Moves a project to `area` of `client` (any client).
    public func moveProject(_ reference: String, toArea area: String, client: String?) async throws(AutomationError) -> ProjectRow {
        let store = store
        let row = try await store.resolveProject(reference, includeArchived: true)
        let target = try await store.resolveArea(area, client: client)
        try await run { try await store.updateProject(row.project.id, ProjectChange(areaID: target.id)) }
        return try await self.row(row.project.id)
    }

    /// Creates an area; the default color when `color` is `nil`.
    public func createArea(_ name: String, client: String, color: String?) async throws(AutomationError) -> AreaSummary {
        let store = store
        let color = try color.map { text throws(AutomationError) in try Self.color(text) }
        let client = try await store.resolveClient(client)
        let area = try await run { try await store.createArea(AreaDraft(clientID: client.id, name: name, color: color)) }
        return AreaSummary(area: area, client: client, activeProjectCount: 0)
    }

    /// Renames an area; refuses the general area and a taken name.
    public func renameArea(_ name: String, to newName: String, client: String) async throws(AutomationError) -> AreaSummary {
        let store = store
        let area = try await store.resolveArea(name, client: client)
        guard !area.isGeneral else {
            throw .refused("Area \"\(area.name)\" is the general area of its client; rename the client instead.")
        }
        try await run { try await store.updateArea(area.id, AreaChange(name: newName)) }
        return try await summary(area.id)
    }

    /// Recolors an area.
    public func setAreaColor(_ name: String, color: String, client: String?) async throws(AutomationError) -> AreaSummary {
        let store = store
        let color = try Self.color(color)
        let area = try await store.resolveArea(name, client: client)
        try await run { try await store.updateArea(area.id, AreaChange(color: color)) }
        return try await summary(area.id)
    }

    /// Creates a client with its general area.
    public func createClient(_ name: String, color: String?) async throws(AutomationError) -> ClientSummary {
        let store = store
        let color = try color.map { text throws(AutomationError) in try Self.color(text) }
        let (client, _) = try await run { try await store.createClient(name: name, generalAreaColor: color) }
        return ClientSummary(client: client, areaCount: 1, activeProjectCount: 0)
    }

    /// Renames a client and its general area.
    public func renameClient(_ name: String, to newName: String) async throws(AutomationError) -> ClientSummary {
        let store = store
        let client = try await store.resolveClient(name)
        try await run { try await store.updateClient(client.id, name: newName) }
        guard let summary = try await clients().first(where: { $0.client.id == client.id }) else {
            throw .notFound("No client named \"\(newName)\".")
        }
        return summary
    }

    // MARK: Helpers

    /// A `#RRGGBB` color in upper case; anything else is a usage error.
    public static func color(_ text: String) throws(AutomationError) -> String {
        guard text.wholeMatch(of: /#[0-9A-Fa-f]{6}/) != nil, let color = try? AreaColor(text) else {
            throw .usage("Malformed color \"\(text)\"; use #RRGGBB.")
        }
        return color.hex
    }

    func row(_ id: ProjectID) async throws(AutomationError) -> ProjectRow {
        let store = store
        let rows = try await run { try await store.projects(filter: ProjectFilter(state: .all)) }
        guard let row = rows.first(where: { $0.project.id == id }) else {
            throw .notFound("No project with id \(id.rawValue).")
        }
        return row
    }

    private func summary(_ id: AreaID) async throws(AutomationError) -> AreaSummary {
        guard let summary = try await areas(includeRetired: true).first(where: { $0.area.id == id }) else {
            throw .notFound("No area with id \(id.rawValue).")
        }
        return summary
    }

    private func areaIDs(named name: String, client: ClientID?) async throws(AutomationError) -> Set<AreaID> {
        let store = store
        let areas = try await run { try await store.areas(of: client, includeRetired: true) }
        let matches = areas.filter { $0.name.folded == name.folded }
        guard !matches.isEmpty else {
            throw .notFound("No area named \"\(name.trimmed)\".")
        }
        return Set(matches.map(\.id))
    }
}

extension Array {
    /// Sorted by `areInIncreasingOrder`, equal elements keeping their order.
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { lhs, rhs in
            areInIncreasingOrder(lhs.element, rhs.element)
                || (!areInIncreasingOrder(rhs.element, lhs.element) && lhs.offset < rhs.offset)
        }.map(\.element)
    }
}

/// A client with its counts, for `clients`.
public struct ClientSummary: Hashable, Sendable {
    public var client: Client
    public var areaCount: Int
    public var activeProjectCount: Int
}

/// An area with its client and active project count, for `areas`.
public struct AreaSummary: Hashable, Sendable {
    public var area: Area
    public var client: Client?
    public var activeProjectCount: Int
}
