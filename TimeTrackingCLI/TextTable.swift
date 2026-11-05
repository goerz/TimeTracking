// TextTable: the human-readable tables, which may change between versions
// (automation.md §1).

import Foundation

/// A table with left- or right-aligned columns, a bold header when colored,
/// and rule lines.
nonisolated struct TextTable {
    enum Row {
        case cells([String])
        case rule
    }

    var headers: [String]
    /// Indices of right-aligned columns.
    var rightAligned: Set<Int> = []
    var rows: [Row] = []

    mutating func add(_ cells: [String]) {
        rows.append(.cells(cells))
    }

    mutating func rule() {
        rows.append(.rule)
    }

    func render(colors: Bool) -> String {
        var widths = headers.map(\.count)
        for case let .cells(cells) in rows {
            for (index, cell) in cells.enumerated() where index < widths.count {
                widths[index] = max(widths[index], cell.count)
            }
        }
        func line(_ cells: [String]) -> String {
            cells.enumerated().map { index, cell in
                let pad = String(repeating: " ", count: max(0, widths[index] - cell.count))
                return rightAligned.contains(index) ? pad + cell : cell + pad
            }
            .joined(separator: "  ")
            .replacing(/\s+$/, with: "")
        }
        let header = line(headers)
        var lines = [colors ? "\u{1B}[1m\(header)\u{1B}[0m" : header]
        let ruleLine = String(repeating: "-", count: widths.reduce(0, +) + 2 * max(0, widths.count - 1))
        for row in rows {
            switch row {
            case let .cells(cells): lines.append(line(cells + Array(repeating: "", count: max(0, headers.count - cells.count))))
            case .rule: lines.append(ruleLine)
            }
        }
        return lines.joined(separator: "\n")
    }
}
