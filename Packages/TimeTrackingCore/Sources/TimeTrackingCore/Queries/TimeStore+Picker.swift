// The project picker's query (spec_planner_projects.md §5).

public import Foundation

extension TimeStore {
    /// How far back task matching looks.
    public static let pickerTaskMatchWindow: TimeInterval = 90 * 86_400

    /// The picker's rows for `search`. With `taskMatching`, a project also
    /// matches when a task tracked under it in the last 90 days contains
    /// the search text. Archived projects and retired areas never appear.
    public func pickerContent(search: String, taskMatching: Bool = false) throws -> ProjectPickerContent {
        let query = search.trimmed
        let rows = try projects(filter: ProjectFilter(state: .active)).compactMap { row -> ProjectPickerRow? in
            guard let area = row.area, !area.isRetired, let client = row.client else {
                return nil
            }
            return ProjectPickerRow(project: row.project, area: area, client: client, trailing: "")
        }
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })

        var recent: [ProjectPickerRow] = []
        var visible = rows
        if query.isEmpty {
            recent = try recentProjects(limit: 50).compactMap { byID[$0] }.prefix(5).map { row in
                var row = row
                row.trailing = row.area.isGeneral ? row.client.name : "\(row.client.name) · \(row.area.name)"
                return row
            }
        } else {
            let taskMatches = taskMatching
                ? try Set(projectsByTask(matching: query, since: clock.now - Self.pickerTaskMatchWindow))
                : []
            visible = rows.filter { row in
                taskMatches.contains(row.id)
                    || ProjectPickerContent.matches(query, project: row.project.name, area: row.area.name, client: row.client.name)
            }
        }

        let groups = Dictionary(grouping: visible, by: \.client.id).values
            .compactMap { rows -> ProjectPickerGroup? in
                guard let client = rows.first?.client else {
                    return nil
                }
                let sorted = rows.sorted { lhs, rhs in
                    (lhs.area.sortOrder, lhs.area.name.folded, lhs.project.name.folded, lhs.id)
                        < (rhs.area.sortOrder, rhs.area.name.folded, rhs.project.name.folded, rhs.id)
                }
                return ProjectPickerGroup(client: client, rows: sorted.map { row in
                    var row = row
                    row.trailing = row.area.isGeneral ? "" : row.area.name
                    return row
                })
            }
            .sorted { ($0.client.name.folded, $0.client.id) < ($1.client.name.folded, $1.client.id) }

        let folded = query.folded
        let exists = rows.contains { $0.project.name.folded == folded }
        return ProjectPickerContent(
            search: search,
            showsNoProject: query.isEmpty,
            recent: recent,
            groups: groups,
            createName: query.isEmpty || exists ? nil : query
        )
    }

    /// Whether `name` (trimmed, folded) is taken by a live project of
    /// `client` in any state other than `excluding` (the project dialog's
    /// inline check, `spec_planner_projects.md` §3.1).
    public func projectNameIsTaken(_ name: String, client: ClientID, excluding: ProjectID? = nil) throws -> Bool {
        let folded = name.folded
        let areas = try Set(areas(of: client, includeRetired: true).map(\.id))
        return try projects(filter: ProjectFilter(state: .all)).contains { row in
            areas.contains(row.project.areaID) && row.id != excluding && row.project.name.folded == folded
        }
    }
}
