// ActivityFocusMove: an arrow key on the Activity section's heatmap and bars
// (spec_activity.md §2).

/// A step of the keyboard focus inside a panel.
public enum ActivityFocusMove: Sendable, Hashable {
    case left
    case right
    case above
    case below
}
