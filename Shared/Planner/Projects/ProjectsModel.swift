// ProjectsModel: the Projects section's view state and actions
// (spec_planner_projects.md §2). Filtering, grouping, sorting, and totals
// come from the library's `ProjectTable`.

import Foundation
import Observation
import os
import TimeTrackingCore

/// A confirmation the view shows as an alert.
struct PlannerConfirmation: Identifiable, Equatable {
    enum Action: Equatable {
        case restore(Set<ProjectID>)
        case delete(ProjectID)
        case merge(ProjectID, into: ProjectID)
    }

    var title: String
    var message: String
    var confirmTitle: String
    var action: Action

    var id: String {
        title + message
    }
}

/// State and commands of the projects table.
@Observable
final class ProjectsModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let device: DeviceSettings
    @ObservationIgnored weak var router: PlannerRouter?
    @ObservationIgnored weak var undoManager: UndoManager?
    /// Starts an entry on the project (the Mac's Timer; iOS's Timer tab).
    @ObservationIgnored var startTimer: (ProjectID) async -> Void = { _ in }
    @ObservationIgnored private(set) var pendingUndo: Task<Void, Never>?

    /// The stored state selector, filters, grouping, and sort.
    var options: ProjectTableOptions {
        didSet {
            device[.projectsOptions] = options
            rebuild()
        }
    }

    /// Not stored.
    var search = "" {
        didSet { rebuild() }
    }

    /// Selected projects (group headers are not selectable).
    var selection: Set<ProjectID> = []
    /// Collapsed group ids per grouping, stored.
    private(set) var collapsed: [String: Set<String>]
    /// The table's encoded column customization, stored.
    var columnData: Data {
        didSet { device[.projectsColumns] = columnData }
    }

    /// The Clients & Areas section's model.
    let clientsAndAreas: ClientsAreasModel
    /// Bumped to focus the search field (⌘F).
    private(set) var searchFocusRequests = 0
    /// The row to scroll to.
    var scrollTarget: ProjectID?
    /// The row in rename mode.
    var renaming: ProjectID?
    var confirmation: PlannerConfirmation?
    /// The project dialog (new or edit).
    var dialog: ProjectDialogModel?
    /// Merge Into…: the project whose target is being picked.
    var mergeSource: ProjectID?
    private(set) var lastError: String?

    private(set) var rows: [ProjectRow] = []
    private(set) var areas: [Area] = []
    private(set) var clients: [Client] = []
    private(set) var table = ProjectTable(groups: [], activeCount: 0, archivedCount: 0)

    init(store: TimeStore, clock: any Clock, device: DeviceSettings) {
        self.store = store
        self.clock = clock
        self.device = device
        self.options = device[.projectsOptions]
        self.collapsed = device[.projectsCollapsed]
        self.columnData = device[.projectsColumns]
        self.clientsAndAreas = ClientsAreasModel(store: store, clock: clock)
        clientsAndAreas.projects = self
    }

    // MARK: Loading

    /// Re-reads projects, areas, and clients (also after any store change).
    func reload() async {
        do {
            rows = try await store.projects(filter: ProjectFilter(state: .all))
            areas = try await store.areas(of: nil, includeRetired: true)
            clients = try await store.clients(includeRetired: true)
        } catch {
            report(error)
        }
        rebuild()
        await clientsAndAreas.reload()
    }

    private func rebuild() {
        table = ProjectTable(rows: rows, areas: areas, options: options, search: search, now: clock.now)
        let visible = Set(table.rows.map(\.id))
        if !selection.isSubset(of: visible) {
            selection.formIntersection(visible)
        }
    }

    // MARK: View state

    /// Whether the State column shows (only on "All").
    var showsStateColumn: Bool {
        options.state == .all
    }

    func isCollapsed(_ group: String) -> Bool {
        collapsed[options.grouping.rawValue, default: []].contains(group)
    }

    /// A group's triangle; with ⌥ every group follows.
    func setExpanded(_ group: String, _ expanded: Bool) {
        let ids = ModifierState.optionDown() ? Set(table.groups.map(\.id)) : [group]
        var set = collapsed[options.grouping.rawValue, default: []]
        if expanded {
            set.subtract(ids)
        } else {
            set.formUnion(ids)
        }
        collapsed[options.grouping.rawValue] = set
        device[.projectsCollapsed] = collapsed
    }

    /// ← and → on a selected row collapse or expand its group.
    func setSelectionGroupExpanded(_ expanded: Bool) {
        for group in table.groups where group.rows.contains(where: { selection.contains($0.id) }) {
            setExpanded(group.id, expanded)
        }
    }

    /// ⌘F.
    func focusSearch() {
        searchFocusRequests += 1
    }

    /// A client or area's header in the table: the Clients & Areas section.
    func showClientsAndAreas(client: ClientID?) {
        router?.showClientsAndAreas(client: client)
    }

    /// "Show Projects" of Clients & Areas: the table filtered to the client or area.
    func showProjects(client: ClientID?, area: AreaID?) {
        var options = options
        options.clients = client.map { [$0] } ?? []
        options.areas = area.map { [$0] } ?? []
        self.options = options
        router?.showProjects()
    }

    /// `showProject`: clears the search, shows the project's state and
    /// filters that hide it, selects and scrolls to its row.
    func reveal(_ id: ProjectID) async {
        await reload()
        guard let row = rows.first(where: { $0.id == id }) else {
            return
        }
        search = ""
        var options = options
        if options.state == .active && row.project.isArchived || options.state == .archived && !row.project.isArchived {
            options.state = .all
        }
        if !ProjectTable(rows: [row], areas: areas, options: options, search: "", now: clock.now).rows.contains(where: { $0.id == id }) {
            options.clearFilters()
        }
        self.options = options
        if let group = table.groups.first(where: { $0.rows.contains { $0.id == id } }), isCollapsed(group.id) {
            setExpanded(group.id, true)
        }
        selection = [id]
        scrollTarget = id
    }

    // MARK: Availability

    var selectedRows: [ProjectRow] {
        rows.filter { selection.contains($0.id) }
    }

    var single: ProjectRow? {
        selectedRows.count == 1 ? selectedRows.first : nil
    }

    var canArchive: Bool {
        selectedRows.contains { !$0.project.isArchived }
    }

    var canRestore: Bool {
        selectedRows.contains(where: \.project.isArchived)
    }

    var canStartTimer: Bool {
        single.map { !$0.project.isArchived } ?? false
    }

    /// Delete…: only for one project without entries.
    var canDelete: Bool {
        single.map { $0.entryCount == 0 } ?? false
    }

    /// "Has N entries; archive it instead".
    var deleteTooltip: String? {
        guard let row = single, row.entryCount > 0 else {
            return nil
        }
        return "Has \(row.entryCount) \(row.entryCount == 1 ? "entry" : "entries"); archive it instead"
    }

    /// "N selected" with several rows selected.
    var selectionText: String? {
        selection.count > 1 ? "\(selection.count) selected" : nil
    }

    // MARK: Helpers

    func perform(
        name: String?,
        _ write: (TimeStore) async throws -> Void,
        undo: (@MainActor (ProjectsModel) async -> Void)? = nil
    ) async {
        do {
            try await write(store)
            if let name, let undo, let undoManager {
                undoManager.registerUndo(withTarget: self) { model in
                    model.pendingUndo = Task { @MainActor in await undo(model) }
                }
                undoManager.setActionName(name)
            }
        } catch {
            report(error)
        }
        await reload()
    }

    func report(_ error: any Error) {
        lastError = UserMessage.text(for: error)
        Logging.logger(category: "Planner").error("Projects command failed: \(String(describing: error), privacy: .public)")
    }

    /// Waits for a pending undo (tests).
    func waitForUndo() async {
        await pendingUndo?.value
    }
}
