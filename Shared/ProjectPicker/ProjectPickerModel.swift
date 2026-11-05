// ProjectPickerModel: the shared project picker's state
// (projects.md §5).

import Foundation
import Observation
import TimeTrackingCore

/// What the picker's owner receives.
enum ProjectPickerChoice: Equatable {
    /// A project, or `nil` for "No Project".
    case project(ProjectID?)
    /// "Create Project": open the dialog with this name.
    case create(String)
}

/// Search, rows, and highlight of the picker. The owner decides where it
/// opens and what a choice does.
@Observable
final class ProjectPickerModel {
    @ObservationIgnored let store: TimeStore
    /// The entry's current project (check mark, initial highlight).
    let currentProject: ProjectID?
    /// Whether tasks of the last 90 days also match (the Mac Timer, the iOS Timer).
    let taskMatching: Bool

    var search = ""
    private(set) var content = ProjectPickerContent(search: "", showsNoProject: true, recent: [], groups: [], createName: nil)
    var highlight: ProjectPickerItem?
    /// The search the lines were loaded for.
    @ObservationIgnored private var loadedSearch: String?

    init(store: TimeStore, currentProject: ProjectID?, taskMatching: Bool) {
        self.store = store
        self.currentProject = currentProject
        self.taskMatching = taskMatching
    }

    /// The search field's placeholder.
    var placeholder: String {
        taskMatching ? "Search projects and tasks" : "Search projects"
    }

    /// Reloads for the current search and sets the highlight.
    func reload() async {
        let query = search
        guard let loaded = try? await store.pickerContent(search: query, taskMatching: taskMatching), query == search else {
            return
        }
        content = loaded
        loadedSearch = query
        highlight = loaded.initialHighlight(current: currentProject)
    }

    /// ↑ and ↓.
    func moveHighlight(by offset: Int) {
        let items = content.items
        guard !items.isEmpty else {
            return
        }
        guard let highlight, let index = items.firstIndex(of: highlight) else {
            highlight = items.first
            return
        }
        self.highlight = items[min(max(index + offset, 0), items.count - 1)]
    }

    /// ↩: the highlighted line's choice, unless the search changed since
    /// the lines loaded (the highlight would be the old search's).
    func chooseHighlighted() -> ProjectPickerChoice? {
        guard loadedSearch == search else {
            return nil
        }
        return highlight.map(choice(for:))
    }

    /// Whether the lines are those of the current search.
    var isLoaded: Bool {
        loadedSearch == search
    }

    /// ↩ typed before the lines of the current search loaded: loads them,
    /// then chooses.
    func chooseHighlightedWhenLoaded() async -> ProjectPickerChoice? {
        if loadedSearch != search {
            await reload()
        }
        return chooseHighlighted()
    }

    /// ⌘↩: create from the search text.
    func createFromSearch() -> ProjectPickerChoice? {
        let name = search.trimmed
        return name.isEmpty ? nil : .create(name)
    }

    func choice(for item: ProjectPickerItem) -> ProjectPickerChoice {
        switch item {
        case .noProject: .project(nil)
        case let .recent(id), let .project(id): .project(id)
        case let .create(name): .create(name)
        }
    }
}
