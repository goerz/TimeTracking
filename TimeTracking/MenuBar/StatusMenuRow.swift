// StatusMenuRow: a menu line as shown, header lines grouped (spec_menubar.md §2.1).

/// A menu entry as shown: consecutive header lines form one item.
enum StatusMenuRow: Equatable {
    case header([MenuHeaderLine])
    case entry(StatusMenuEntry)

    static func rows(_ entries: [StatusMenuEntry]) -> [Self] {
        var rows: [Self] = []
        var pending: [MenuHeaderLine] = []
        for entry in entries {
            if case let .header(line) = entry {
                pending.append(line)
                continue
            }
            if !pending.isEmpty {
                rows.append(.header(pending))
                pending = []
            }
            rows.append(.entry(entry))
        }
        if !pending.isEmpty {
            rows.append(.header(pending))
        }
        return rows
    }

    /// The row without header text: equal shapes need no rebuild. Compared
    /// by value, not by description: a key's modifier set describes itself
    /// in varying order, which rebuilt the open menu every few seconds.
    var shape: Self {
        switch self {
        case let .header(lines): .header(lines.map { _ in MenuHeaderLine("", style: .title) })
        case .entry: self
        }
    }

    /// The header lines as a one-element array, else empty.
    var headerGroup: [[MenuHeaderLine]] {
        if case let .header(lines) = self {
            return [lines]
        }
        return []
    }
}
