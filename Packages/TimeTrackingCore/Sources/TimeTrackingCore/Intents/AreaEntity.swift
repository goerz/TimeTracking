// AreaEntity and ClientEntity: areas and clients for Shortcuts
// (automation.md §5).

public import AppIntents
public import Foundation

/// An area, identified by its UUID.
public struct AreaEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Area"
    public static let defaultQuery = AreaEntityQuery()

    public let id: UUID
    @Property(title: "Name") public var name: String
    @Property(title: "Color") public var color: String
    @Property(title: "Client") public var client: String

    public init(_ summary: AreaSummary) {
        self.id = summary.area.id.uuid
        self.name = summary.area.name
        self.color = summary.area.color.uppercased()
        self.client = summary.client?.name ?? ""
    }

    public var areaID: AreaID {
        AreaID(id)
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(client)")
    }
}

/// All live areas that are not retired; by name.
public struct AreaEntityQuery: EnumerableEntityQuery, EntityStringQuery {
    @Dependency private var environment: IntentEnvironment

    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [AreaEntity] {
        let wanted = Set(identifiers)
        return try await summaries(includeRetired: true).filter { wanted.contains($0.area.id.uuid) }.map(AreaEntity.init)
    }

    public func allEntities() async throws -> [AreaEntity] {
        try await summaries(includeRetired: false).map(AreaEntity.init)
    }

    public func entities(matching string: String) async throws -> [AreaEntity] {
        let needle = string.folded
        return try await summaries(includeRetired: false).filter { $0.area.name.folded.contains(needle) }.map(AreaEntity.init)
    }

    public func suggestedEntities() async throws -> [AreaEntity] {
        try await allEntities()
    }

    private func summaries(includeRetired: Bool) async throws -> [AreaSummary] {
        try await environment.automation().areas(includeRetired: includeRetired)
    }
}

/// A client, identified by its UUID.
public struct ClientEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Client"
    public static let defaultQuery = ClientEntityQuery()

    public let id: UUID
    @Property(title: "Name") public var name: String

    public init(_ client: Client) {
        self.id = client.id.uuid
        self.name = client.name
    }

    public var clientID: ClientID {
        ClientID(id)
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// All live clients, alphabetically.
public struct ClientEntityQuery: EnumerableEntityQuery {
    @Dependency private var environment: IntentEnvironment

    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [ClientEntity] {
        let wanted = Set(identifiers)
        return try await allEntities().filter { wanted.contains($0.id) }
    }

    public func allEntities() async throws -> [ClientEntity] {
        try await environment.automation().clients().map { ClientEntity($0.client) }
    }

    public func suggestedEntities() async throws -> [ClientEntity] {
        try await allEntities()
    }
}
