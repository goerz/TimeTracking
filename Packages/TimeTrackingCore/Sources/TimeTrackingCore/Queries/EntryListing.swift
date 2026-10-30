// EntryListing: an entry with the names display and CSV resolve it to
// (spec_data_and_sync.md §7.3, spec_automation.md §8.2). Client and area come
// from the project's current area.

import Foundation
import GRDB

/// An entry with its project, area, and client (each `nil` when absent or
/// not received yet).
public struct EntryListing: Identifiable, Hashable, Sendable {
    public var entry: TimeEntry
    public var project: Project?
    public var area: Area?
    public var client: Client?

    public init(entry: TimeEntry, project: Project?, area: Area?, client: Client?) {
        self.entry = entry
        self.project = project
        self.area = area
        self.client = client
    }

    public var id: EntryID {
        entry.id
    }
}

extension TimeStore {
    /// Resolves the project, area, and client of each entry, tombstones
    /// included, so history keeps its names.
    public func listings(for entries: [TimeEntry]) throws -> [EntryListing] {
        try read { database in
            let projects = try Dictionary(
                Row.fetchAll(database, sql: "SELECT * FROM project").map(Project.init(row:)).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let areas = try Dictionary(
                Row.fetchAll(database, sql: "SELECT * FROM area").map(Area.init(row:)).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let clients = try Dictionary(
                Row.fetchAll(database, sql: "SELECT * FROM client").map(Client.init(row:)).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            return entries.map { entry in
                let project = entry.projectID.flatMap { projects[$0] }
                let area = project.flatMap { areas[$0.areaID] }
                return EntryListing(entry: entry, project: project, area: area, client: area.flatMap { clients[$0.clientID] })
            }
        }
    }
}
