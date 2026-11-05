// StatusMenuEntry: one line of the status item's menu (menubar.md §2).

/// One line of the menu.
enum StatusMenuEntry: Equatable {
    /// A disabled informational line.
    case header(MenuHeaderLine)
    case separator
    case item(title: String, key: MenuKey?, enabled: Bool, command: MenuCommand)
}
