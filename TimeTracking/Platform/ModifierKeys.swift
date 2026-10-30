// ModifierKeys: the modifier keys held during a click (⌥-click skips the
// discard alert, spec_timer_window.md §2.1).

import AppKit

/// The current modifier keys, read from AppKit.
enum ModifierKeys {
    static var optionIsDown: Bool {
        NSEvent.modifierFlags.contains(.option)
    }
}
