// CalendarKeyHandlers: the Calendar's navigation keys, which are not menu
// items (spec_calendar.md §5).

import SwiftUI
import TimeTrackingCore

/// Invisible buttons carrying the keys of `CalendarKeyCommand.isViewKey`
/// (←, →, ⇧←, ⇧→, Tab, ⇧Tab, Escape) while the Calendar shows; off while a
/// popover, editor, or sheet takes text input.
struct CalendarKeyHandlers: View {
    var model: CalendarModel

    static let commands: [CalendarKeyCommand] = [
        .previousSpan, .nextSpan, .previousEntry, .previousDay, .nextDay, .nextEntry, .escape,
    ]

    /// Whether ⇧ is held for a key press, as far as the platform tells.
    enum Shift {
        case held
        case notHeld
        /// The iPad: a shortcut's own modifiers are all there is.
        case unknown
    }

    /// The command of a key by whether ⇧ is held for it. On the Mac a
    /// view's arrow or Tab shortcut may take the key with or without ⇧
    /// (which of the two buttons gets it varies), so either button decides
    /// by the key press's own ⇧; where that is unknown each button keeps
    /// its own command.
    static func resolved(_ command: CalendarKeyCommand, shift: Shift) -> CalendarKeyCommand {
        let held: Bool
        switch shift {
        case .held: held = true
        case .notHeld: held = false
        case .unknown: return command
        }
        switch command {
        case .previousDay, .previousSpan: return held ? .previousSpan : .previousDay
        case .nextDay, .nextSpan: return held ? .nextSpan : .nextDay
        case .nextEntry, .previousEntry: return held ? .previousEntry : .nextEntry
        default: return command
        }
    }

    /// The days ←, →, ⇧←, and ⇧→ step by; nil for the other keys.
    static func step(_ command: CalendarKeyCommand, wholeDays: Int) -> Int? {
        switch command {
        case .previousDay: -1
        case .nextDay: 1
        case .previousSpan: -wholeDays
        case .nextSpan: wholeDays
        default: nil
        }
    }

    var body: some View {
        ZStack {
            ForEach(Self.commands) { command in
                Button(command.title) {
                    let shift: Shift = ModifierState.readsKeyPresses ? (ModifierState.shiftDown() ? .held : .notHeld) : .unknown
                    let resolved = Self.resolved(command, shift: shift)
                    if let days = Self.step(resolved, wholeDays: model.viewport.wholeDays) {
                        // The days slide over, as with the toolbar's arrows.
                        withAnimation(.smooth(duration: 0.3)) { model.step(days: days) }
                    } else {
                        Task { await model.perform(resolved) }
                    }
                }
                .keyboardShortcut(command.shortcut)
                .disabled(model.takesTextInput)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
