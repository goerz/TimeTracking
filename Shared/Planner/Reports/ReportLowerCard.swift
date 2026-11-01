// ReportLowerCard: the segmented control, the level chain, and the
// breakdown table or the entry list (spec_planner_reports.md §5, §6).

import SwiftUI
import TimeTrackingCore

/// Breakdown | Entries with their headers.
struct ReportLowerCard: View {
    @Bindable var model: ReportsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(Design.Spacing.medium)
            Divider()
            if (model.snapshot?.summary.entryCount ?? 0) == 0 {
                ContentUnavailableView("No entries in this range", systemImage: SymbolName.reports)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("reports.empty")
            } else if model.state.card == .breakdown {
                ReportBreakdownTable(model: model)
            } else {
                ReportEntryList(model: model)
            }
        }
        #if os(macOS)
        .onCopyCommand {
            // ⌘C on the selected table or list rows (spec_planner_reports.md §7).
            let text = model.copySelectedRows()
            // NSItemProvider writes plain text from an NSString only.
            // swiftlint:disable:next legacy_objc_type
            return text.isEmpty ? [] : [NSItemProvider(object: text as NSString)]
        }
        #endif
        .frame(maxHeight: .infinity)
        .cardBackground()
        .clipShape(.rect(cornerRadius: Design.Radius.card))
    }

    private var header: some View {
        HStack(spacing: Design.Spacing.small) {
            Picker("", selection: Binding(get: { model.state.card }, set: { card in
                Task { await model.show(card) }
            })) {
                Text("Breakdown").tag(ReportCard.breakdown)
                Text("Entries").tag(ReportCard.entries)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("reports.card")
            if model.state.card == .breakdown {
                levelChain
                Spacer()
                expandButton
            } else {
                pathChip
                Spacer()
            }
            exportButton
        }
    }

    /// The card shown as CSV (Breakdown or Entries).
    private var exportButton: some View {
        Button {
            model.requestExport()
        } label: {
            Label("Export…", systemImage: SymbolName.share)
        }
        .labelStyle(.iconOnly)
        .help(model.state.card == .breakdown ? "Export Breakdown (CSV)" : "Export Entries (CSV)")
        .disabled((model.snapshot?.summary.entryCount ?? 0) == 0)
        .accessibilityIdentifier("reports.export")
    }

    private var expandButton: some View {
        Button(model.anyCollapsed ? "Expand All" : "Collapse All") {
            if model.anyCollapsed {
                model.expandAll()
            } else {
                model.collapseAll()
            }
        }
        .accessibilityIdentifier("reports.expandAll")
    }

    @ViewBuilder private var pathChip: some View {
        if let chip = model.pathChipText {
            Button {
                Task { await model.clearEntryPath() }
            } label: {
                Label("\(chip) ×", systemImage: SymbolName.filter)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("reports.pathChip")
        }
    }

    private var levelChain: some View {
        HStack(spacing: Design.Spacing.tight) {
            ForEach(model.state.levels.indices, id: \.self) { index in
                if index > 0 {
                    Text("›").foregroundStyle(.secondary)
                }
                Menu(model.state.levels[index].title) {
                    ForEach(GroupKey.allCases, id: \.self) { kind in
                        Button(kind.title) { Task { await model.setLevel(index, to: kind) } }
                            .disabled(!model.availableKinds(at: index).contains(kind) || model.state.levels[index] == kind)
                    }
                    if index > 0 {
                        Divider()
                        Button("Remove Level") { Task { await model.removeLevel(index) } }
                    }
                }
                .fixedSize()
                .accessibilityIdentifier("reports.level.\(index)")
            }
            if model.canAddLevel {
                Text("›").foregroundStyle(.secondary)
                Button {
                    Task { await model.addLevel() }
                } label: {
                    Image(systemName: SymbolName.add).accessibilityLabel("Add Level")
                }
                .accessibilityIdentifier("reports.addLevel")
            }
        }
    }
}

extension GroupKey {
    var title: String {
        switch self {
        case .client: "Client"
        case .area: "Area"
        case .project: "Project"
        case .task: "Task"
        case .day: "Day"
        }
    }
}

/// The breakdown: Name, Logged time, Share, Entries, Bar, with a pinned Total.
struct ReportBreakdownTable: View {
    @Bindable var model: ReportsModel

    var body: some View {
        let total = model.snapshot?.tree
        VStack(spacing: 0) {
            columnHeader
            List(selection: $model.tableSelection) {
                ForEach(model.breakdownRows) { row in
                    rowView(row, total: total?.seconds ?? 0).tag(row.path)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: [GroupKeyValue].self) { _ in
                EmptyView()
            } primaryAction: { paths in
                if let path = paths.first {
                    Task { await model.openNode(path) }
                }
            }
            .onKeyPress(keys: [.rightArrow, .leftArrow, .space, .return]) { press in
                handle(press)
            }
            .accessibilityIdentifier("reports.breakdown")
            Divider()
            if let total {
                footer(total)
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: Design.Spacing.medium) {
            sortButton("Name", .name).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            sortButton("Logged time", .loggedTime).frame(width: 120, alignment: .trailing)
            sortButton("Share", .share).frame(width: 70, alignment: .trailing)
            sortButton("Entries", .entries).frame(width: 70, alignment: .trailing)
            Text("").frame(minWidth: 40, maxWidth: 160)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Design.Spacing.large)
        .padding(.vertical, Design.Spacing.compact)
    }

    private func sortButton(_ title: String, _ column: ReportColumn) -> some View {
        Button {
            model.sortTable(by: column)
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if model.state.tableSort == column {
                    Image(systemName: model.state.tableAscending ? SymbolName.ascending : SymbolName.expanded).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func rowView(_ row: BreakdownRow, total: Int) -> some View {
        HStack(spacing: Design.Spacing.medium) {
            nameCell(row)
                .padding(.leading, CGFloat(row.depth) * 20)
                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            Text(ReportText.seconds(row.node.seconds, padded: true)).monospacedDigit().frame(width: 120, alignment: .trailing)
            Text(ReportText.share(row.node.seconds, of: total)).monospacedDigit().frame(width: 70, alignment: .trailing)
            Text(String(row.node.entryCount)).monospacedDigit().frame(width: 70, alignment: .trailing)
            GeometryReader { geometry in
                Capsule()
                    .fill(barColor(row).flatMap(\.self).map { Color(hex: $0) } ?? fallbackBarColor(row))
                    .frame(width: max(2, geometry.size.width * ReportText.fraction(row.node.seconds, of: total)), height: 8)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(minWidth: 40, maxWidth: 160)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reports.node")
    }

    /// Triangle, dot, name, and the number of direct children.
    private func nameCell(_ row: BreakdownRow) -> some View {
        HStack(spacing: Design.Spacing.compact) {
            Group {
                if row.hasChildren {
                    Button {
                        if ModifierState.optionDown() {
                            model.setSubtreeExpanded(row.path, !row.isExpanded)
                        } else {
                            model.toggle(row.path)
                        }
                    } label: {
                        Image(systemName: row.isExpanded ? SymbolName.expanded : SymbolName.next)
                            .font(.caption)
                            .accessibilityLabel(row.isExpanded ? "Collapse" : "Expand")
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                }
            }
            .frame(width: 14)
            if row.level == .area || row.level == .project {
                AreaDot(color: barColor(row).flatMap(\.self))
            }
            Text(row.title).lineLimit(1)
            if row.hasChildren {
                Text("(\(row.node.children.count))").foregroundStyle(.secondary)
            }
        }
    }

    /// "No area" and "No project" in the chart's gray; other levels in the accent color.
    private func fallbackBarColor(_ row: BreakdownRow) -> Color {
        row.level == .area || row.level == .project ? StackColor.gray.color : .accentColor
    }

    /// Area color for area nodes; the lightness step for project nodes.
    private func barColor(_ row: BreakdownRow) -> String?? {
        guard row.level == .area || row.level == .project, let hex = row.node.color else {
            return .some(nil)
        }
        if row.level == .project, case let .project(id?) = row.node.key, let step = model.snapshot?.projectSteps[id],
           let color = try? AreaColor(hex)
        {
            return color.lightnessStep(step).hex
        }
        return hex
    }

    private func footer(_ total: ReportNode) -> some View {
        HStack(spacing: Design.Spacing.medium) {
            Text("Total").fontWeight(.semibold).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            Text(ReportText.seconds(total.seconds, padded: true)).fontWeight(.semibold).monospacedDigit()
                .frame(width: 120, alignment: .trailing)
                .accessibilityIdentifier("reports.total")
            Text("100%").fontWeight(.semibold).frame(width: 70, alignment: .trailing)
            Text(String(total.entryCount)).fontWeight(.semibold).frame(width: 70, alignment: .trailing)
            Text("").frame(minWidth: 40, maxWidth: 160)
        }
        .padding(.horizontal, Design.Spacing.large)
        .padding(.vertical, Design.Spacing.small)
    }

    /// → expands, ← collapses, ⌥→ the subtree, Space toggles, ↩ opens the entries.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard let path = model.tableSelection.first else {
            return .ignored
        }
        switch press.key {
        case .rightArrow:
            if press.modifiers.contains(.option) {
                model.setSubtreeExpanded(path, true)
            } else if !(model.breakdownRows.first { $0.path == path }?.isExpanded ?? true) {
                model.toggle(path)
            }
        case .leftArrow:
            if model.breakdownRows.first(where: { $0.path == path })?.isExpanded == true {
                model.toggle(path)
            }
        case .space:
            model.toggle(path)
        default:
            Task { await model.openNode(path) }
        }
        return .handled
    }
}
