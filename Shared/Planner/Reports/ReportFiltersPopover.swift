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

/// Chips that wrap onto further lines (filters, the chart legend).
struct FlowChips: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > width, origin.x > 0 {
                origin = CGPoint(x: 0, y: origin.y + lineHeight + spacing)
                lineHeight = 0
            }
            origin.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: origin.y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var origin = bounds.origin
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX, origin.x > bounds.minX {
                origin = CGPoint(x: bounds.minX, y: origin.y + lineHeight + spacing)
                lineHeight = 0
            }
            subview.place(at: origin, proposal: ProposedViewSize(size))
            origin.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
