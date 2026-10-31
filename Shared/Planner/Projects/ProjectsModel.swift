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

    /// Selected projects; selecting one clears a selected client or area row.
    var selection: Set<ProjectID> = [] {
        didSet {
            if !selection.isEmpty, clientsAndAreas.selection != nil {
                clientsAndAreas.selection = nil
            }
        }
    }

    /// Collapsed group ids per grouping, stored.
    private(set) var collapsed: [String: Set<String>]
    /// The table's encoded column customization, stored.
    var columnData: Data {
        didSet { device[.projectsColumns] = columnData }
    }

    /// The client and area rows' sheets and actions.
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
    /// New Project… on an area or client row: the dialog's area.
    var newProjectArea: AreaID?
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
        table = ProjectTable(rows: rows, clients: clients, areas: areas, options: options, search: search, now: clock.now)
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
        let ids = ModifierState.optionDown() ? Set(table.allGroups.map(\.id)) : [group]
        var set = collapsed[options.grouping.rawValue, default: []]
        if expanded {
            set.subtract(ids)
        } else {
            set.formUnion(ids)
        }
        collapsed[options.grouping.rawValue] = set
        device[.projectsCollapsed] = collapsed
    }

    /// ← and → on a selected client or area row collapse or expand it; on
    /// selected projects, their group.
    func setSelectionGroupExpanded(_ expanded: Bool) {
        if let row = clientsAndAreas.selection {
            setExpanded(row.rowID, expanded)
            return
        }
        for group in table.allGroups where group.rows.contains(where: { selection.contains($0.id) }) {
            setExpanded(group.id, expanded)
        }
    }

    /// The table's selected rows: `project:<id>`, or one `client:<id>` or
    /// `area:<id>`.
    var selectedRowIDs: Set<String> {
        if let row = clientsAndAreas.selection {
            return [row.rowID]
        }
        return Set(selection.map { "project:\($0.rawValue)" })
    }

    /// The table's selection changed: a client or area row is selected
    /// alone; a selection extended over such rows keeps only its projects.
    func selectRows(_ ids: Set<String>) {
        let projects = Set(ids.compactMap { id in id.hasPrefix("project:") ? ProjectID(String(id.dropFirst(8))) : nil })
        if projects.isEmpty, ids.count == 1, let id = ids.first, let row = ClientsAreasSelection(rowID: id) {
            clientsAndAreas.selection = row
        } else {
            clientsAndAreas.selection = nil
            selection = projects
        }
    }

    /// ⌘F.
    func focusSearch() {
        searchFocusRequests += 1
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
        let alone = ProjectTable(rows: [row], clients: clients, areas: areas, options: options, search: "", now: clock.now)
        if !alone.rows.contains(where: { $0.id == id }) {
            options.clearFilters()
        }
        self.options = options
        for group in table.allGroups where isCollapsed(group.id) && group.allRows.contains(where: { $0.id == id }) {
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
