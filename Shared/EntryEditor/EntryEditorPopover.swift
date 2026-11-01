// EntryEditorPopover: the edit popover of one entry, opened by an
// `editing` id (spec_timer_window.md §4; spec_calendar.md §2.5;
// spec_reports.md §6).

import SwiftUI
import TimeTrackingCore

/// Builds an `EntryEditorModel` when `editing` names the entry and shows
/// `EntryEditorView` in a popover until `editing` changes or the popover
/// closes; closing clears `editing` unless it already names another entry.
/// Applied with `.modifier(EntryEditorPopover(...))`.
struct EntryEditorPopover: ViewModifier {
    /// The entry this view edits; nil shows nothing (the bar while stopped).
    var entry: TimeEntry?
    @Binding var editing: EntryID?
    var store: TimeStore
    var clock: any Clock
    /// Whether the picker matches the task text (the Timer's running-entry bar).
    var taskMatching = false
    var arrowEdge: Edge
    /// Whether a view that appears while `editing` already names its entry
    /// opens the editor (the sections' cards and rows, which reloads rebuild).
    var opensOnAppear = false
    /// Called after the editor stored a change.
    var onChange: () async -> Void

    @State private var editor: EntryEditorModel?

    func body(content: Content) -> some View {
        content
            .popover(isPresented: shown, arrowEdge: arrowEdge) {
                if let editor {
                    EntryEditorView(model: editor, makePicker: makePicker) {
                        editing = nil
                    }
                }
            }
            .onChange(of: editing, initial: opensOnAppear) { _, editing in
                if let entry, editing == entry.id {
                    let model = EntryEditorModel(store: store, clock: clock, entry: entry)
                    model.onChange = onChange
                    model.onDelete = { self.editing = nil }
                    editor = model
                }
            }
    }

    private var shown: Binding<Bool> {
        Binding {
            entry.map { editing == $0.id } ?? false && editor != nil
        } set: { shown in
            if !shown, editing == editor?.entry.id {
                editing = nil
            }
        }
    }

    private func makePicker(_ current: ProjectID?) -> ProjectPickerModel {
        ProjectPickerModel(store: store, currentProject: current, taskMatching: taskMatching)
    }
}
