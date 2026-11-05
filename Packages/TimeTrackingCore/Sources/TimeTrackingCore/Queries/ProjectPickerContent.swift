// ProjectPickerContent: the rows of the shared project picker
// (projects.md §5, timer.md §2.3).

import Foundation

/// One project row of the picker.
public struct ProjectPickerRow: Hashable, Sendable, Identifiable {
    public var project: Project
    public var area: Area
    public var client: Client
    /// The trailing text: "Client · Area" (Recent) or the area name (client
    /// groups); "Client" or empty for a general area.
    public var trailing: String

    public init(project: Project, area: Area, client: Client, trailing: String) {
        self.project = project
        self.area = area
        self.client = client
        self.trailing = trailing
    }

    public var id: ProjectID {
        project.id
    }
}

/// A client's group of project rows.
public struct ProjectPickerGroup: Hashable, Sendable, Identifiable {
    public var client: Client
    public var rows: [ProjectPickerRow]

    public init(client: Client, rows: [ProjectPickerRow]) {
        self.client = client
        self.rows = rows
    }

    public var id: ClientID {
        client.id
    }
}

/// A selectable line of the picker, in display order.
public enum ProjectPickerItem: Hashable, Sendable {
    case noProject
    case recent(ProjectID)
    case project(ProjectID)
    /// "+ Create Project “name”".
    case create(String)

    /// The project the item assigns, if any.
    public var projectID: ProjectID? {
        switch self {
        case let .recent(id), let .project(id): id
        case .noProject, .create: nil
        }
    }
}

/// Everything the picker shows for one search text.
public struct ProjectPickerContent: Hashable, Sendable {
    public var search: String
    /// "No Project", hidden while searching.
    public var showsNoProject: Bool
    /// Up to five recent active projects; empty while searching.
    public var recent: [ProjectPickerRow]
    public var groups: [ProjectPickerGroup]
    /// The name of the "Create Project" row, if shown.
    public var createName: String?

    public init(search: String, showsNoProject: Bool, recent: [ProjectPickerRow], groups: [ProjectPickerGroup], createName: String?) {
        self.search = search
        self.showsNoProject = showsNoProject
        self.recent = recent
        self.groups = groups
        self.createName = createName
    }

    /// The selectable lines in display order.
    public var items: [ProjectPickerItem] {
        var items: [ProjectPickerItem] = showsNoProject ? [.noProject] : []
        items += recent.map { .recent($0.id) }
        items += groups.flatMap { $0.rows.map { .project($0.id) } }
        if let createName {
            items.append(.create(createName))
        }
        return items
    }

    /// The line highlighted when the content appears: with an empty search
    /// the current project's Recent row, else its client row, else the
    /// first Recent row; while searching the first match.
    public func initialHighlight(current: ProjectID?) -> ProjectPickerItem? {
        let items = items
        if search.trimmed.isEmpty {
            if let current {
                if items.contains(.recent(current)) {
                    return .recent(current)
                }
                if items.contains(.project(current)) {
                    return .project(current)
                }
            }
            return recent.first.map { .recent($0.id) } ?? items.first
        }
        return items.first
    }

    /// Whether every word of `query` occurs, case- and diacritic-insensitively,
    /// in the project, area, or client name (`projects.md` §2.4).
    public static func matches(_ query: String, project: String, area: String, client: String) -> Bool {
        let names = [project, area, client].map(\.folded)
        return query.folded.split(whereSeparator: \.isWhitespace).allSatisfy { word in
            names.contains { $0.contains(word) }
        }
    }
}
