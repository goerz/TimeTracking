// MenuHeaderLine: a header line of the status item's menu (menubar.md §2.1).

/// A disabled line at the top of the menu (menubar.md §2.1).
struct MenuHeaderLine: Equatable {
    enum Style: Equatable {
        /// The running task or "Not tracking": the menu font, semibold.
        case title
        /// The project and Pomodoro lines: primary text, then `secondary` in the secondary color.
        case primary
        /// The start time and the last entry: the secondary color.
        case secondary
        /// The tracker warning.
        case warning
    }

    var text: String
    /// Text after `text` in the secondary color (" · client").
    var secondary: String?
    var style: Style
    /// An SF Symbol shown as the item's image.
    var symbol: String?
    /// The area dot shown as the item's image: an `#RRGGBB` color, or `""`
    /// for the hollow dot of no project.
    var dot: String?

    init(_ text: String, secondary: String? = nil, style: Style, symbol: String? = nil, dot: String? = nil) {
        self.text = text
        self.secondary = secondary
        self.style = style
        self.symbol = symbol
        self.dot = dot
    }

    /// The line as plain text.
    var plain: String {
        text + (secondary ?? "")
    }
}
