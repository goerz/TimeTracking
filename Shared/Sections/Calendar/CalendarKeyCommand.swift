// CalendarKeyCommand: every key of the Calendar section with its menu item
// (spec_calendar.md §5).

import SwiftUI
import TimeTrackingCore

/// A keyboard command of the Calendar; each is a menu item while the section shows.
enum CalendarKeyCommand: String, CaseIterable, Identifiable {
    case today
    case zoomIn
    case zoomOut
    case zoomReset
    case narrowerDays
    case widerDays
    case previousDay
    case nextDay
    case previousSpan
    case nextSpan
    case toggleActivity
    case toggleCalendar
    case nextEntry
    case previousEntry
    case edit
    case createEntry
    case moveEarlier
    case moveLater
    case lengthen
    case shorten
    case delete
    case duplicate
    case escape

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .today: "Today"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .zoomReset: "Actual Size"
        case .narrowerDays: "Narrower Days"
        case .widerDays: "Wider Days"
        case .previousDay: "Previous Day"
        case .nextDay: "Next Day"
        case .previousSpan: "Previous Days"
        case .nextSpan: "Next Days"
        case .toggleActivity: "Show Activity Column"
        case .toggleCalendar: "Show Calendar Column"
        case .nextEntry: "Next Entry"
        case .previousEntry: "Previous Entry"
        case .edit: "Edit Selection…"
        case .createEntry: "Create Entry from Selection"
        case .moveEarlier: "Move Earlier"
        case .moveLater: "Move Later"
        case .lengthen: "Lengthen"
        case .shorten: "Shorten"
        case .delete: "Delete"
        case .duplicate: "Duplicate to Next Day"
        case .escape: "Deselect"
        }
    }

    /// The key and modifiers.
    var shortcut: KeyboardShortcut {
        switch self {
        case .today: KeyboardShortcut("t")
        case .zoomIn: KeyboardShortcut("+")
        case .zoomOut: KeyboardShortcut("-")
        case .zoomReset: KeyboardShortcut("0")
        case .narrowerDays: KeyboardShortcut("[", modifiers: [.command, .option])
        case .widerDays: KeyboardShortcut("]", modifiers: [.command, .option])
        case .previousDay: KeyboardShortcut(.leftArrow, modifiers: [])
        case .nextDay: KeyboardShortcut(.rightArrow, modifiers: [])
        case .previousSpan: KeyboardShortcut(.leftArrow, modifiers: .shift)
        case .nextSpan: KeyboardShortcut(.rightArrow, modifiers: .shift)
        case .toggleActivity: KeyboardShortcut("a", modifiers: [.command, .option])
        case .toggleCalendar: KeyboardShortcut("k", modifiers: [.command, .option])
        case .nextEntry: KeyboardShortcut(.tab, modifiers: [])
        case .previousEntry: KeyboardShortcut(.tab, modifiers: .shift)
        case .edit: KeyboardShortcut(.return, modifiers: [])
        case .createEntry: KeyboardShortcut(.space, modifiers: [])
        case .moveEarlier: KeyboardShortcut(.upArrow)
        case .moveLater: KeyboardShortcut(.downArrow)
        case .lengthen: KeyboardShortcut(.downArrow, modifiers: [.command, .option])
        case .shorten: KeyboardShortcut(.upArrow, modifiers: [.command, .option])
        case .delete: KeyboardShortcut(.delete, modifiers: [])
        case .duplicate: KeyboardShortcut("d")
        case .escape: KeyboardShortcut(.escape, modifiers: [])
        }
    }

    /// Navigation keys the Calendar view handles itself (`CalendarKeyHandlers`);
    /// as on every Mac, arrows, Tab, and Escape are not menu items. Today is
    /// View › Go to Today; the rest are the Calendar menu's.
    var isViewKey: Bool {
        switch self {
        case .previousDay, .nextDay, .previousSpan, .nextSpan, .nextEntry, .previousEntry, .escape:
            true
        default:
            false
        }
    }
}

extension CalendarModel {
    /// Performs a key command (the menu item and the key do the same).
    func perform(_ command: CalendarKeyCommand) async { // swiftlint:disable:this cyclomatic_complexity
        switch command {
        case .today: await goToToday()
        case .zoomIn: zoom(by: 1)
        case .zoomOut: zoom(by: -1)
        case .zoomReset: zoom(by: 0)
        case .narrowerDays: zoomDays(by: -1)
        case .widerDays: zoomDays(by: 1)
        case .previousDay: await shift(days: -1)
        case .nextDay: await shift(days: 1)
        case .previousSpan: await shift(days: -viewport.wholeDays)
        case .nextSpan: await shift(days: viewport.wholeDays)
        case .toggleActivity: await toggle(.activity)
        case .toggleCalendar: await toggle(.calendar)
        default: await performSelectionCommand(command)
        }
    }

    private func performSelectionCommand(_ command: CalendarKeyCommand) async { // swiftlint:disable:this cyclomatic_complexity
        switch command {
        case .nextEntry: stepSelection(by: 1)
        case .previousEntry: stepSelection(by: -1)
        case .edit: editSelection()
        case .createEntry: createEntryFromSelection()
        case .moveEarlier: await nudgeSelection(steps: -1, lengthen: false)
        case .moveLater: await nudgeSelection(steps: 1, lengthen: false)
        case .lengthen: await nudgeSelection(steps: 1, lengthen: true)
        case .shorten: await nudgeSelection(steps: -1, lengthen: true)
        case .delete: await deleteSelection()
        case .duplicate: await duplicateSelection()
        case .escape: escape()
        default: break
        }
    }

    /// A popover or editor takes the plain keys.
    var takesTextInput: Bool {
        draft != nil || blockDraft != nil || editingEntry != nil || pendingOverlap != nil || showsMonthPicker
            || showsFilters || searchFocused
    }

    /// Return: the editor of the selected entry or time block.
    func editSelection() {
        for item in selection {
            switch item {
            case let .entry(id):
                editingEntry = id
                return
            case let .timeBlock(id):
                if let block = timeBlocks.first(where: { $0.id == id }) {
                    editTimeBlock(block)
                }
                return
            default:
                continue
            }
        }
    }

    /// Escape: closes a popover or editor, else deselects.
    func escape() {
        if pendingOverlap != nil {
            pendingOverlap = nil
        } else if draft != nil {
            draft = nil
        } else if blockDraft != nil {
            blockDraft = nil
        } else if editingEntry != nil {
            editingEntry = nil
        } else {
            selection = []
        }
    }
}
