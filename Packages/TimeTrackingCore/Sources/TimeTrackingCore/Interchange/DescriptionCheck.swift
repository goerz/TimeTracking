// DescriptionCheck: compares a store with a description file and repairs
// what loses no information (spec_automation.md §4.2, §4.3).

import Foundation
import GRDB

/// One difference between the store and the description file.
public struct Inconsistency: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case missingClient = "missing-client"
        case missingArea = "missing-area"
        case retiredArea = "retired-area"
        case colorMismatch = "color-mismatch"
        case missingProject = "missing-project"
        case archivedProject = "archived-project"
        case wrongArea = "wrong-area"
        case unlistedArea = "unlisted-area"
        case unlistedClient = "unlisted-client"
        /// Only with `--strict`.
        case unlistedProject = "unlisted-project"

        /// The rule number of the table in §4.2.
        public var rule: Int {
            switch self {
            case .missingClient: 1
            case .missingArea, .retiredArea: 2
            case .colorMismatch: 3
            case .missingProject, .archivedProject, .wrongArea: 4
            case .unlistedArea: 5
            case .unlistedClient: 6
            case .unlistedProject: 7
            }
        }
    }

    public var kind: Kind
    public var client: String
    public var area: String?
    public var project: String?
    public var actual: String?
    public var expected: String?
    /// The report line.
    public var message: String

    public var json: JSONValue {
        .object([
            "rule": .int(kind.rule),
            "kind": .string(kind.rawValue),
            "client": .string(client),
            "area": .optional(area),
            "project": .optional(project),
            "actual": .optional(actual),
            "expected": .optional(expected),
            "message": .string(message),
        ])
    }
}

/// One repair of `check --fix`.
public struct FixAction: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case createdClient = "created-client"
        case createdArea = "created-area"
        case recoloredArea = "recolored-area"
        case unretiredArea = "unretired-area"
        case unarchivedProject = "unarchived-project"
        case createdProject = "created-project"
    }

    public var kind: Kind
    public var client: String
    public var area: String?
    public var project: String?
    public var message: String

    public var json: JSONValue {
        .object([
            "kind": .string(kind.rawValue),
            "client": .string(client),
            "area": .optional(area),
            "project": .optional(project),
            "message": .string(message),
        ])
    }
}

/// The result of `check` or `check --fix`.
public struct CheckResult: Hashable, Sendable {
    public var actions: [FixAction]
    public var inconsistencies: [Inconsistency]

    /// `{"inconsistencies": [...]}`, with `actions` first after a fix.
    public func json(fixed: Bool) -> JSONValue {
        var members: [JSONValue.Member] = []
        if fixed {
            members.append(JSONValue.Member("actions", .array(actions.map(\.json))))
        }
        members.append(JSONValue.Member("inconsistencies", .array(inconsistencies.map(\.json))))
        return .object(members)
    }
}

/// The store's clients, areas, and projects, live ones only.
struct StructureSnapshot {
    var clients: [Client]
    var areas: [Area]
    var projects: [Project]

    func client(named name: String) -> Client? {
        clients.first { $0.name.folded == name.folded }
    }

    func areas(of client: ClientID) -> [Area] {
        areas.filter { $0.clientID == client }
    }

    /// The area of `client` matching a description area: by name, or the
    /// general area for an area named like its client.
    func area(named name: String, in client: Client) -> Area? {
        let areas = areas(of: client.id)
        if name.folded == client.name.folded, let general = areas.first(where: \.isGeneral) {
            return general
        }
        return areas.first { $0.name.folded == name.folded }
    }

    func projects(of client: ClientID) -> [Project] {
        let ids = Set(areas(of: client).map(\.id))
        return projects.filter { ids.contains($0.areaID) }
    }
}

enum DescriptionCheck {
    /// The violations of §4.2 in rule order, then alphabetically; rule 7
    /// only when `strict`.
    static func inconsistencies(
        _ file: DescriptionFile,
        _ store: StructureSnapshot,
        client filter: String?,
        strict: Bool = false
    ) -> [Inconsistency] {
        var found: [Inconsistency] = []
        for description in described(file, filter) {
            guard let client = store.client(named: description.name) else {
                found.append(.missingClient(description.name))
                continue
            }
            for areaDescription in description.areas {
                found += check(areaDescription, of: client, in: store)
            }
            found += unlistedAreas(description, of: client, in: store)
            if strict {
                found += unlistedProjects(description, of: client, in: store)
            }
        }
        if filter == nil {
            found += unlistedClients(file, in: store)
        }
        return found.sorted { ($0.kind.rule, $0.message.folded) < ($1.kind.rule, $1.message.folded) }
    }

    /// Rules 2 to 4 for one listed area.
    private static func check(
        _ description: DescriptionFile.AreaDescription,
        of client: Client,
        in store: StructureSnapshot
    ) -> [Inconsistency] {
        let path = Place(client: client.name, area: description.name)
        guard let area = store.area(named: description.name, in: client) else {
            return [.missingArea(path)]
        }
        var found: [Inconsistency] = []
        if area.isRetired {
            found.append(.retiredArea(path))
        }
        if area.color.uppercased() != description.color {
            found.append(.colorMismatch(path, actual: area.color.uppercased(), expected: description.color))
        }
        let projects = store.projects(of: client.id)
        for name in description.projects {
            guard let project = projects.first(where: { $0.name.folded == name.folded }) else {
                found.append(.missingProject(path.with(project: name)))
                continue
            }
            if project.isArchived {
                found.append(.archivedProject(path.with(project: project.name)))
            } else if project.areaID != area.id {
                let actual = store.areas.first { $0.id == project.areaID }?.name ?? "?"
                found.append(.wrongArea(path.with(project: project.name), actual: actual))
            }
        }
        return found
    }

    /// Rule 5: areas of a listed client with active projects that the file omits.
    private static func unlistedAreas(
        _ description: DescriptionFile.ClientDescription,
        of client: Client,
        in store: StructureSnapshot
    ) -> [Inconsistency] {
        let listed = Set(description.areas.compactMap { store.area(named: $0.name, in: client)?.id })
        let projects = store.projects(of: client.id)
        return store.areas(of: client.id).filter { !listed.contains($0.id) }.compactMap { area in
            let active = projects.filter { $0.areaID == area.id && $0.isActive }.map(\.name).sorted { $0.folded < $1.folded }
            return active.isEmpty ? nil : .unlistedArea(Place(client: client.name, area: area.name), projects: active)
        }
    }

    /// Rule 7: active projects in a listed area whose name no area of the
    /// client lists (a project listed under another area is rule 4's).
    private static func unlistedProjects(
        _ description: DescriptionFile.ClientDescription,
        of client: Client,
        in store: StructureSnapshot
    ) -> [Inconsistency] {
        let listedNames = Set(description.areas.flatMap(\.projects).map(\.folded))
        let projects = store.projects(of: client.id).filter { $0.isActive && !listedNames.contains($0.name.folded) }
        return description.areas.compactMap { store.area(named: $0.name, in: client) }.flatMap { area in
            projects.filter { $0.areaID == area.id }.map { project in
                Inconsistency.unlistedProject(Place(client: client.name, area: area.name, project: project.name))
            }
        }
    }

    /// Rule 6: clients with active projects that the file omits.
    private static func unlistedClients(_ file: DescriptionFile, in store: StructureSnapshot) -> [Inconsistency] {
        let listed = Set(file.clients.map(\.name.folded))
        return store.clients.filter { !listed.contains($0.name.folded) }.compactMap { client in
            let active = store.projects(of: client.id).count(where: \.isActive)
            return active > 0 ? .unlistedClient(client.name, activeProjects: active) : nil
        }
    }

    private static func described(_ file: DescriptionFile, _ filter: String?) -> [DescriptionFile.ClientDescription] {
        file.clients.filter { filter == nil || $0.name.folded == filter?.folded }
    }

    // MARK: Fix

    /// A repair found after clients and areas exist.
    private enum Repair {
        case recolor(Place, Area, String)
        case unretire(Place, Area)
        case unarchive(Place, Project)
        case create(Place, Area)
    }

    /// Applies the repairs of §4.3 in their order inside `transaction`.
    static func fix(_ file: DescriptionFile, client filter: String?, in transaction: StoreTransaction) throws -> [FixAction] {
        let described = described(file, filter)
        var actions = try createClients(described, in: transaction)
        actions += try createAreas(described, in: transaction)
        let repairs = try plan(described, in: transaction)
        // Recolor, un-retire, unarchive, create: the order of §4.3.
        for repair in repairs {
            if case let .recolor(place, area, color) = repair {
                try transaction.updateArea(area.id, AreaChange(color: color))
                actions.append(.recoloredArea(place, from: area.color.uppercased(), to: color))
            }
        }
        for repair in repairs {
            if case let .unretire(place, area) = repair {
                try transaction.updateArea(area.id, AreaChange(retired: false))
                actions.append(.unretiredArea(place))
            }
        }
        for repair in repairs {
            if case let .unarchive(place, project) = repair {
                try transaction.restoreProject(project.id)
                actions.append(.unarchivedProject(place))
            }
        }
        for repair in repairs {
            if case let .create(place, area) = repair {
                _ = try transaction.createProject(ProjectDraft(areaID: area.id, name: place.project ?? ""))
                actions.append(.createdProject(place))
            }
        }
        return actions
    }

    private static func createClients(
        _ described: [DescriptionFile.ClientDescription],
        in transaction: StoreTransaction
    ) throws -> [FixAction] {
        let snapshot = try transaction.structureSnapshot()
        var actions: [FixAction] = []
        for description in described where snapshot.client(named: description.name) == nil {
            let general = description.areas.first { $0.name.folded == description.name.folded }
            _ = try transaction.createClient(name: description.name, generalAreaColor: general?.color)
            actions.append(.createdClient(description.name))
        }
        return actions
    }

    private static func createAreas(
        _ described: [DescriptionFile.ClientDescription],
        in transaction: StoreTransaction
    ) throws -> [FixAction] {
        let snapshot = try transaction.structureSnapshot()
        var actions: [FixAction] = []
        for description in described {
            guard let client = snapshot.client(named: description.name) else {
                continue
            }
            for area in description.areas where snapshot.area(named: area.name, in: client) == nil {
                _ = try transaction.createArea(AreaDraft(clientID: client.id, name: area.name, color: area.color))
                actions.append(.createdArea(Place(client: client.name, area: area.name), color: area.color))
            }
        }
        return actions
    }

    private static func plan(_ described: [DescriptionFile.ClientDescription], in transaction: StoreTransaction) throws -> [Repair] {
        let snapshot = try transaction.structureSnapshot()
        var repairs: [Repair] = []
        for description in described {
            guard let client = snapshot.client(named: description.name) else {
                continue
            }
            let projects = snapshot.projects(of: client.id)
            for areaDescription in description.areas {
                guard let area = snapshot.area(named: areaDescription.name, in: client) else {
                    continue
                }
                let place = Place(client: client.name, area: area.name)
                if area.color.uppercased() != areaDescription.color {
                    repairs.append(.recolor(place, area, areaDescription.color))
                }
                if area.isRetired {
                    repairs.append(.unretire(place, area))
                }
                for name in areaDescription.projects {
                    if let project = projects.first(where: { $0.name.folded == name.folded }) {
                        if project.isArchived {
                            repairs.append(.unarchive(place.with(project: project.name), project))
                        }
                    } else {
                        repairs.append(.create(place.with(project: name), area))
                    }
                }
            }
        }
        return repairs
    }
}

/// A client, area, and project name, as the report lines show them.
struct Place: Hashable, Sendable {
    var client: String
    var area: String?
    var project: String?

    func with(project: String) -> Self {
        Self(client: client, area: area, project: project)
    }

    /// `Client / Area / Project`.
    var path: String {
        [client, area, project].compactMap(\.self).joined(separator: " / ")
    }
}

extension Inconsistency {
    init(_ kind: Kind, _ place: Place, actual: String? = nil, expected: String? = nil, message: String) {
        self.init(
            kind: kind,
            client: place.client,
            area: place.area,
            project: place.project,
            actual: actual,
            expected: expected,
            message: message
        )
    }

    static func missingClient(_ name: String) -> Self {
        Self(.missingClient, Place(client: name), message: "missing client: \(name)")
    }

    static func missingArea(_ place: Place) -> Self {
        Self(.missingArea, place, message: "missing area: \(place.path)")
    }

    static func retiredArea(_ place: Place) -> Self {
        Self(.retiredArea, place, message: "retired area: \(place.path)")
    }

    static func colorMismatch(_ place: Place, actual: String, expected: String) -> Self {
        Self(
            .colorMismatch,
            place,
            actual: actual,
            expected: expected,
            message: "color mismatch: \(place.path) is \(actual), expected \(expected)"
        )
    }

    static func missingProject(_ place: Place) -> Self {
        Self(.missingProject, place, message: "missing project: \(place.path)")
    }

    static func archivedProject(_ place: Place) -> Self {
        Self(.archivedProject, place, message: "archived project: \(place.path)")
    }

    static func wrongArea(_ place: Place, actual: String) -> Self {
        let expected = place.area ?? ""
        let message = "wrong area: \(place.client) / \(place.project ?? "") is in \(actual), expected \(expected)"
        return Self(.wrongArea, place, actual: actual, expected: expected, message: message)
    }

    static func unlistedArea(_ place: Place, projects: [String]) -> Self {
        Self(.unlistedArea, place, message: "unlisted area: \(place.path) (active projects: \(projects.joined(separator: ", ")))")
    }

    static func unlistedProject(_ place: Place) -> Self {
        Self(.unlistedProject, place, message: "unlisted project: \(place.path)")
    }

    static func unlistedClient(_ name: String, activeProjects: Int) -> Self {
        Self(.unlistedClient, Place(client: name), message: "unlisted client: \(name) (active projects: \(activeProjects))")
    }
}

extension FixAction {
    init(_ kind: Kind, _ place: Place, message: String) {
        self.init(kind: kind, client: place.client, area: place.area, project: place.project, message: message)
    }

    static func createdClient(_ name: String) -> Self {
        Self(.createdClient, Place(client: name), message: "created client: \(name)")
    }

    static func createdArea(_ place: Place, color: String) -> Self {
        Self(.createdArea, place, message: "created area: \(place.path) \(color)")
    }

    static func recoloredArea(_ place: Place, from old: String, to new: String) -> Self {
        Self(.recoloredArea, place, message: "recolored area: \(place.path) from \(old) to \(new)")
    }

    static func unretiredArea(_ place: Place) -> Self {
        Self(.unretiredArea, place, message: "unretired area: \(place.path)")
    }

    static func unarchivedProject(_ place: Place) -> Self {
        Self(.unarchivedProject, place, message: "unarchived project: \(place.path)")
    }

    static func createdProject(_ place: Place) -> Self {
        Self(.createdProject, place, message: "created project: \(place.path)")
    }
}

extension StoreTransaction {
    func structureSnapshot() throws -> StructureSnapshot {
        try StructureSnapshot(
            clients: Row.fetchAll(database, sql: "SELECT * FROM client WHERE deleted_at IS NULL").map(Client.init(row:)),
            areas: Row.fetchAll(database, sql: "SELECT * FROM area WHERE deleted_at IS NULL").map(Area.init(row:)),
            projects: Row.fetchAll(database, sql: "SELECT * FROM project WHERE deleted_at IS NULL").map(Project.init(row:))
        )
    }
}

extension AutomationService {
    /// Compares the store with `file`; only `client` when given; rule 7 too
    /// when `strict`.
    public func check(_ file: DescriptionFile, client: String? = nil, strict: Bool = false) async throws(AutomationError) -> CheckResult {
        let store = store
        let snapshot = try await run {
            try await StructureSnapshot(
                clients: store.clients(includeRetired: true),
                areas: store.areas(of: nil, includeRetired: true),
                projects: store.projects(filter: ProjectFilter(state: .all)).map(\.project)
            )
        }
        return CheckResult(actions: [], inconsistencies: DescriptionCheck.inconsistencies(file, snapshot, client: client, strict: strict))
    }

    /// Repairs what loses no information in one transaction, then checks
    /// again; `strict` adds rule 7 to that check and repairs nothing more.
    public func fix(_ file: DescriptionFile, client: String? = nil, strict: Bool = false) async throws(AutomationError) -> CheckResult {
        let store = store
        let actions = try await run { try await store.transaction { try DescriptionCheck.fix(file, client: client, in: $0) } }
        var result = try await check(file, client: client, strict: strict)
        result.actions = actions
        return result
    }
}
