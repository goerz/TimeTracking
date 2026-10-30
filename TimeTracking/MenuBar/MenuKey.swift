// MenuKey: a key equivalent in the status item's menu (spec_menubar.md §2).

/// A key equivalent of a menu item.
struct MenuKey: Equatable {
    enum Modifier: Hashable {
        case command
        case shift
        case option
        case control
    }

    var key: String
    var modifiers: Set<Modifier>

    static func command(_ key: String, _ extra: Modifier...) -> Self {
        Self(key: key, modifiers: Set([.command] + extra))
    }

    /// "⌃⌥⇧⌘P" in the system's order.
    var display: String {
        let order: [(Modifier, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return order.filter { modifiers.contains($0.0) }.map(\.1).joined() + key.uppercased()
    }
}
