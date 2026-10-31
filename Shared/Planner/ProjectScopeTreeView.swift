// ProjectScopeTreeView: the clients, areas, and projects of a Filters
// popover as a searchable tree of tri-state check boxes, shared by Projects
// and Reports (spec_planner_projects.md §2.4, spec_planner_reports.md §3).

import SwiftUI
import TimeTrackingCore

/// A search field above the tree; areas show their swatch, projects their
/// dot, retired areas and archived projects in secondary color. An optional
/// "No project" row comes first.
struct ProjectScopeTreeView: View {
    var tree: ProjectScopeTree
    @Binding var scope: ProjectScope
    /// "No project" (Reports); `nil` hides the row.
    var noProject: Binding<Bool>?
    var identifier: String

    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.compact) {
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("\(identifier).search")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Design.Spacing.tight) {
                    if let noProject, search.isEmpty {
                        checkRow(noProject.wrappedValue ? .checked : .unchecked, depth: 0) {
                            noProject.wrappedValue.toggle()
                        } label: {
                            Text("No project")
                        }
                    }
                    ForEach(tree.rows(matching: search)) { row in
                        checkRow(tree.state(of: row.node, in: scope), depth: row.depth) {
                            scope = tree.toggling(row.node, in: scope)
                        } label: {
                            label(row)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 260)
            .accessibilityIdentifier("\(identifier).tree")
        }
    }

    private func label(_ row: ProjectScopeTree.Row) -> some View {
        HStack(spacing: Design.Spacing.compact) {
            if let color = row.color {
                if case .area = row.node {
                    AreaSwatch(color: color)
                } else {
                    AreaDot(color: color)
                }
            }
            Text(row.name)
                .fontWeight(row.depth == 0 ? .semibold : .regular)
                .foregroundStyle(row.isInactive ? .secondary : .primary)
        }
    }

    private func checkRow(
        _ state: CheckState,
        depth: Int,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing.compact) {
                Image(systemName: symbol(state))
                    .foregroundStyle(state == .unchecked ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    .accessibilityHidden(true)
                label()
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, CGFloat(depth) * Design.Spacing.large)
        .accessibilityValue(state == .checked ? "checked" : state == .mixed ? "mixed" : "unchecked")
        .accessibilityIdentifier("\(identifier).node")
    }

    private func symbol(_ state: CheckState) -> String {
        switch state {
        case .checked: SymbolName.checkboxOn
        case .mixed: SymbolName.checkboxMixed
        case .unchecked: SymbolName.checkboxOff
        }
    }
}
