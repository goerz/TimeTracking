// The Reports Filters button, its chips, and its popover
// (spec_planner_reports.md §3).

import SwiftUI
import TimeTrackingCore

/// Filters with badge, then one removable chip per active kind.
struct ReportFiltersButton: View {
    @Bindable var model: ReportsModel

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.showsFilters.toggle()
            } label: {
                let count = model.state.filters.activeKindCount
                Label(count > 0 ? "Filters (\(count))" : "Filters", systemImage: "line.3.horizontal.decrease")
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityIdentifier("reports.filters")
            .popover(isPresented: $model.showsFilters) {
                ReportFiltersPopover(model: model)
            }
            ForEach(model.filterChips) { chip in
                Button {
                    Task { await model.removeChip(chip.kind) }
                } label: {
                    Text("\(chip.text) ×")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reports.chip")
            }
        }
    }
}

/// Client and Area chips, the Project list, the Task field, and the archive switch.
struct ReportFiltersPopover: View {
    @Bindable var model: ReportsModel

    @State private var projectSearch = ""
    @State private var task = ""
    @FocusState private var taskFocused: Bool

    private var filters: ReportFilters {
        model.state.filters
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            clientSection
            areaSection
            projectSection
            section("Task") {
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
        .padding(14)
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

    private var clientSection: some View {
        section("Client") {
            FlowChips {
                ForEach(model.clients) { client in
                    chip(client.name, isOn: filters.clients.contains(client.id)) { filters in
                        filters.clients.formSymmetricDifference([client.id])
                    }
                }
                chip("No client", isOn: filters.noClient) { filters in filters.noClient.toggle() }
            }
        }
    }

    private var areaSection: some View {
        section("Area") {
            FlowChips {
                ForEach(filters.visibleAreas(model.areas)) { area in
                    chip(area.name, color: area.color, isOn: filters.areas.contains(area.id)) { filters in
                        filters.areas.formSymmetricDifference([area.id])
                    }
                }
                chip("No area", isOn: filters.noArea) { filters in filters.noArea.toggle() }
            }
        }
    }

    private var projectSection: some View {
        let visible = filters.visibleProjects(model.projects).filter { row in
            projectSearch.isEmpty || row.project.name.folded.contains(projectSearch.folded)
        }
        let archived = visible.filter(\.project.isArchived)
        return section("Project") {
            TextField("Search projects", text: $projectSearch).textFieldStyle(.roundedBorder)
            List {
                projectToggle("(no project)", isOn: filters.noProject) { filters in filters.noProject.toggle() }
                ForEach(visible.filter { !$0.project.isArchived }) { row in
                    projectToggle(row)
                }
                if !archived.isEmpty {
                    Section("Archived") {
                        ForEach(archived) { row in
                            projectToggle(row)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
    }

    private func projectToggle(_ row: ProjectRow) -> some View {
        projectToggle(row.project.name, color: row.color, isOn: filters.projects.contains(row.id)) { filters in
            filters.projects.formSymmetricDifference([row.id])
        }
    }

    private func update(_ change: (inout ReportFilters) -> Void) {
        var filters = filters
        change(&filters)
        Task { await model.setFilters(filters) }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func chip(_ title: String, color: String? = nil, isOn: Bool, change: @escaping (inout ReportFilters) -> Void) -> some View {
        Button {
            update(change)
        } label: {
            HStack(spacing: 4) {
                if let color {
                    AreaSwatch(color: color)
                }
                Text(title)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func projectToggle(
        _ title: String,
        color: String? = nil,
        isOn: Bool,
        change: @escaping (inout ReportFilters) -> Void
    ) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in update(change) })) {
            HStack(spacing: 6) {
                if let color {
                    AreaDot(color: color)
                }
                Text(title)
            }
        }
    }
}

/// Chips that wrap onto further lines.
private struct FlowChips: Layout {
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
