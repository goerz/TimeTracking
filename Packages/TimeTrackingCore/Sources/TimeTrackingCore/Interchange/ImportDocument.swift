// ImportDocument: parsing and field validation of an import (data_and_sync.md §5.2, step 1).

import Foundation

/// A parsed export-format document. Every failure names its JSON path.
/// Records carrying `deletedAt` are dropped: an import never deletes.
struct ImportDocument {
    struct Record<Value> {
        var path: String
        var value: Value
    }

    var clients: [Record<Client>] = []
    var areas: [Record<Area>] = []
    var projects: [Record<Project>] = []
    var entries: [Record<TimeEntry>] = []
    var settings: [String: String] = [:]

    /// Parses `data`; defaults come from `context`.
    init(data: Data, context: StoreTransaction, defaultTimeZone: String) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StoreError.invalidDocument(path: "$", reason: "not a JSON object")
        }
        guard root["format"] as? Int == 1 else {
            throw StoreError.invalidDocument(path: "format", reason: "unsupported format")
        }
        let parser = FieldParser(now: context.now)
        for (path, object) in try Self.objects(root, "clients") {
            try clients.append(Record(path: path, value: Client(
                id: parser.id(object, "id", path),
                name: parser.name(object, path),
                createdAt: parser.date(object, "createdAt", path) ?? context.now,
                modifiedAt: context.modifiedAt
            )))
        }
        for (path, object) in try Self.objects(root, "areas") {
            try areas.append(Record(path: path, value: Area(
                id: parser.id(object, "id", path),
                clientID: parser.id(object, "clientID", path),
                name: parser.name(object, path),
                isGeneral: parser.bool(object, "general", path),
                color: parser.color(object, path),
                sortOrder: parser.int(object, "sortOrder", path),
                isRetired: parser.bool(object, "retired", path),
                createdAt: parser.date(object, "createdAt", path) ?? context.now,
                modifiedAt: context.modifiedAt
            )))
        }
        for (path, object) in try Self.objects(root, "projects") {
            try projects.append(Record(path: path, value: Project(
                id: parser.id(object, "id", path),
                areaID: parser.id(object, "areaID", path),
                name: parser.name(object, path),
                isArchived: parser.bool(object, "archived", path),
                archivedAt: parser.date(object, "archivedAt", path),
                createdAt: parser.date(object, "createdAt", path) ?? context.now,
                modifiedAt: context.modifiedAt
            )))
        }
        var chainRoots: [EntryID: EntryID] = [:]
        for (path, object) in try Self.objects(root, "entries") {
            let entry = try parser.entry(object, path, context: context, defaultTimeZone: defaultTimeZone)
            entries.append(Record(path: path, value: entry))
            chainRoots[entry.id] = try parser.optionalID(object, "splitRootID", path)
        }
        mergeChains(roots: chainRoots)
        if let settings = root["settings"] as? [String: Any] {
            for (key, value) in settings {
                let data = try JSONSerialization.data(
                    withJSONObject: value,
                    options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
                )
                self.settings[key] = String(decoding: data, as: UTF8.self)
            }
        }
    }

    /// A document exported before schema version 4 holds entries as midnight
    /// pieces: contiguous ones become one entry, as in the store's migration.
    private mutating func mergeChains(roots: [EntryID: EntryID]) {
        let rootIDs = Set(roots.values)
        let pieces = entries.map(\.value).filter { roots[$0.id] != nil || rootIDs.contains($0.id) }.map { entry in
            ChainPiece(
                id: entry.id.rawValue,
                root: (roots[entry.id] ?? entry.id).rawValue,
                start: Time.seconds(entry.start),
                end: Time.seconds(optional: entry.end)
            )
        }
        var ends: [String: Int64?] = [:]
        var later: Set<String> = []
        for run in ChainRun.runs(of: pieces) {
            ends[run.head] = run.end
            later.formUnion(run.later)
        }
        entries = entries.filter { !later.contains($0.value.id.rawValue) }.map { record in
            var record = record
            if let end = ends[record.value.id.rawValue] {
                record.value.end = Time.date(optional: end)
            }
            return record
        }
    }

    /// The live objects of the array `key`, with their paths.
    private static func objects(_ root: [String: Any], _ key: String) throws -> [(String, [String: Any])] {
        guard let value = root[key] else {
            return []
        }
        guard let array = value as? [Any] else {
            throw StoreError.invalidDocument(path: key, reason: "not an array")
        }
        return try array.enumerated().compactMap { index, element in
            guard let object = element as? [String: Any] else {
                throw StoreError.invalidDocument(path: "\(key)[\(index)]", reason: "not an object")
            }
            if let deleted = object["deletedAt"], !(deleted is NSNull) {
                return nil
            }
            return ("\(key)[\(index)]", object)
        }
    }
}

/// Typed field access with JSON paths in every error.
private struct FieldParser {
    let now: Date

    func fail(_ path: String, _ key: String, _ reason: String) -> StoreError {
        .invalidDocument(path: "\(path).\(key)", reason: reason)
    }

    func present(_ object: [String: Any], _ key: String) -> Any? {
        guard let value = object[key], !(value is NSNull) else {
            return nil
        }
        return value
    }

    func id<Entity>(_ object: [String: Any], _ key: String, _ path: String) throws -> Identifier<Entity> {
        guard let value = present(object, key) else {
            throw fail(path, key, "missing")
        }
        guard let string = value as? String, let id = Identifier<Entity>(string) else {
            throw fail(path, key, "not a UUID")
        }
        return id
    }

    func optionalID<Entity>(_ object: [String: Any], _ key: String, _ path: String) throws -> Identifier<Entity>? {
        try present(object, key).map { _ in try id(object, key, path) }
    }

    func name(_ object: [String: Any], _ path: String) throws -> String {
        guard let name = present(object, "name") as? String, !name.trimmed.isEmpty else {
            throw fail(path, "name", "missing or empty")
        }
        return name.trimmed
    }

    func color(_ object: [String: Any], _ path: String) throws -> String {
        guard let string = present(object, "color") as? String, let color = try? AreaColor(string) else {
            throw fail(path, "color", "not a #RRGGBB color")
        }
        return color.hex
    }

    func bool(_ object: [String: Any], _ key: String, _ path: String) throws -> Bool {
        guard let value = present(object, key) else {
            return false
        }
        guard let bool = value as? Bool else {
            throw fail(path, key, "not a boolean")
        }
        return bool
    }

    func int(_ object: [String: Any], _ key: String, _ path: String) throws -> Int {
        guard let value = present(object, key) else {
            return 0
        }
        guard let int = value as? Int else {
            throw fail(path, key, "not an integer")
        }
        return int
    }

    func date(_ object: [String: Any], _ key: String, _ path: String) throws -> Date? {
        guard let value = present(object, key) else {
            return nil
        }
        guard let string = value as? String, let date = try? Date.ISO8601FormatStyle().parse(string) else {
            throw fail(path, key, "not an RFC 3339 time")
        }
        return Time.whole(date)
    }

    func entry(_ object: [String: Any], _ path: String, context: StoreTransaction, defaultTimeZone: String) throws -> TimeEntry {
        guard let start = try date(object, "start", path) else {
            throw fail(path, "start", "missing")
        }
        guard object["end"] != nil else {
            throw fail(path, "end", "missing")
        }
        let end = try date(object, "end", path)
        if let end, end < start {
            throw fail(path, "end", "before start")
        }
        if start > now {
            throw fail(path, "start", "in the future")
        }
        if let end, end > now {
            throw fail(path, "end", "in the future")
        }
        let zone = present(object, "timeZone") as? String ?? defaultTimeZone
        guard TimeZone(identifier: zone) != nil else {
            throw fail(path, "timeZone", "unknown time zone")
        }
        return try TimeEntry(
            id: id(object, "id", path),
            projectID: optionalID(object, "projectID", path),
            task: (present(object, "task") as? String ?? "").trimmed,
            start: start,
            end: end,
            timeZone: zone,
            deviceID: optionalID(object, "deviceID", path) ?? context.deviceID,
            createdAt: date(object, "createdAt", path) ?? context.now,
            modifiedAt: context.modifiedAt
        )
    }
}
