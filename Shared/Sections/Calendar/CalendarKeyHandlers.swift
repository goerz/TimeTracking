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

    /// The command a key performs with ⇧ held. On the Mac a view's plain
    /// arrow or Tab shortcut may also take the key with ⇧ (which of the two
    /// buttons gets it varies), so the plain keys check ⇧ themselves.
    static func resolved(_ command: CalendarKeyCommand, shiftDown: Bool) -> CalendarKeyCommand {
        guard shiftDown else {
            return command
        }
        switch command {
        case .previousDay: return .previousSpan
        case .nextDay: return .nextSpan
        case .nextEntry: return .previousEntry
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
                    let resolved = Self.resolved(command, shiftDown: ModifierState.shiftDown())
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
