// StatusItemContent: what the menu bar item shows (menubar.md §1).

/// The status item's icon, title, Pomodoro segment, badge, and accessibility label.
struct StatusItemContent: Equatable {
    /// The Pomodoro countdown after the title: the phase glyph and `m:ss`
    /// (`+m:ss` once the phase has ended).
    struct PomodoroSegment: Equatable {
        /// Symbol name, template: `SymbolName.phase(isFocus:)`.
        var symbol: String
        var text: String
    }

    /// The dial icon's knob, as a fraction of a turn clockwise from 12
    /// o'clock: the running entry's minutes within the hour, or the
    /// Pomodoro phase's progress. `nil` while nothing runs (the empty ring).
    var dial: Double?
    /// The elapsed time and the project, as the settings ask.
    var title: String
    var pomodoro: PomodoroSegment?
    /// The exclamation-mark badge of the tracker warning.
    var badge: Bool
    var accessibilityLabel: String

    /// Everything the item shows as text: the accessibility title.
    var visibleText: String {
        [title, pomodoro?.text ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
