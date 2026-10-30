// TimerUIState: presentation state of the Timer window that menu commands
// drive (spec_timer_window.md §9).

import Foundation
import Observation
import TimeTrackingCore

/// Window-level presentation: the chip's picker, the edit popover, focus.
@Observable
final class TimerUIState {
    /// The chip's picker (click, ⌘P, Space).
    var pickerModel: ProjectPickerModel?
    /// The entry whose edit popover is open.
    var editing: EntryID?
    /// The new-project dialog opened from a picker.
    var dialogModel: ProjectDialogModel?
    /// Bumped to move keyboard focus to the list.
    private(set) var focusListRequest = 0
    /// Whether the list has keyboard focus (⌘⌫ applies to the selection).
    var listFocused = false

    func focusList() {
        focusListRequest += 1
    }
}

/// The Timer window's AppKit side, as the models see it.
@MainActor
protocol TimerWindowControlling: AnyObject {
    var isCompact: Bool { get }
    var isKey: Bool { get }
    /// ⇧⌘M.
    func toggleCompact()
    /// The pin.
    func applyPin(_ pinned: Bool)
    func show()
    func hide()
}
