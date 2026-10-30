// Resolving the names scripts use for projects, areas, and clients
// (spec_automation.md §3.3).

import Foundation

extension TimeStore {
    /// The live client named `name` (trimmed, case- and diacritic-insensitive).
    public func resolveClient(_ name: String) throws(AutomationError) -> Client {
        let clients = try automation { try clients(includeRetired: true) }
        guard let client = clients.first(where: { $0.name.folded == name.folded }) else {
            throw .notFound("No client named \"\(name.trimmed)\".")
        }
        return client
    }

    /// The live area named `name`, in `client` when given. Retired areas
    /// match only with `includeRetired`.
    public func resolveArea(_ name: String, client: String?, includeRetired: Bool = true) throws(AutomationError) -> Area {
        let clientID = try client.map { name throws(AutomationError) in try resolveClient(name).id }
        let areas = try automation { try areas(of: clientID, includeRetired: includeRetired) }
        let matches = areas.filter { $0.name.folded == name.folded }
        switch matches.count {
        case 0:
            throw .notFound("No area named \"\(name.trimmed)\"\(client.map { " in \($0.trimmed)" } ?? "").")
        case 1:
            return matches[0]
        default:
            let names = try clientNames()
            throw .ambiguous(
                "The area name \"\(name.trimmed)\" exists in several clients; add --client:",
                candidates: matches.map { "\(names[$0.clientID] ?? "?")/\($0.name)" }.sorted()
            )
        }
    }

    /// The live project `reference` names: a name or `Client/Project`, in
    /// `client` when given. Archived projects match only with
    /// `includeArchived`; otherwise a name matching only an archived project
    /// is refused with the tool's exit-4 message.
    public func resolveProject(
        _ reference: String,
        client: String? = nil,
        includeArchived: Bool = false
    ) throws(AutomationError) -> ProjectRow {
        let rows = try automation { try projects(filter: ProjectFilter(state: .all)) }
        var candidates = rows.filter { $0.project.name.folded == reference.folded }
        var clientName = client
        if candidates.isEmpty, client == nil, let slash = reference.firstIndex(of: "/") {
            clientName = String(reference[..<slash])
            let name = String(reference[reference.index(after: slash)...])
            candidates = rows.filter { $0.project.name.folded == name.folded }
        }
        if let clientName {
            let id = try resolveClient(clientName).id
            candidates = candidates.filter { $0.client?.id == id }
        }
        let active = includeArchived ? candidates : candidates.filter { !$0.project.isArchived }
        switch active.count {
        case 1:
            return active[0]
        case 0:
            if let archived = candidates.first {
                throw .refused("Project \"\(archived.project.name)\" is archived; unarchive it first.")
            }
            throw .notFound("No project named \"\(reference.trimmed)\".")
        default:
            throw .ambiguous(
                "The project name \"\(reference.trimmed)\" exists in several clients; use Client/Project or --client:",
                candidates: active.map { "\($0.client?.name ?? "?")/\($0.project.name)" }.sorted()
            )
        }
    }

    /// The live entry with the id `text`.
    public func resolveEntry(_ text: String) throws(AutomationError) -> TimeEntry {
        guard let id = EntryID(text.trimmed.lowercased()) else {
            throw .usage("Malformed entry id \"\(text)\".")
        }
        guard let entry = try automation({ try entry(id) }) else {
            throw .notFound("No entry with id \(id.rawValue).")
        }
        return entry
    }

    /// The live project with the id `text`.
    public func resolveProject(id text: String) throws(AutomationError) -> ProjectRow {
        guard let id = ProjectID(text.trimmed.lowercased()) else {
            throw .usage("Malformed project id \"\(text)\".")
        }
        let rows = try automation { try projects(filter: ProjectFilter(state: .all)) }
        guard let row = rows.first(where: { $0.project.id == id }) else {
            throw .notFound("No project with id \(id.rawValue).")
        }
        return row
    }

    func clientNames() throws(AutomationError) -> [ClientID: String] {
        let clients = try automation { try clients(includeRetired: true) }
        return Dictionary(clients.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// Runs a store call, turning its errors into automation errors.
    func automation<R>(_ body: () throws -> R) throws(AutomationError) -> R {
        do {
            return try body()
        } catch {
            throw AutomationError(wrapping: error)
        }
    }
}
