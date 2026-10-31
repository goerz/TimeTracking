// The Reports Filters button and its popover (spec_planner_reports.md §3).
// The active filters show in the filter bar above the tiles (ReportsView).

import SwiftUI
import TimeTrackingCore

/// The Filters toolbar button.
struct ReportFiltersButton: View {
    @Bindable var model: ReportsModel

    var body: some View {
        PlannerFiltersButton(
            activeFilters: model.state.filters.activeKindCount,
            isPresented: $model.showsFilters,
            identifier: "reports.filters"
        ) {
            ReportFiltersPopover(model: model)
        }
    }
}

/// The tree of clients, areas, and projects with "No project", the Task
/// field, the archive switch, and Clear All, laid out as the Projects
/// popover.
struct ReportFiltersPopover: View {
    @Bindable var model: ReportsModel

    @State private var task = ""
    @FocusState private var taskFocused: Bool

    private var filters: ReportFilters {
        model.state.filters
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.medium) {
            FilterSection("Clients, Areas, and Projects") {
                ProjectScopeTreeView(
                    tree: filters.tree(clients: model.clients, areas: model.areas, projects: model.projects),
                    scope: Binding(get: { filters.scope }, set: { scope in update { $0.scope = scope } }),
                    noProject: Binding(get: { filters.noProject }, set: { value in update { $0.noProject = value } }),
                    identifier: "reports.filter"
                )
            }
            FilterSection("Task") {
                TextField("Task contains", text: $task)
                    .textFieldStyle(.roundedBorder)
                    .focused($taskFocused)
                    .accessibilityIdentifier("reports.filter.task")
            }
            Toggle("Include archived projects", isOn: Binding(get: { filters.includeArchived }, set: { value in
                update { filters in filters.includeArchived = value }
            }))
            HStack {
                Spacer()
                Button("Clear All") {
                    task = ""
                    Task { await model.clearFilters() }
                }
            }
        }
        .padding(Design.Spacing.large)
        .frame(width: 360)
        .onAppear {
            task = filters.task
            if model.taskFocusRequests > 0 {
                taskFocused = true
            }
        }
        .onChange(of: model.taskFocusRequests) { taskFocused = true }
        .task(id: task) {
            // Applied 150 ms after the last keystroke.
            guard task != filters.task else {
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled {
                update { filters in filters.task = task }
            }
        }
    }

    private func update(_ change: (inout ReportFilters) -> Void) {
        var filters = filters
        change(&filters)
        Task { await model.setFilters(filters) }
    }
}
