// ProjectsView: the Projects section's toolbar, table, and status row
// (spec_planner_projects.md §2; mockups/planner_projects.png).

import SwiftUI
import TimeTrackingCore

/// The section: the table, or Clients & Areas in its place.
struct ProjectsView: View {
    @Bindable var model: ProjectsModel
    var now: Date

    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            #if os(iOS)
                // The iPad pushes Clients & Areas (spec_planner_projects.md §1.4).
                ProjectsTableView(model: model, now: now)
                    .navigationDestination(isPresented: $model.showsClientsAndAreas) {
                        ClientsAreasView(model: model.clientsAndAreas, projects: model)
                            .navigationTitle("Clients & Areas")
                    }
            #else
                if model.showsClientsAndAreas {
                    ClientsAreasView(model: model.clientsAndAreas, projects: model)
                } else {
                    ProjectsTableView(model: model, now: now)
                }
            #endif
        }
        .navigationTitle("Projects")
        .onChange(of: now) {
            // Total tracked counts the running entry to now, once a minute.
            Task { await model.reload() }
        }
        .task {
            model.undoManager = undoManager
            model.clientsAndAreas.undoManager = undoManager
            await model.reload()
        }
        .sheet(item: $model.dialog) { dialog in
            ProjectDialogView(model: dialog, preferredArea: model.dialogDefaultArea) { project in
                Task { await model.dialogFinished(project) }
            }
        }
        .alert(
            model.confirmation?.title ?? "",
            isPresented: .isPresent($model.confirmation),
            presenting: model.confirmation
        ) { confirmation in
            Button(confirmation.confirmTitle, role: .destructive) { Task { await model.confirm() } }
                .accessibilityIdentifier("projects.confirm")
            Button("Cancel", role: .cancel) { model.confirmation = nil }
        } message: { confirmation in
            Text(confirmation.message)
        }
        .popover(isPresented: .isPresent($model.mergeSource)) {
            ProjectsMergePicker(model: model)
        }
    }
}

/// The toolbar, the table, and the status row.
private struct ProjectsTableView: View {
    @Bindable var model: ProjectsModel
    var now: Date

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let empty = model.table.emptyText {
                emptyState(empty)
            } else {
                ProjectsTable(model: model, now: now)
            }
            Divider()
            statusRow
        }
        .toolbar { ProjectsToolbar(model: model) }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search")
        .searchFocused($searchFocused)
        .onChange(of: model.searchFocusRequests) { searchFocused = true }
        .onKeyPress(.escape) {
            guard !model.search.isEmpty else {
                return .ignored
            }
            model.search = ""
            return .handled
        }
    }

    private var statusRow: some View {
        HStack {
            Text(model.table.statusText).accessibilityIdentifier("projects.status")
            Spacer()
            if let selected = model.selectionText {
                Text(selected)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func emptyState(_ text: String) -> some View {
        ContentUnavailableView {
            Text(text)
        } actions: {
            if model.table.activeCount + model.table.archivedCount == 0 {
                Button("New Project") { model.newProject() }
            } else {
                Button("Clear Filters") {
                    model.options.clearFilters()
                    model.search = ""
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("projects.empty")
    }
}

/// State selector, Filters, Group by, Sort by; Clients & Areas, New Project.
private struct ProjectsToolbar: ToolbarContent {
    @Bindable var model: ProjectsModel
    @State private var showsFilters = false

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Picker("State", selection: $model.options.state) {
                ForEach(ProjectFilter.State.allCases, id: \.self) { state in
                    Text(state.title).tag(state)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("projects.state")
            Button {
                showsFilters.toggle()
            } label: {
                let count = model.options.filterCount
                Label(count > 0 ? "Filters (\(count))" : "Filters", systemImage: "line.3.horizontal.decrease").labelStyle(.titleAndIcon)
            }
            .popover(isPresented: $showsFilters) {
                ProjectsFiltersPopover(model: model)
            }
            .accessibilityIdentifier("projects.filters")
            Picker("Group by", selection: $model.options.grouping) {
                ForEach(ProjectGrouping.allCases, id: \.self) { grouping in
                    Text("Group by: \(grouping.title)").tag(grouping)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("projects.groupBy")
            Menu("Sort by: \(model.options.sort.title)") {
                ForEach(ProjectSortKey.allCases, id: \.self) { key in
                    Button(key.title + sortMark(key)) { model.options.sort(by: key) }
                }
            }
            .accessibilityIdentifier("projects.sortBy")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Clients & Areas") { model.showClientsAndAreas(client: nil) }
                .accessibilityIdentifier("projects.clientsAndAreas")
            Button {
                model.newProject()
            } label: {
                Label("New Project", systemImage: "plus").labelStyle(.titleAndIcon)
            }
            .accessibilityIdentifier("projects.new")
        }
    }

    private func sortMark(_ key: ProjectSortKey) -> String {
        guard model.options.sort == key else {
            return ""
        }
        return model.options.ascending ? " ↑" : " ↓"
    }
}

/// The Project menu's commands for the selection (context menu, ⋯).
struct ProjectContextMenu: View {
    var model: ProjectsModel

    var body: some View {
        Button("Start Timer") { Task { await model.startTimerOnSelection() } }
            .disabled(!model.canStartTimer)
        Button("Edit…") { model.editSelection() }
            .disabled(model.single == nil)
        Button("Rename") { model.renaming = model.single?.id }
            .disabled(model.single == nil)
        Divider()
        if model.canArchive {
            Button("Archive") { Task { await model.archiveSelection() } }
        }
        if model.canRestore {
            Button("Restore") { Task { await model.restoreSelection() } }
        }
        Button("Merge Into…") { model.mergeSource = model.single?.id }
            .disabled(model.single == nil)
        Button("Delete…") { model.requestDelete() }
            .disabled(!model.canDelete)
            .help(model.deleteTooltip ?? "")
        Divider()
        Button("Show in Reports") { Task { await model.showInReports() } }
            .disabled(model.single == nil)
        Button("Copy Name") { model.router?.copyText(model.copyNames()) }
            .disabled(model.selection.isEmpty)
    }
}

/// Merge Into…: a picker of all other projects, any state, any client.
private struct ProjectsMergePicker: View {
    var model: ProjectsModel
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Merge Into").font(.headline)
            TextField("Search projects", text: $search).textFieldStyle(.roundedBorder)
            List(candidates) { row in
                Button {
                    model.requestMerge(into: row.id)
                } label: {
                    HStack {
                        AreaDot(color: row.color)
                        Text(row.project.name)
                        Spacer()
                        Text(row.client?.name ?? "").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(height: 300)
        }
        .padding(12)
        .frame(width: 340)
    }

    private var candidates: [ProjectRow] {
        let words = search.folded.split(separator: " ").map(String.init)
        return model.rows
            .filter { $0.id != model.mergeSource }
            .filter { row in
                words.allSatisfy { word in
                    [row.project.name, row.area?.name ?? "", row.client?.name ?? ""].contains { $0.folded.contains(word) }
                }
            }
            .sorted { $0.project.name.folded < $1.project.name.folded }
    }
}
