// View+ContextCommand: a menu item that applies in one window or section
// (timer.md §9).

import SwiftUI

extension View {
    /// A menu item that applies in one context: enabled, and holding its
    /// key equivalent, only while `enabled`. A disabled item keeps no key
    /// because AppKit sends a key equivalent to the first item that has it,
    /// even a disabled one, and the key would not reach the item of another
    /// context or a text field.
    func contextCommand(_ shortcut: KeyboardShortcut?, enabled: Bool) -> some View {
        keyboardShortcut(enabled ? shortcut : nil)
            .disabled(!enabled)
    }
}
