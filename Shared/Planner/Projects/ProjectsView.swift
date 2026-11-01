// ProjectsView: the Projects section's toolbar, table, and status row
// (spec_planner_projects.md §2).

import SwiftUI
import TimeTrackingCore

/// The section: the toolbar, table, and status row, with the project,
/// client, and area sheets, the confirmations, and Merge Into.
struct ProjectsView: View {
    @Bindable var model: ProjectsModel
    var now: Date

    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ProjectsTableView(model: model, now: now)
            .navigationTitle("Projects")
            .navigationSubtitle(model.range.label)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
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
            .modifier(ClientAreaSheets(model: model.clientsAndAreas))
    }
}

/// The client and area sheets and the Delete and Remove confirmations.
private struct ClientAreaSheets: ViewModifier {
    @Bindable var model: ClientsAreasModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.clientForm) { form in
                ClientFormView(model: form) { client, _ in
                    Task { await model.sheetFinished(created: client.map { .client($0.id) }) }
                }
            }
            .sheet(item: $model.areaForm) { form in
                AreaFormView(model: form) { area in
                    Task { await model.sheetFinished(created: area.map { .area($0.id) }) }
                }
            }
            .alert(
                model.confirmation?.title ?? "",
                isPresented: .isPresent($model.confirmation),
                presenting: model.confirmation
            ) { confirmation in
                Button(confirmation.confirmTitle, role: .destructive) { Task { await model.confirm() } }
                    .accessibilityIdentifier("clientsAreas.confirm")
                Button("Cancel", role: .cancel) { model.confirmation = nil }
            } message: { confirmation in
                Text(confirmation.message)
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

    /// The bar below the table: "+" (New Project…, New Area…, New
    /// Client…), the status, the selection count, and Group by.
    private var statusRow: some View {
        HStack(spacing: Design.Spacing.medium) {
            newMenu
            Text(model.table.statusText).accessibilityIdentifier("projects.status")
            Spacer()
            if let selected = model.selectionText {
                Text(selected)
            }
            Picker("Group by", selection: $model.options.grouping) {
                ForEach(ProjectGrouping.allCases, id: \.self) { grouping in
                    Text(grouping.title).tag(grouping)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("projects.groupBy")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Design.Spacing.content)
        .padding(.vertical, Design.Spacing.small)
    }

    /// A click is New Project…; the menu adds New Area… and New Client….
    private var newMenu: some View {
        Menu {
            Button("New Project…") { model.newProject() }
            Button("New Area…") { Task { await model.clientsAndAreas.newArea(in: model.clientForNewArea) } }
            Button("New Client…") { Task { await model.clientsAndAreas.newClient() } }
        } label: {
            Label("New Project", systemImage: SymbolName.add)
        } primaryAction: {
            model.newProject()
        }
        .labelStyle(.iconOnly)
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("New Project")
        .accessibilityIdentifier("projects.new")
    }

    private func emptyState(_ text: String) -> some View {
        ContentUnavailableView {
            Label(text, systemImage: SymbolName.projects)
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

/// Leading the period items; trailing Filters (on iOS also Sort, for want
/// of column headers), then the search field, as in Reports
/// (spec_design.md §4). New and Group by are in the bar below the table.
private struct ProjectsToolbar: ToolbarContent {
    @Bindable var model: ProjectsModel
    @State private var showsFilters = false

    var body: some ToolbarContent {
        DateRangeToolbar(range: model.range, showsPopover: $model.showsDatePopover) {
            Task { await model.reload() }
        }
        ToolbarItem(placement: .primaryAction) {
            PlannerFiltersButton(activeFilters: model.options.filterCount, isPresented: $showsFilters, identifier: "projects.filters") {
                ProjectsFiltersPopover(model: model)
            }
        }
        .visibilityPriority(.high)
        #if os(iOS)
            // Without column headers, a menu sorts (spec_ios.md §10).
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort By", selection: sortKey) {
                        ForEach(ProjectSortKey.allCases, id: \.self) { key in
                            Text(key.title).tag(key)
                        }
                    }
                    .pickerStyle(.inline)
                    Picker("Order", selection: $model.options.ascending) {
                        Text("Ascending").tag(true)
                        Text("Descending").tag(false)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: SymbolName.sort)
                }
                .accessibilityIdentifier("projects.sortBy")
            }
        #endif
    }

    #if os(iOS)
        /// Choosing another key sorts ascending by it, like a header click.
        private var sortKey: Binding<ProjectSortKey> {
            Binding {
                model.options.sort
            } set: { key in
                if key != model.options.sort {
                    model.options.sort(by: key)
                }
            }
        }
    #endif
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
        VStack(alignment: .leading, spacing: Design.Spacing.small) {
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
        .padding(Design.Spacing.medium)
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
