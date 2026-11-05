// JSON export, the backup and interchange format (data_and_sync.md §5.1).

public import Foundation
import GRDB

extension TimeStore {
    /// The whole store as one document: RFC 3339 UTC times, sorted records,
    /// sorted object keys, synced settings only, no push tokens.
    public func exportDocument(includeDeleted: Bool = false) throws -> Data {
        let object = try exportObject(includeDeleted: includeDeleted)
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    func exportObject(includeDeleted: Bool) throws -> [String: Any] {
        let generatedAt = clock.now
        let storeID = try storeID()
        let records = try read { try ExportRecords(database: $0, includeDeleted: includeDeleted) }
        let clientNames = Dictionary(uniqueKeysWithValues: records.clients.map { ($0.id, $0.name.folded) })
        return [
            "format": 1,
            "generatedAt": Self.rfc3339(generatedAt),
            "storeID": storeID,
            "clients": records.clients.sorted { ($0.name.folded, $0.id) < ($1.name.folded, $1.id) }.map(Self.object),
            "areas": records.areas.sorted { lhs, rhs in
                (clientNames[lhs.clientID] ?? "", lhs.clientID, lhs.sortOrder, lhs.name.folded, lhs.id)
                    < (clientNames[rhs.clientID] ?? "", rhs.clientID, rhs.sortOrder, rhs.name.folded, rhs.id)
            }.map(Self.object),
            "projects": records.projects.sorted { ($0.name.folded, $0.id) < ($1.name.folded, $1.id) }.map(Self.object),
            "entries": records.entries.map(Self.object),
            "settings": records.settings,
            "devices": records.devices.sorted { ($0.name, $0.id) < ($1.name, $1.id) }.map { device in
                ["id": device.id.rawValue, "name": device.name, "platform": device.platform.rawValue]
            },
        ]
    }

    /// RFC 3339 in UTC with whole seconds (`2024-03-14T10:00:00Z`), the
    /// timestamps of the export format and of `LiveState`; fractions are
    /// truncated, never rounded.
    static func rfc3339(_ date: Date) -> String {
        Time.whole(date).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: false, timeZone: .gmt))
    }

    private static func nullable(_ value: String?) -> Any {
        value ?? NSNull()
    }

    private static func withDeletion(_ object: [String: Any], _ deletedAt: Date?) -> [String: Any] {
        var object = object
        if let deletedAt {
            object["deletedAt"] = rfc3339(deletedAt)
        }
        return object
    }

    private static func object(_ client: Client) -> [String: Any] {
        withDeletion(["id": client.id.rawValue, "name": client.name, "createdAt": rfc3339(client.createdAt)], client.deletedAt)
    }

    private static func object(_ area: Area) -> [String: Any] {
        withDeletion([
            "id": area.id.rawValue, "clientID": area.clientID.rawValue, "name": area.name, "general": area.isGeneral,
            "color": area.color, "sortOrder": area.sortOrder, "retired": area.isRetired, "createdAt": rfc3339(area.createdAt),
        ], area.deletedAt)
    }

    private static func object(_ project: Project) -> [String: Any] {
        withDeletion([
            "id": project.id.rawValue, "areaID": project.areaID.rawValue, "name": project.name, "archived": project.isArchived,
            "archivedAt": nullable(project.archivedAt.map(rfc3339)), "createdAt": rfc3339(project.createdAt),
        ], project.deletedAt)
    }

    private static func object(_ entry: TimeEntry) -> [String: Any] {
        withDeletion([
            "id": entry.id.rawValue, "projectID": nullable(entry.projectID?.rawValue), "task": entry.task,
            "start": rfc3339(entry.start), "end": nullable(entry.end.map(rfc3339)), "timeZone": entry.timeZone,
            "deviceID": entry.deviceID.rawValue,
        ], entry.deletedAt)
    }
}

/// The rows an export reads in one transaction.
private struct ExportRecords {
    var clients: [Client]
    var areas: [Area]
    var projects: [Project]
    var entries: [TimeEntry]
    var settings: [String: Any] = [:]
    var devices: [Device]

    init(database: Database, includeDeleted: Bool) throws {
        let live = includeDeleted ? "1 = 1" : "deleted_at IS NULL"
        self.clients = try Row.fetchAll(database, sql: "SELECT * FROM client WHERE \(live)").map(Client.init(row:))
        self.areas = try Row.fetchAll(database, sql: "SELECT * FROM area WHERE \(live)").map(Area.init(row:))
        self.projects = try Row.fetchAll(database, sql: "SELECT * FROM project WHERE \(live)").map(Project.init(row:))
        self.entries = try Row.fetchAll(database, sql: "SELECT * FROM time_entry WHERE \(live) ORDER BY start, id")
            .map(TimeEntry.init(row:))
        self.devices = try Row.fetchAll(database, sql: "SELECT * FROM device").map(Device.init(row:))
        for row in try Row.fetchAll(database, sql: "SELECT key, value FROM setting WHERE deleted_at IS NULL") {
            let json: String = row["value"]
            settings[row["key"]] = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
        }
    }
}
