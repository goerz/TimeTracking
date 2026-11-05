// ActivityHeatmap+Focus: the arrow keys on the heatmap's cells
// (spec_activity.md §2).

extension ActivityHeatmap {
    /// A cell: its row and clock hour.
    public struct Cell: Sendable, Hashable {
        public var row: Row.ID
        public var hour: Int

        public init(row: Row.ID, hour: Int) {
            self.row = row
            self.hour = hour
        }
    }

    /// The rows top down, with the footer.
    public var allRows: [Row] {
        rows + (footer.map { [$0] } ?? [])
    }

    public func row(of cell: Cell) -> Row? {
        allRows.first { $0.id == cell.row }
    }

    /// The top row's leftmost cell.
    public func firstCell(midnightHour: Int) -> Cell? {
        allRows.first.map { Cell(row: $0.id, hour: Self.columns(midnightHour: midnightHour)[0]) }
    }

    /// The cell `move` reaches from `cell`, staying put at an edge. Without
    /// a cell, or one of a row no longer shown, the first cell.
    public func cell(_ move: ActivityFocusMove, from cell: Cell?, midnightHour: Int) -> Cell? {
        let rows = allRows
        guard let cell, let row = rows.firstIndex(where: { $0.id == cell.row }) else {
            return firstCell(midnightHour: midnightHour)
        }
        let columns = Self.columns(midnightHour: midnightHour)
        let column = columns.firstIndex(of: cell.hour) ?? 0
        return switch move {
        case .left: Cell(row: cell.row, hour: columns[max(column - 1, 0)])
        case .right: Cell(row: cell.row, hour: columns[min(column + 1, columns.count - 1)])
        case .above: Cell(row: rows[max(row - 1, 0)].id, hour: cell.hour)
        case .below: Cell(row: rows[min(row + 1, rows.count - 1)].id, hour: cell.hour)
        }
    }
}
