// ReportsModel+Breakdown: the breakdown table's rows, expansion, sorting,
// and drill-down to the entry list (spec_planner_reports.md §5.3).

import Foundation
import TimeTrackingCore

extension ReportsModel {
    // MARK: Breakdown

    /// The tree sorted by the table's column.
    var sortedTree: ReportNode? {
        snapshot?.tree.sorted(by: state.tableSort, ascending: state.tableAscending)
    }

    /// The visible rows, depth first.
    var breakdownRows: [BreakdownRow] {
        guard let tree = sortedTree else {
            return []
        }
        var rows: [BreakdownRow] = []
        func visit(_ node: ReportNode, path: [GroupKeyValue], depth: Int) {
            for child in node.children {
                let childPath = path + [child.key]
                let open = expanded.contains(childPath)
                rows.append(BreakdownRow(path: childPath, node: child, level: state.levels[depth], depth: depth, isExpanded: open))
                if open {
                    visit(child, path: childPath, depth: depth + 1)
                }
            }
        }
        visit(tree, path: [], depth: 0)
        return rows
    }

    /// The header button: "Expand All" while any node is collapsed.
    var anyCollapsed: Bool {
        guard let tree = snapshot?.tree else {
            return false
        }
        return tree.expandablePaths.contains { !expanded.contains($0) }
    }

    func toggle(_ path: [GroupKeyValue]) {
        if expanded.contains(path) {
            expanded.remove(path)
        } else {
            expanded.insert(path)
        }
    }

    /// ⌥-click and ⌥→: the node's subtree.
    func setSubtreeExpanded(_ path: [GroupKeyValue], _ open: Bool) {
        guard let node = snapshot?.tree.node(at: path) else {
            return
        }
        let paths = [path] + node.expandablePaths.map { path + $0 }
        if open {
            expanded.formUnion(paths)
        } else {
            expanded.subtract(paths)
        }
    }

    /// ⇧⌘→.
    func expandAll() {
        expanded = Set(snapshot?.tree.expandablePaths ?? [])
    }

    /// ⇧⌘←.
    func collapseAll() {
        expanded = []
    }

    /// A column header click: the same column reverses.
    func sortTable(by column: ReportColumn) {
        if state.tableSort == column {
            state.tableAscending.toggle()
        } else {
            state.tableSort = column
            state.tableAscending = column == .name
        }
    }

    /// Double-click or ↩ on a node: the entry list filtered to its key path.
    func openNode(_ path: [GroupKeyValue]) async {
        entryPath = path
        state.card = .entries
        await reload()
    }

    /// "Research › Noise Model › Clarify noise model".
    var pathChipText: String? {
        guard !entryPath.isEmpty, let tree = snapshot?.tree else {
            return nil
        }
        var names: [String] = []
        for index in entryPath.indices {
            if let node = tree.node(at: Array(entryPath[...index])) {
                names.append(node.displayName(level: state.levels[index]))
            }
        }
        return names.joined(separator: " › ")
    }

    /// The chip's ×, Escape in the list, or switching back to Breakdown.
    func clearEntryPath() async {
        guard !entryPath.isEmpty else {
            return
        }
        entryPath = []
        await reload()
    }

    /// ⌃⌘1 / ⌃⌘2 and the segmented control.
    func show(_ card: ReportCard) async {
        state.card = card
        if card == .breakdown {
            await clearEntryPath()
        }
    }
}
