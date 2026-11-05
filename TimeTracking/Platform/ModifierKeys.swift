// ModifierKeys: the modifier keys held during a click or key press (⌥-click
// skips the discard alert, spec_timer.md §2.1; the Calendar's ⌥, ⇧, and ⌘,
// spec_calendar.md §1.2, §2.5, §5).

import AppKit

/// The modifier keys of the event being handled (the click or key press),
/// read from AppKit; the keyboard's state when there is none. The event's
/// own flags are what the user held for it: the keyboard's state can lag
/// behind or run ahead of the event, and a synthesized ⇧-scroll can leave it
/// set.
enum ModifierKeys {
    static var optionIsDown: Bool {
        flags.contains(.option)
    }

    static var shiftIsDown: Bool {
        flags.contains(.shift)
    }

    /// ⇧-click or ⌘-click (spec_calendar.md §2.5).
    static var extendsSelection: Bool {
        !flags.isDisjoint(with: [.shift, .command])
    }

    /// The click count of the click being handled; 1 for any other event.
    static var clickCount: Int {
        guard let event = NSApp.currentEvent, [.leftMouseDown, .leftMouseUp].contains(event.type) else {
            return 1
        }
        return event.clickCount
    }

    private static var flags: NSEvent.ModifierFlags {
        NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
    }
}
