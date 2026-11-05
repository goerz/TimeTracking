// ModifierState: whether ⌥ is held during a click, for the Calendar, Reports,
// and Projects, whether ⇧ is held with a Calendar navigation key, and whether
// ⇧ or ⌘ extends a Calendar click
// (spec_calendar.md §1.2, §2.3, §2.5, §5; spec_projects.md §2.3).

/// Whether ⌥ or ⇧ is held; the Mac sets them from AppKit.
enum ModifierState {
    @MainActor static var optionDown: () -> Bool = { false }
    /// ⇧ or ⌘ on a click, which extends a selection.
    @MainActor static var extendDown: () -> Bool = { false }
    /// A view's plain-arrow or Tab shortcut on the Mac may also take the
    /// key with ⇧, so `CalendarKeyHandlers` checks ⇧ itself.
    @MainActor static var shiftDown: () -> Bool = { false }
    /// Whether `shiftDown` reads the key press's own ⇧ (the Mac); elsewhere
    /// a shortcut's own modifiers are all there is.
    @MainActor static var readsKeyPresses = false
}
