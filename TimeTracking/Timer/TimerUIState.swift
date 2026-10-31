// TimerUIState: one Timer view's own state, the Mini Timer's or the main
// window's (spec_timer_window.md §1, §9).

import Foundation
import Observation
import TimeTrackingCore

/// One Timer view's presentation: its list (days, filter, selection), its
/// task field's popup, the chip's picker, the edit popover, the project
/// dialog, and focus. The Mini Timer and the main window's Timer each own
/// one, so nothing opened in one shows in the other; both show the stored
/// result.
@Observable
final class TimerUIState {
    /// Which Timer view this is.
    enum Place {
        case miniTimer
        case mainWindow
    }

    let place: Place
    /// This view's list: its days, filter, selection, and scroll position.
    let list: TimerListModel
    /// This view's task field: suggestions and the `@` picker.
    let taskField: TaskFieldModel
    /// The chip's picker (click, ⌘J, Space).
    var pickerModel: ProjectPickerModel?
    /// The entry whose edit popover is open.
    var editing: EntryID?
    /// The new-project dialog opened from a picker.
    var dialogModel: ProjectDialogModel?
    /// Bumped to move keyboard focus to the list.
    private(set) var focusListRequest = 0
    /// Whether the list has keyboard focus (⌘⌫ applies to the selection).
    var listFocused = false
    /// Set to focus the task field; the field clears it once focused, so a
    /// request made before the view appears still applies.
    var wantsTaskFieldFocus = false
    /// The task field's leading edge in the window; the suggestions popup
    /// lines up with it.
    var taskFieldLeading: CGFloat = Design.Spacing.window + Design.CircleDiameter.bar + Design.Spacing.medium

    init(place: Place, store: TimeStore, clock: any Clock) {
        self.place = place
        self.list = TimerListModel(store: store, clock: clock)
        self.taskField = TaskFieldModel(store: store)
    }

    func focusList() {
        focusListRequest += 1
    }

    func focusTaskField() {
        wantsTaskFieldFocus = true
    }
}

/// The Timer window's AppKit side, as the models see it.
@MainActor
protocol TimerWindowControlling: AnyObject {
    var isCompact: Bool { get }
    var isKey: Bool { get }
    /// The Mini Timer is on screen.
    var isVisible: Bool { get }
    /// ⇧⌘M.
    func toggleCompact()
    /// The pin.
    func applyPin(_ pinned: Bool)
    func show()
    func hide()
}
