// ProjectListing: a project with the names display resolves it to, as an
// entry's listing does (data_and_sync.md §7.3; timer.md §2).

import Foundation
import GRDB

/// A project with its area and client, tombstones included, so history
/// keeps its names (`nil` area or client: not received yet).
public struct ProjectListing: Hashable, Sendable {
    public var project: Project
    public var area: Area?
    public var client: Client?

    public init(project: Project, area: Area?, client: Client?) {
        self.project = project
        self.area = area
        self.client = client
    }
}

extension TimeStore {
    /// The project `id` with its area and client, resolved as
    /// `listings(for:)` does, deleted ones included; `nil` when no project
    /// has the id.
    public func projectListing(_ id: ProjectID) throws -> ProjectListing? {
        try read { database in
            guard let project = try StoreQueries.project(id, includeDeleted: true, in: database) else {
                return nil
            }
            let area = try Row.fetchOne(database, sql: "SELECT * FROM area WHERE id = ?", arguments: [project.areaID.rawValue])
                .map(Area.init(row:))
            let client = try area.flatMap { area in
                try Row.fetchOne(database, sql: "SELECT * FROM client WHERE id = ?", arguments: [area.clientID.rawValue])
                    .map(Client.init(row:))
            }
            return ProjectListing(project: project, area: area, client: client)
        }
    }
}
