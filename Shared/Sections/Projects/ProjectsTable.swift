// ProjectsTable: the projects `Table` with client, area, and group rows,
// column customization, and the hover ⋯ button (projects.md
// §2.1 to §2.5, §4).

import SwiftUI
import TimeTrackingCore

/// A table line: a client, area, or group row, or a project. The ids are
/// the selection's row ids (`client:<id>`, `area:<id>`, `project:<id>`).
enum ProjectTableItem: Identifiable, Hashable {
    case group(ProjectTableGroup)
    case project(ProjectTableRow)

    var id: String {
        switch self {
        case let .group(group): group.id
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

/// The table; client, area, and group rows collapse with their triangles.
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
        Table(
            of: ProjectTableItem.self,
            selection: selection,
            sortOrder: ProjectColumnSort.sortOrder($model.options),
            columnCustomization: columns
        ) {
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
            guard !model.selection.isEmpty else {
                return
            }
            Task {
                if model.canArchive {
                    await model.archiveSelection()
                } else {
                    await model.restoreSelection()
                }
            }
        }
        .onCopyCommand {
            // Edit › Copy (⌘C): the selected names, as Copy Name.
            let text = model.copySelectionNames()
            // NSItemProvider writes plain text from an NSString only.
            // swiftlint:disable:next legacy_objc_type
            return text.isEmpty ? [] : [NSItemProvider(object: text as NSString)]
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
                    // Client and Area: the client's areas, each with its projects.
                    ForEach(group.subgroups) { area in
                        DisclosureTableRow(ProjectTableItem.group(area), isExpanded: expansion(area.id)) {
                            ForEach(area.rows) { row in
                                TableRow(ProjectTableItem.project(row))
                            }
                        }
                    }
                    ForEach(group.rows) { row in
                        TableRow(ProjectTableItem.project(row))
                    }
                }
            }
        }
    }

    // MARK: Columns

    private typealias Sort = ProjectColumnSort

    // A narrow iPad gives each column little more than its minimum, and the
    // rows' indents come out of that.
    #if os(macOS)
        private static let nameColumnMinimum: CGFloat = 160
        private static let placeColumnMinimum: CGFloat? = nil
        private static let lastTrackedColumnMinimum: CGFloat? = nil
        private static let totalColumnMinimum: CGFloat? = nil
    #else
        private static let nameColumnMinimum: CGFloat = 215
        private static let placeColumnMinimum: CGFloat? = 92
        private static let lastTrackedColumnMinimum: CGFloat? = 100
        private static let totalColumnMinimum: CGFloat? = 104
    #endif

    @TableColumnBuilder<ProjectTableItem, Sort> private var nameColumns: some TableColumnContent<ProjectTableItem, Sort> {
        TableColumn("Project", sortUsing: Sort(key: .name)) { item in
            ProjectNameCell(model: model, item: item)
        }
        .width(min: Self.nameColumnMinimum, ideal: 280)
        .customizationID("project")
        .disabledCustomizationBehavior(.visibility)
        TableColumn("Client", sortUsing: Sort(key: .client)) { item in
            Text(item.row?.clientText ?? "")
        }
        .width(min: Self.placeColumnMinimum, ideal: 140)
        .customizationID("client")
        TableColumn("Area", sortUsing: Sort(key: .area)) { item in
            if let row = item.row {
                Text(row.areaIsGeneral ? row.row.client?.name ?? "" : row.areaText)
                    .foregroundStyle(row.areaIsGeneral || row.isOrphan ? .secondary : .primary)
            }
        }
        .width(min: Self.placeColumnMinimum, ideal: 140)
        .customizationID("area")
        TableColumn("State") { item in
            Text(item.row.map { $0.row.project.isArchived ? "Archived" : "Active" } ?? "")
        }
        .width(ideal: 90)
        .customizationID("state")
        .defaultVisibility(model.showsStateColumn ? .visible : .hidden)
    }

    @TableColumnBuilder<ProjectTableItem, Sort> private var dateColumns: some TableColumnContent<ProjectTableItem, Sort> {
        TableColumn("Created", sortUsing: Sort(key: .created)) { item in
            if let row = item.row {
                dateText(row.row.project.createdAt)
            }
        }
        .width(ideal: 100)
        .customizationID("created")
        TableColumn("Last tracked", sortUsing: Sort(key: .lastTracked)) { item in
            if let row = item.row {
                dateText(row.row.lastUsed)
            }
        }
        .width(min: Self.lastTrackedColumnMinimum, ideal: 120)
        .customizationID("lastTracked")
        TableColumn("Total tracked", sortUsing: Sort(key: .totalTracked)) { item in
            totalCell(item)
        }
        .width(min: Self.totalColumnMinimum, ideal: 120)
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
            model.selectedRowIDs
        } set: { ids in
            model.selectRows(ids)
        }
    }

    private func expansion(_ group: String) -> Binding<Bool> {
        Binding {
            !model.isCollapsed(group)
        } set: { open in
            model.setExpanded(group, open)
        }
    }

    /// A client or area row's own commands; a project's (or the selection's).
    @ViewBuilder
    private func menu(for ids: Set<String>) -> some View {
        if ids.count == 1, let id = ids.first, let row = ClientsAreasSelection(rowID: id) {
            ClientAreaContextMenu(model: model, row: row)
        } else if ids.contains(where: { $0.hasPrefix("project:") }) {
            ProjectContextMenu(model: model)
        }
    }

    @ViewBuilder
    private func totalCell(_ item: ProjectTableItem) -> some View {
        switch item {
        case let .group(group):
            Text(ActivityText.duration(group.totalSeconds))
                .fontWeight(group.isArea ? .regular : .semibold)
                .monospacedDigit()
        case let .project(row):
            Text(ActivityText.duration(row.row.totalSeconds)).monospacedDigit()
        }
    }

    private func dateText(_ date: Date?) -> some View {
        Text(ProjectTable.dateText(date, now: now, calendar: model.range.calendar))
            .help(date.map { $0.formatted(date: .complete, time: .shortened) } ?? "")
    }
}

/// The Project cell: dot and name (or the rename field), ⚠ for a duplicate
/// name, the ⋯ button on the hovered row; a client or group row shows its
/// title, an area row its swatch, name, and tag.
private struct ProjectNameCell: View {
    var model: ProjectsModel
    var item: ProjectTableItem

    @State private var renameText = ""
    @State private var hovering = false

    /// The Mac keeps the ⋯ button's space, so a row doesn't shift on hover.
    /// Without a pointer the button never shows, and a name needs that space.
    private var showsMoreButton: Bool {
        #if os(macOS)
            true
        #else
            hovering
        #endif
    }

    var body: some View {
        switch item {
        case let .group(group):
            if group.isArea {
                HStack(spacing: Design.Spacing.compact) {
                    if let color = group.color {
                        AreaSwatch(color: color)
                    }
                    Text(group.title).foregroundStyle(group.tag == "retired" ? .secondary : .primary)
                    if let tag = group.tag {
                        Text(tag).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("projects.area")
            } else {
                Text(group.title).fontWeight(.semibold)
                    .accessibilityIdentifier(group.clientID == nil ? "projects.group" : "projects.client")
            }
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
                Image(systemName: SymbolName.warning)
                    .foregroundStyle(.yellow)
                    .help(tooltip)
                    .accessibilityLabel(tooltip)
            }
            Spacer(minLength: 4)
            if showsMoreButton {
                Menu {
                    ProjectContextMenu(model: model)
                } label: {
                    Image(systemName: SymbolName.more).accessibilityLabel("Actions")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity(hovering ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityIdentifier("projects.row")
    }
}
