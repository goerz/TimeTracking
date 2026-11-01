// ModifierState: whether ⌥ is held during a click, for the Calendar, Reports,
// and Projects, and whether ⇧ is held with a Calendar navigation key
// (spec_calendar.md §1.2, §2.3, §6; spec_projects.md §2.3).

/// Whether ⌥ or ⇧ is held; the Mac sets them from AppKit.
enum ModifierState {
    @MainActor static var optionDown: () -> Bool = { false }
    /// A view's plain-arrow or Tab shortcut on the Mac may also take the
    /// key with ⇧, so `CalendarKeyHandlers` checks ⇧ itself.
    @MainActor static var shiftDown: () -> Bool = { false }
}
