// The Timer window's pointer and key inputs: the task field's Return and
// the list rows' click, double-click, and context menu
// (spec_timer_window.md §2.3, §3).

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
    /// Return in the task field: the `@` picker's highlighted project
    /// (the `@query` leaves the text), else the highlighted suggestion,
    /// else the task is submitted. The returned task finishes the command.
    @discardableResult
    func taskFieldReturn() -> Task<Void, Never> {
        if let choice = taskField.choosePickerHighlight() {
            return assignPicked(choice)
        }
        if let suggestion = taskField.acceptSuggestion() {
            return Task {
                await timer.accept(suggestion)
                if !timer.isRunning {
                    await timer.start()
                }
            }
        }
        return Task { await timer.submitTask() }
    }

    /// A click on a project in the `@` picker list.
    @discardableResult
    func taskFieldPicked(_ choice: ProjectPickerChoice) -> Task<Void, Never> {
        taskField.reset()
        return assignPicked(choice)
    }

    /// Removes the `@query` from the task and assigns the chosen project.
    private func assignPicked(_ choice: ProjectPickerChoice) -> Task<Void, Never> {
        timer.taskText = TaskFieldModel.removingTrigger(from: timer.taskText)
        return Task {
            await choose(choice)
            await timer.commitTask()
        }
    }

    /// A click on a row: select it and open the edit popover.
    func rowClicked(_ id: EntryID) {
        list.selection = id
        presentation.editing = id
    }

    /// A double-click on a row: Continue.
    @discardableResult
    func rowDoubleClicked(_ id: EntryID) -> Task<Void, Never> {
        Task { await timer.continueEntry(id) }
    }

    /// A context-menu item of a row.
    @discardableResult
    func performRowMenu(_ item: TimerRowMenuItem, on id: EntryID) -> Task<Void, Never>? {
        switch item {
        case .continueEntry:
            return rowDoubleClicked(id)
        case .edit:
            rowClicked(id)
        case .delete:
            timer.alert = list.deleteAlert(for: id)
        }
        return nil
    }
}
