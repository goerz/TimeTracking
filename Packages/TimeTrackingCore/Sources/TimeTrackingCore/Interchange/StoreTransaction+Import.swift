// importDocument: upsert by id in one transaction (spec_data_and_sync.md §5.2).

public import Foundation
import GRDB

extension StoreTransaction {
    /// Validates and upserts an export-format document. The caller's
    /// transaction runs the invariant pass afterwards.
    public func importDocument(_ data: Data, options: ImportOptions) throws -> ImportReport {
        let document = try ImportDocument(
            data: data,
            context: self,
            defaultTimeZone: options.defaultTimeZone ?? timeZone.identifier
        )
        try validateReferences(document)
        var report = ImportReport()
        for record in document.clients {
            try report.counts[.client, default: ImportCounts()].add(upsert(
                record.value,
                existing: client(record.value.id, includeDeleted: true)
            ))
        }
        for record in document.areas {
            try report.counts[.area, default: ImportCounts()].add(upsert(
                record.value,
                existing: area(record.value.id, includeDeleted: true)
            ))
        }
        try addMissingGeneralAreas(document, report: &report)
        for record in document.projects {
            let existing = try project(record.value.id, includeDeleted: true)
            try report.counts[.project, default: ImportCounts()].add(upsert(record.value, existing: existing))
        }
        for record in document.entries {
            try report.counts[.entry, default: ImportCounts()].add(upsert(
                record.value,
                existing: entry(record.value.id, includeDeleted: true)
            ))
        }
        if options.includeSettings {
            for (key, json) in document.settings.sorted(by: { $0.key < $1.key }) {
                try report.counts[.setting, default: ImportCounts()].add(upsertSetting(key, json))
            }
        }
        try validateNames(document)
        return report
    }

    // MARK: Validation

    private func validateReferences(_ document: ImportDocument) throws {
        let clientIDs = Set(document.clients.map(\.value.id))
        let areaIDs = Set(document.areas.map(\.value.id))
        let projectIDs = Set(document.projects.map(\.value.id))
        for record in document.areas where !clientIDs.contains(record.value.clientID) {
            if try client(record.value.clientID) == nil {
                throw StoreError.invalidDocument(path: "\(record.path).clientID", reason: "unknown client")
            }
        }
        for record in document.projects where !areaIDs.contains(record.value.areaID) {
            if try area(record.value.areaID) == nil {
                throw StoreError.invalidDocument(path: "\(record.path).areaID", reason: "unknown area")
            }
        }
        var running: String?
        for record in document.entries {
            if let projectID = record.value.projectID, !projectIDs.contains(projectID), try project(projectID) == nil {
                throw StoreError.invalidDocument(path: "\(record.path).projectID", reason: "unknown project")
            }
            if record.value.end == nil {
                guard running == nil else {
                    throw StoreError.invalidDocument(path: "\(record.path).end", reason: "a second running entry")
                }
                running = record.path
            }
        }
    }

    /// The name rules on the resulting store: a duplicate involving a
    /// document record fails at that record's path.
    private func validateNames(_ document: ImportDocument) throws {
        var paths: [UUID: String] = [:]
        for record in document.clients {
            paths[record.value.id.uuid] = record.path
        }
        for record in document.areas {
            paths[record.value.id.uuid] = record.path
        }
        for record in document.projects {
            paths[record.value.id.uuid] = record.path
        }
        for case let .duplicateName(_, _, ids) in try TimeStore.duplicateNames(in: database) {
            if let path = ids.lazy.compactMap({ paths[$0] }).first {
                throw StoreError.invalidDocument(path: "\(path).name", reason: "duplicate name")
            }
        }
        for record in document.areas where !record.value.isGeneral {
            if let client = try client(record.value.clientID), client.name.folded == record.value.name.folded {
                throw StoreError.invalidDocument(path: "\(record.path).name", reason: "only the general area carries the client's name")
            }
        }
    }

    // MARK: Upserts

    private func addMissingGeneralAreas(_ document: ImportDocument, report: inout ImportReport) throws {
        for record in document.clients {
            let client = record.value
            guard try !(liveAreas(of: client.id).contains(where: \.isGeneral)) else {
                continue
            }
            let id = AreaID(UUID.version5(namespace: client.id.uuid, name: "general-area"))
            if try area(id, includeDeleted: true) != nil {
                report.counts[.area, default: ImportCounts()].skippedDeleted += 1
                continue
            }
            let color = try AreaColor.defaultColor(existing: liveAreaColors())
            try write(Area(
                id: id,
                clientID: client.id,
                name: client.name,
                isGeneral: true,
                color: color.hex,
                createdAt: now,
                modifiedAt: modifiedAt
            ))
            report.counts[.area, default: ImportCounts()].created += 1
        }
    }

    private func outcome<T>(_ value: T, existing: T?, deletedAt: Date?, same: (T, T) -> Bool) -> ImportOutcome {
        guard let existing else {
            return .created
        }
        if deletedAt != nil {
            return .skippedDeleted
        }
        return same(existing, value) ? .unchanged : .updated
    }

    private func upsert(_ client: Client, existing: Client?) throws -> ImportOutcome {
        let result = outcome(client, existing: existing, deletedAt: existing?.deletedAt) { $0.name == $1.name }
        if result == .created || result == .updated {
            var client = client
            client.createdAt = existing?.createdAt ?? client.createdAt
            try write(client)
        }
        return result
    }

    private func upsert(_ area: Area, existing: Area?) throws -> ImportOutcome {
        let result = outcome(area, existing: existing, deletedAt: existing?.deletedAt) { lhs, rhs in
            lhs.clientID == rhs.clientID && lhs.name == rhs.name && lhs.isGeneral == rhs.isGeneral && lhs.color == rhs.color
                && lhs.sortOrder == rhs.sortOrder && lhs.isRetired == rhs.isRetired
        }
        if result == .created || result == .updated {
            var area = area
            area.createdAt = existing?.createdAt ?? area.createdAt
            try write(area)
        }
        return result
    }

    private func upsert(_ project: Project, existing: Project?) throws -> ImportOutcome {
        let result = outcome(project, existing: existing, deletedAt: existing?.deletedAt) { lhs, rhs in
            lhs.areaID == rhs.areaID && lhs.name == rhs.name && lhs.isArchived == rhs.isArchived && lhs.archivedAt == rhs.archivedAt
        }
        if result == .created || result == .updated {
            var project = project
            project.createdAt = existing?.createdAt ?? project.createdAt
            try write(project)
        }
        return result
    }

    private func upsert(_ entry: TimeEntry, existing: TimeEntry?) throws -> ImportOutcome {
        let result = outcome(entry, existing: existing, deletedAt: existing?.deletedAt) { $0.sameContent(as: $1) }
        if result == .created || result == .updated {
            var entry = entry
            entry.createdAt = existing?.createdAt ?? entry.createdAt
            try write(entry)
        }
        return result
    }

    private func upsertSetting(_ key: String, _ json: String) throws -> ImportOutcome {
        let row = try Row.fetchOne(database, sql: "SELECT value, deleted_at FROM setting WHERE key = ?", arguments: [key])
        guard let row else {
            try setSettingJSON(key, json)
            return .created
        }
        if row["deleted_at"] as Int64? != nil {
            return .skippedDeleted
        }
        if row["value"] as String == json {
            return .unchanged
        }
        try setSettingJSON(key, json)
        return .updated
    }
}

/// What happened to one imported record.
enum ImportOutcome {
    case created
    case updated
    case unchanged
    case skippedDeleted
}

extension ImportCounts {
    mutating func add(_ outcome: ImportOutcome) {
        switch outcome {
        case .created: created += 1
        case .updated: updated += 1
        case .unchanged: unchanged += 1
        case .skippedDeleted: skippedDeleted += 1
        }
    }
}
