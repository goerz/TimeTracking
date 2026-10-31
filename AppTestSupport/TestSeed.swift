// TestSeed: projects seeded into a test store for the hosted view-model
// tests of both apps (spec_architecture.md §3).

import Foundation
import TimeTrackingCore

/// Seeds a test store.
enum TestSeed {
    /// A client, one area, and the named projects in it.
    static func projects(
        _ names: [String],
        in store: TimeStore,
        client: String,
        area: String,
        color: String? = nil
    ) async throws -> [Project] {
        let (created, _) = try await store.createClient(name: client)
        let area = try await store.createArea(AreaDraft(clientID: created.id, name: area, color: color))
        var projects: [Project] = []
        for name in names {
            try await projects.append(store.createProject(ProjectDraft(areaID: area.id, name: name)))
        }
        return projects
    }
}
