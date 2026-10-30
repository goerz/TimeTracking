// ModifierState: whether ⌥ is held during a click, for the Calendar, Reports,
// and Projects (spec_planner_calendar.md §1.2, §2.3; spec_planner_projects.md §2.3).

/// Whether ⌥ is held during a click; the Mac sets it from AppKit.
enum ModifierState {
    @MainActor static var optionDown: () -> Bool = { false }
}
