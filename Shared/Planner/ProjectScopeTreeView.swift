// ProjectScopeTreeView: the clients, areas, and projects of a Filters
// popover as a searchable tree of tri-state check boxes, shared by Projects
// and Reports (spec_planner_projects.md §2.4, spec_planner_reports.md §3).

import SwiftUI
import TimeTrackingCore

/// A search field above the tree; areas show their swatch, projects their
/// dot, retired areas and archived projects in secondary color. An optional
/// "No project" row comes first. Clients and areas with rows below fold
/// with a disclosure triangle; the tree opens with areas folded unless
/// partly checked.
struct ProjectScopeTreeView: View {
    var tree: ProjectScopeTree
    @Binding var scope: ProjectScope
    /// "No project" (Reports); `nil` hides the row.
    var noProject: Binding<Bool>?
    var identifier: String

    @State private var search = ""
    @State private var collapsed: Set<ProjectScopeNode>

    init(tree: ProjectScopeTree, scope: Binding<ProjectScope>, noProject: Binding<Bool>? = nil, identifier: String) {
        self.tree = tree
        _scope = scope
        self.noProject = noProject
        self.identifier = identifier
        _collapsed = State(initialValue: tree.initiallyCollapsed(in: scope.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.compact) {
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("\(identifier).search")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Design.Spacing.tight) {
                    if let noProject, search.isEmpty {
                        checkRow(noProject.wrappedValue ? .checked : .unchecked, depth: 0, node: nil) {
                            noProject.wrappedValue.toggle()
                        } label: {
                            Text("No project")
                        }
                    }
                    ForEach(tree.rows(matching: search, collapsed: collapsed)) { row in
                        checkRow(tree.state(of: row.node, in: scope), depth: row.depth, node: row.node) {
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

    /// A row: the disclosure slot (a triangle for a node with rows below),
    /// then the check box and label as one button.
    private func checkRow(
        _ state: CheckState,
        depth: Int,
        node: ProjectScopeNode?,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        HStack(spacing: Design.Spacing.tight) {
            disclosure(node)
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
            .accessibilityValue(state == .checked ? "checked" : state == .mixed ? "mixed" : "unchecked")
            .accessibilityIdentifier("\(identifier).node")
        }
        .padding(.leading, CGFloat(depth) * Design.Spacing.large)
    }

    /// The triangle of a client or area with rows below; ⌥-click folds or
    /// unfolds every row. A search unfolds everything, so it shows open.
    private func disclosure(_ node: ProjectScopeNode?) -> some View {
        Group {
            if let node, tree.hasChildren(node) {
                let isOpen = !search.isEmpty || !collapsed.contains(node)
                Button {
                    toggleFolding(node, open: !isOpen)
                } label: {
                    Image(systemName: isOpen ? SymbolName.expanded : SymbolName.next)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .accessibilityLabel(isOpen ? "Collapse" : "Expand")
                }
                .buttonStyle(.plain)
                .disabled(!search.isEmpty)
                .accessibilityIdentifier("\(identifier).disclosure")
            } else {
                Color.clear
            }
        }
        .frame(width: 14)
    }

    private func toggleFolding(_ node: ProjectScopeNode, open: Bool) {
        let nodes = ModifierState.optionDown() ? tree.rows.map(\.node).filter(tree.hasChildren) : [node]
        if open {
            collapsed.subtract(nodes)
        } else {
            collapsed.formUnion(nodes)
        }
    }

    private func symbol(_ state: CheckState) -> String {
        switch state {
        case .checked: SymbolName.checkboxOn
        case .mixed: SymbolName.checkboxMixed
        case .unchecked: SymbolName.checkboxOff
        }
    }
}
