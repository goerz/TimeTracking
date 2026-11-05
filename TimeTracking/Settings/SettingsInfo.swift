// SettingsInfo: the content of a settings row's info button
// (activity_tracking.md §7.4, timer.md §8.1).

/// The content of an info button's popover.
struct SettingsInfo: Equatable {
    var title: String
    var paragraphs: [String]
    /// The text to copy, shown in a monospaced box with a Copy button.
    var snippet: String?
}
