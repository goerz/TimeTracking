// Client, area, and project writes (spec_data_and_sync.md §1.1 to §1.3, §7.1).

import Foundation
import GRDB

extension StoreTransaction {
    /// Creates a client and its general area.
    public func createClient(name: String, generalAreaColor: String? = nil) throws -> (Client, Area) {
        let name = try validName(name)
        try requireUniqueClientName(name, excluding: nil)
        let color = try generalAreaColor.map { try AreaColor($0) } ?? AreaColor.defaultColor(existing: liveAreaColors())
        let client = Client(name: name, createdAt: now, modifiedAt: modifiedAt)
        let area = Area(clientID: client.id, name: name, isGeneral: true, color: color.hex, createdAt: now, modifiedAt: modifiedAt)
        try write(client)
        try write(area)
        return (client, area)
    }

    /// Renames a client and its general area.
    public func updateClient(_ id: ClientID, name: String) throws {
        guard var client = try client(id) else {
            throw StoreError.unknownID
        }
        let name = try validName(name)
        try requireUniqueClientName(name, excluding: id)
        let areas = try liveAreas(of: id)
        guard !areas.contains(where: { !$0.isGeneral && $0.name.folded == name.folded }) else {
            throw StoreError.duplicateName
        }
        client.name = name
        try write(client)
        for var area in areas where area.isGeneral {
            area.name = name
            try write(area)
        }
    }

    /// Tombstones a client and its general area; fails while it has another
    /// area or a live project.
    public func deleteClient(_ id: ClientID) throws {
        guard var client = try client(id) else {
            throw StoreError.unknownID
        }
        let areas = try liveAreas(of: id)
        guard !areas.contains(where: { !$0.isGeneral }), try liveProjects(of: id).isEmpty else {
            throw StoreError.referenced
        }
        client.deletedAt = now
        try write(client)
        for var area in areas {
            area.deletedAt = now
            try write(area)
        }
    }

    public func createArea(_ draft: AreaDraft) throws -> Area {
        guard let client = try client(draft.clientID) else {
            throw StoreError.unknownID
        }
        let name = try validName(draft.name)
        let areas = try liveAreas(of: client.id)
        guard name.folded != client.name.folded, !areas.contains(where: { $0.name.folded == name.folded }) else {
            throw StoreError.duplicateName
        }
        let color = try draft.color.map { try AreaColor($0) } ?? AreaColor.defaultColor(existing: liveAreaColors())
        let order = draft.sortOrder ?? (areas.map(\.sortOrder).max() ?? 0) + 1
        let area = Area(
            clientID: client.id,
            name: name,
            color: color.hex,
            sortOrder: max(order, 1),
            createdAt: now,
            modifiedAt: modifiedAt
        )
        try write(area)
        return area
    }

    public func updateArea(_ id: AreaID, _ change: AreaChange) throws {
        guard var area = try area(id) else {
            throw StoreError.unknownID
        }
        if area.isGeneral, change.name != nil || change.sortOrder != nil || change.retired != nil {
            throw StoreError.generalArea
        }
        if let color = change.color {
            area.color = try AreaColor(color).hex
        }
        if let name = change.name {
            let name = try validName(name)
            let client = try client(area.clientID, includeDeleted: true)
            let siblings = try liveAreas(of: area.clientID).filter { $0.id != id }
            guard name.folded != client?.name.folded, !siblings.contains(where: { $0.name.folded == name.folded }) else {
                throw StoreError.duplicateName
            }
            area.name = name
        }
        if let order = change.sortOrder {
            area.sortOrder = max(order, 1)
        }
        if let retired = change.retired {
            if retired, try liveProjects(in: id).contains(where: \.isActive) {
                throw StoreError.activeProjects
            }
            area.isRetired = retired
        }
        try write(area)
    }

    public func deleteArea(_ id: AreaID) throws {
        guard var area = try area(id) else {
            throw StoreError.unknownID
        }
        guard !area.isGeneral else {
            throw StoreError.generalArea
        }
        guard try liveProjects(in: id).isEmpty else {
            throw StoreError.referenced
        }
        area.deletedAt = now
        try write(area)
    }

    public func createProject(_ draft: ProjectDraft) throws -> Project {
        guard let area = try area(draft.areaID) else {
            throw StoreError.unknownID
        }
        guard !area.isRetired else {
            throw StoreError.areaRetired
        }
        let name = try validName(draft.name)
        try requireUniqueProjectName(name, client: area.clientID, excluding: nil)
        let id = draft.id ?? ProjectID()
        if try project(id, includeDeleted: true) != nil {
            throw StoreError.referenced
        }
        let project = Project(id: id, areaID: area.id, name: name, createdAt: now, modifiedAt: modifiedAt)
        try write(project)
        return project
    }

    /// Renames or moves a project, also into another client's area.
    public func updateProject(_ id: ProjectID, _ change: ProjectChange) throws {
        guard var project = try project(id) else {
            throw StoreError.unknownID
        }
        if let areaID = change.areaID, areaID != project.areaID {
            guard let area = try area(areaID) else {
                throw StoreError.unknownID
            }
            guard !area.isRetired else {
                throw StoreError.areaRetired
            }
            project.areaID = areaID
        }
        if let name = change.name {
            project.name = try validName(name)
        }
        if let area = try area(project.areaID, includeDeleted: true) {
            try requireUniqueProjectName(project.name, client: area.clientID, excluding: id)
        }
        try write(project)
    }

    public func archive(_ id: ProjectID) throws {
        guard var project = try project(id) else {
            throw StoreError.unknownID
        }
        guard !project.isArchived else {
            return
        }
        project.isArchived = true
        project.archivedAt = now
        try write(project)
    }

    /// Restores an archived project and un-retires its area.
    public func restoreProject(_ id: ProjectID) throws {
        guard var project = try project(id) else {
            throw StoreError.unknownID
        }
        project.isArchived = false
        project.archivedAt = nil
        try write(project)
        if var area = try area(project.areaID), area.isRetired {
            area.isRetired = false
            try write(area)
        }
    }

    /// Moves every live entry of `source` to `target` and tombstones `source`.
    public func merge(project source: ProjectID, into target: ProjectID) throws {
        guard source != target, var project = try project(source), try self.project(target) != nil else {
            throw StoreError.unknownID
        }
        let entries = try Row.fetchAll(
            database,
            sql: "SELECT * FROM time_entry WHERE project_id = ? AND deleted_at IS NULL",
            arguments: [source.rawValue]
        ).map(TimeEntry.init(row:))
        for var entry in entries {
            entry.projectID = target
            try write(entry)
        }
        project.deletedAt = now
        try write(project)
    }

    /// Tombstones a project without live entries.
    public func deleteProject(_ id: ProjectID) throws {
        guard var project = try project(id) else {
            throw StoreError.unknownID
        }
        let used = try Bool.fetchOne(
            database,
            sql: "SELECT 1 FROM time_entry WHERE project_id = ? AND deleted_at IS NULL LIMIT 1",
            arguments: [id.rawValue]
        ) ?? false
        guard !used else {
            throw StoreError.referenced
        }
        project.deletedAt = now
        try write(project)
    }

    // MARK: Name rules

    private func validName(_ name: String) throws -> String {
        let name = name.trimmed
        guard !name.isEmpty else {
            throw StoreError.emptyName
        }
        return name
    }

    private func requireUniqueClientName(_ name: String, excluding: ClientID?) throws {
        let names = try Row.fetchAll(database, sql: "SELECT id, name FROM client WHERE deleted_at IS NULL")
        let clash = names.contains { row in
            (row["name"] as String).folded == name.folded && row["id"] != excluding?.rawValue
        }
        if clash {
            throw StoreError.duplicateName
        }
    }

    private func requireUniqueProjectName(_ name: String, client: ClientID, excluding: ProjectID?) throws {
        let clash = try liveProjects(of: client).contains { $0.id != excluding && $0.name.folded == name.folded }
        if clash {
            throw StoreError.duplicateName
        }
    }
}
