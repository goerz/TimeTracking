// The Timer views' pointer and key inputs: the task field's Return and
// the list rows' click, double-click, and context menu
// (spec_timer.md §2.3, §3).

import Foundation
import TimeTrackingCore

/// The items of a list row's context menu, in order.
enum TimerRowMenuItem: CaseIterable {
    case continueEntry
    case edit
    case delete

    var title: String {
        switch self {
        case .continueEntry: "Continue"
        case .edit: "Edit…"
        case .delete: "Delete…"
        }
    }
}

extension AppModel {
    /// Return in `view`'s task field: the `@` picker's highlighted project
    /// (the `@query` leaves the text), else the highlighted suggestion,
    /// else the task is submitted. The returned task finishes the command.
    @discardableResult
    func taskFieldReturn(in view: TimerUIState) -> Task<Void, Never> {
        // A Return right after a keystroke: the `@query` must not end up
        // in a task, so it waits for the picker's lines.
        if view.taskField.pickerIsLoading {
            return Task {
                if let choice = await view.taskField.choosePickerHighlightWhenLoaded() {
                    await assignPicked(choice, in: view).value
                } else {
                    await timer.submitTask()
                }
            }
        }
        if let choice = view.taskField.choosePickerHighlight() {
            return assignPicked(choice, in: view)
        }
        if let suggestion = view.taskField.acceptSuggestion() {
            return Task {
                await timer.accept(suggestion)
                if !timer.isRunning {
                    await timer.start()
                }
            }
        }
        return Task { await timer.submitTask() }
    }

    /// A click on a project in `view`'s `@` picker list.
    @discardableResult
    func taskFieldPicked(_ choice: ProjectPickerChoice, in view: TimerUIState) -> Task<Void, Never> {
        view.taskField.reset()
        return assignPicked(choice, in: view)
    }

    /// Removes the `@query` from the task and assigns the chosen project.
    private func assignPicked(_ choice: ProjectPickerChoice, in view: TimerUIState) -> Task<Void, Never> {
        timer.taskText = TaskFieldModel.removingTrigger(from: timer.taskText)
        return Task {
            await choose(choice, in: view)
            await timer.commitTask()
        }
    }

    /// A click on a row of `view`: select it and open the edit popover.
    func rowClicked(_ id: EntryID, in view: TimerUIState) {
        view.list.selection = id
        view.editing = id
    }

    /// A double-click on a row: Continue.
    @discardableResult
    func rowDoubleClicked(_ id: EntryID) -> Task<Void, Never> {
        Task { await timer.continueEntry(id) }
    }

    /// A context-menu item of a row of `view`.
    @discardableResult
    func performRowMenu(_ item: TimerRowMenuItem, on id: EntryID, in view: TimerUIState) -> Task<Void, Never>? {
        switch item {
        case .continueEntry:
            return rowDoubleClicked(id)
        case .edit:
            rowClicked(id, in: view)
        case .delete:
            timer.alert = view.list.deleteAlert(for: id)
        }
        return nil
    }
}
