// GlobalShortcuts: the recordable system-wide shortcuts
// (spec_timer_window.md §8.3, spec_architecture.md §5).

import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Show/hide the Timer window, ⌥⌘R by default.
    static let showHideTimer = Self("showHideTimer", initial: .init(.r, modifiers: [.option, .command]))
    /// Continue/stop, unassigned by default.
    static let continueStop = Self("continueStop")
}

/// Registers the two shortcuts' handlers.
enum GlobalShortcuts {
    static func register(toggleTimer: @escaping () -> Void, continueOrStop: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .showHideTimer, action: toggleTimer)
        KeyboardShortcuts.onKeyUp(for: .continueStop, action: continueOrStop)
    }

    /// The recorded show/hide shortcut as a menu key, `nil` when cleared.
    static var showHideKey: MenuKey? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .showHideTimer), let key = shortcut.nsMenuItemKeyEquivalent else {
            return nil
        }
        var modifiers: Set<MenuKey.Modifier> = []
        if shortcut.modifiers.contains(.command) {
            modifiers.insert(.command)
        }
        if shortcut.modifiers.contains(.shift) {
            modifiers.insert(.shift)
        }
        if shortcut.modifiers.contains(.option) {
            modifiers.insert(.option)
        }
        if shortcut.modifiers.contains(.control) {
            modifiers.insert(.control)
        }
        return MenuKey(key: key, modifiers: modifiers)
    }
}

extension MenuKey {
    /// The AppKit modifier mask.
    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) {
            flags.insert(.command)
        }
        if modifiers.contains(.shift) {
            flags.insert(.shift)
        }
        if modifiers.contains(.option) {
            flags.insert(.option)
        }
        if modifiers.contains(.control) {
            flags.insert(.control)
        }
        return flags
    }
}
