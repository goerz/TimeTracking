// ProjectsTable: the projects `Table` with group header rows, column
// customization, and the hover ⋯ button (spec_planner_projects.md §2.1 to §2.3).

import SwiftUI
import TimeTrackingCore

/// A table line: a group header or a project.
enum ProjectTableItem: Identifiable, Hashable {
    case group(ProjectTableGroup)
    case project(ProjectTableRow)

    var id: String {
        switch self {
        case let .group(group): "group:\(group.id)"
        case let .project(row): "project:\(row.id.rawValue)"
        }
    }

    var row: ProjectTableRow? {
        if case let .project(row) = self {
            return row
        }
        return nil
    }
}

/// The table; group headers collapse with their triangles.
struct ProjectsTable: View {
    @Bindable var model: ProjectsModel
    var now: Date

    var body: some View {
        ScrollViewReader { proxy in
            table
                .onChange(of: model.scrollTarget) { _, target in
                    if let target {
                        proxy.scrollTo("project:\(target.rawValue)")
                    }
                }
                .accessibilityIdentifier("projects.table")
        }
    }

    private var table: some View {
        Table(of: ProjectTableItem.self, selection: selection, columnCustomization: columns) {
            nameColumns
            dateColumns
        } rows: {
            rows
        }
        .contextMenu(forSelectionType: String.self) { ids in
            menu(for: ids)
        } primaryAction: { _ in
            model.editSelection()
        }
        #if os(macOS)
        .onDeleteCommand {
            // ⌫: Archive on active rows, Restore on archived ones.
            Task {
                if model.canArchive {
                    await model.archiveSelection()
                } else {
                    await model.restoreSelection()
                }
            }
        }
        #endif
        .onKeyPress(keys: [.return, .leftArrow, .rightArrow]) { press in
            switch press.key {
            case .return: model.editSelection()
            case .leftArrow: model.setSelectionGroupExpanded(false)
            default: model.setSelectionGroupExpanded(true)
            }
            return .handled
        }
    }

    // MARK: Rows

    @TableRowBuilder<ProjectTableItem> private var rows: some TableRowContent<ProjectTableItem> {
        ForEach(model.table.groups) { group in
            if model.options.grouping == .ungrouped {
                ForEach(group.rows) { row in
                    TableRow(ProjectTableItem.project(row))
                }
            } else {
                DisclosureTableRow(ProjectTableItem.group(group), isExpanded: expansion(group.id)) {
                    ForEach(group.rows) { row in
                        TableRow(ProjectTableItem.project(row))
                    }
                }
            }
        }
    }

    // MARK: Columns

    @TableColumnBuilder<ProjectTableItem, Never> private var nameColumns: some TableColumnContent<ProjectTableItem, Never> {
        TableColumn("Project") { item in
            ProjectNameCell(model: model, item: item)
        }
        .width(min: 160, ideal: 280)
        .customizationID("project")
        .disabledCustomizationBehavior(.visibility)
        TableColumn("Client") { item in
            Text(item.row?.clientText ?? "")
        }
        .width(ideal: 140)
        .customizationID("client")
        TableColumn("Area") { item in
            if let row = item.row {
                Text(row.areaIsGeneral ? row.row.client?.name ?? "" : row.areaText)
                    .foregroundStyle(row.areaIsGeneral || row.isOrphan ? .secondary : .primary)
            }
        }
        .width(ideal: 140)
        .customizationID("area")
        TableColumn("State") { item in
            Text(item.row.map { $0.row.project.isArchived ? "Archived" : "Active" } ?? "")
        }
        .width(ideal: 90)
        .customizationID("state")
        .defaultVisibility(model.showsStateColumn ? .visible : .hidden)
    }

    @TableColumnBuilder<ProjectTableItem, Never> private var dateColumns: some TableColumnContent<ProjectTableItem, Never> {
        TableColumn("Created") { item in
            if let row = item.row {
                dateText(row.row.project.createdAt)
            }
        }
        .width(ideal: 100)
        .customizationID("created")
        TableColumn("Last tracked") { item in
            if let row = item.row {
                dateText(row.row.lastUsed)
            }
        }
        .width(ideal: 120)
        .customizationID("lastTracked")
        TableColumn("Total tracked") { item in
            totalCell(item)
        }
        .width(ideal: 120)
        .alignment(.trailing)
        .customizationID("totalTracked")
    }

    // MARK: Cells and bindings

    private var columns: Binding<TableColumnCustomization<ProjectTableItem>> {
        Binding {
            (try? JSONDecoder().decode(TableColumnCustomization<ProjectTableItem>.self, from: model.columnData)) ?? .init()
        } set: { customization in
            model.columnData = (try? JSONEncoder().encode(customization)) ?? Data()
        }
    }

    private var selection: Binding<Set<String>> {
        Binding {
            Set(model.selection.map { "project:\($0.rawValue)" })
        } set: { ids in
            model.selection = Set(ids.compactMap { id in
                id.hasPrefix("project:") ? ProjectID(String(id.dropFirst(8))) : nil
            })
        }
    }

    private func expansion(_ group: String) -> Binding<Bool> {
        Binding {
            !model.isCollapsed(group)
        } set: { open in
            model.setExpanded(group, open)
        }
    }

    @ViewBuilder
    private func menu(for ids: Set<String>) -> some View {
        if let id = ids.first, id.hasPrefix("group:"), let group = model.table.groups.first(where: { id == "group:\($0.id)" }) {
            if let client = group.clientID {
                Button("Edit Client…") {
                    model.showClientsAndAreas(client: client)
                    model.clientsAndAreas.renameClient(client)
                }
            }
            if let area = group.areaID {
                Button("Edit Area…") {
                    model.showClientsAndAreas(client: group.clientID)
                    model.clientsAndAreas.editArea(area)
                }
            }
        } else {
            ProjectContextMenu(model: model)
        }
    }

    @ViewBuilder
    private func totalCell(_ item: ProjectTableItem) -> some View {
        switch item {
        case let .group(group):
            Text(ActivityText.duration(group.totalSeconds)).fontWeight(.semibold).monospacedDigit()
        case let .project(row):
            Text(ActivityText.duration(row.row.totalSeconds)).monospacedDigit()
        }
    }

    private func dateText(_ date: Date?) -> some View {
        Text(ProjectTable.dateText(date, now: now, calendar: TrackingCalendar(timeZone: .current)))
            .help(date.map { $0.formatted(date: .complete, time: .shortened) } ?? "")
    }
}

/// The Project cell: dot and name (or the rename field), ⚠ for a duplicate
/// name, the ⋯ button on the selected row; group headers show their title.
private struct ProjectNameCell: View {
    var model: ProjectsModel
    var item: ProjectTableItem

    @State private var renameText = ""
    @State private var hovering = false

    var body: some View {
        switch item {
        case let .group(group):
            HStack(spacing: Design.Spacing.compact) {
                if let color = group.color {
                    AreaSwatch(color: color)
                }
                Text(group.title).fontWeight(.semibold)
            }
            .accessibilityIdentifier("projects.group")
        case let .project(row):
            if model.renaming == row.id {
                TextField("Name", text: $renameText)
                    .onSubmit { Task { await model.rename(row.id, to: renameText) } }
                    .onKeyPress(.escape) {
                        model.renaming = nil
                        return .handled
                    }
                    .onAppear { renameText = row.row.project.name }
                    .accessibilityIdentifier("projects.rename")
            } else {
                projectLabel(row)
            }
        }
    }

    private func projectLabel(_ row: ProjectTableRow) -> some View {
        HStack(spacing: Design.Spacing.small) {
            AreaDot(color: row.row.color).opacity(row.row.project.isArchived ? 0.5 : 1)
            Text(row.row.project.name)
                .foregroundStyle(row.row.project.isArchived ? .secondary : .primary)
            if let tooltip = row.duplicateTooltip {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
                    .help(tooltip)
                    .accessibilityLabel(tooltip)
            }
            Spacer(minLength: 4)
            Menu {
                ProjectContextMenu(model: model)
            } label: {
                Image(systemName: "ellipsis").accessibilityLabel("Actions")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityIdentifier("projects.row")
    }
}
