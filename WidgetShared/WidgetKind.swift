// WidgetKind: the kinds of the widgets and controls (ios.md §3, §5).
// Compiled into the app and the widget extension.

/// The widget kinds and control kinds.
nonisolated enum WidgetKind {
    static let now = "now"
    static let recent = "recent"
    static let pinned = "pinned"
    static let timerToggle = "timerToggle"
    static let startProject = "startProject"
}
