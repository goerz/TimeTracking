// WorkspacesPanel: where the time went, by workspace, with the items of
// one workspace (activity.md §1.6).

import SwiftUI
import TimeTrackingCore

/// "Where the time went": the workspaces and their items (§1.6).
struct WorkspacesPanel: View {
    @Bindable var model: ActivityModel

    var body: some View {
        ActivityPanel(title: "Where the time went") {
            Picker("Kind", selection: $model.workspaceKind) {
                ForEach(ActivityWorkspaceKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let row = model.drill {
                drill(row)
            } else {
                list
            }
        }
        .accessibilityIdentifier("activity.workspaces")
    }

    @ViewBuilder private var list: some View {
        let rows = model.workspaceRows
        let largest = rows.map(\.seconds).max() ?? 1
        ForEach(rows.prefix(model.showsAllWorkspaces ? rows.count : 20)) { row in
            HStack {
                Text(row.name).foregroundStyle(row.isPrivate ? .secondary : .primary).lineLimit(1)
                    .help(row.workspace)
                Text(row.apps.prefix(2).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Capsule().fill(row.isPrivate ? Color.gray : Color.accentColor)
                    .frame(width: 140 * CGFloat(row.seconds) / CGFloat(max(largest, 1)), height: 8)
                Text(ActivityText.duration(row.seconds)).frame(width: 64, alignment: .trailing)
                if row.hasItems {
                    Image(systemName: SymbolName.next).accessibilityHidden(true).foregroundStyle(.secondary)
                }
            }
            .modifier(ActivityRowAction(identifier: "activity.workspace.\(row.id)", action: row.hasItems ? { model.open(row) } : nil))
            .contextMenu {
                if model.isMac, let draft = TrackerExclusionDraft.forWorkspace(row) {
                    Button("Exclude \(draft.value) from Tracking…") { model.exclude(workspace: row) }
                }
            }
        }
        if rows.count > 20, !model.showsAllWorkspaces {
            Button("Show all (\(rows.count))") { model.showsAllWorkspaces = true }.buttonStyle(.borderless)
        }
    }

    private func drill(_ row: ActivityWorkspaceRow) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.compact) {
            HStack {
                Button(model.drillBreadcrumb ?? row.name) { model.closeDrill() }.buttonStyle(.borderless)
                Text("· \(row.items.count) \(row.items.count == 1 ? "item" : "items")").foregroundStyle(.secondary)
            }
            ForEach(row.items, id: \.label) { item in
                HStack {
                    Text(item.label).lineLimit(1)
                    Spacer()
                    Text(ActivityText.duration(item.seconds))
                }
            }
        }
    }
}
