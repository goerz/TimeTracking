// ProjectLabel: a project as chips and rows show it (spec_timer_window.md §2,
// §3; spec_planner_projects.md §4.4).

import TimeTrackingCore

/// The project shown on a chip: its name, client, area, and color.
struct ProjectLabel: Equatable, Sendable {
    var name: String
    var client: String?
    var area: String?
    var color: String?

    /// "Noise Model · University" style text, or "No project".
    static let noProject = Self(name: "No project", client: nil, area: nil, color: nil)

    init(name: String, client: String?, area: String?, color: String?) {
        self.name = name
        self.client = client
        self.area = area
        self.color = color
    }

    init(_ listing: EntryListing) {
        if let project = listing.project {
            self.init(name: project.name, client: listing.client?.name, area: listing.area?.name, color: listing.area?.color)
        } else {
            self = .noProject
        }
    }

    init(_ row: ProjectRow) {
        self.init(name: row.project.name, client: row.client?.name, area: row.area?.name, color: row.area?.color)
    }

    /// The label of the live project `id`; "No project" for `nil` or a
    /// project that is missing or deleted.
    static func load(_ id: ProjectID?, from store: TimeStore) async -> Self {
        guard let id, let row = try? await store.projectRow(id) else {
            return .noProject
        }
        return Self(row)
    }

    var isNone: Bool {
        color == nil && client == nil && name == Self.noProject.name
    }

    /// "Project · Client" or "No project".
    var projectAndClient: String {
        guard let client else {
            return name
        }
        return "\(name) · \(client)"
    }
}
