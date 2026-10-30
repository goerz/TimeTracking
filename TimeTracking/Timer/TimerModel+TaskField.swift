// The task field of the running-entry bar (spec_timer_window.md §2.2).

import Foundation
import TimeTrackingCore

extension TimerModel {
    /// A keystroke in the task field: while running, the task commits 500 ms
    /// after the last one.
    func taskTextChanged() {
        guard running != nil else {
            return
        }
        pendingTaskCommit?.cancel()
        let delay = debounce
        pendingTaskCommit = Task { [weak self] in
            do {
                try await delay(Self.taskCommitDelay)
            } catch {
                return
            }
            await self?.commitTask()
        }
    }

    /// Commits the running entry's task now (Return, focus loss, close).
    func commitTask() async {
        pendingTaskCommit?.cancel()
        pendingTaskCommit = nil
        guard let running, taskText.trimmed != running.task else {
            return
        }
        do {
            try await store.updateChain(of: running.id, task: taskText)
            await refresh()
        } catch {
            report(error)
        }
    }

    /// Escape: reverts to the stored task. Returns `false` when the field was
    /// unchanged, so focus moves to the list.
    func revertTask() -> Bool {
        guard let running, taskText != running.task else {
            return false
        }
        pendingTaskCommit?.cancel()
        pendingTaskCommit = nil
        taskText = running.task
        return true
    }

    /// Return in the task field: commit while running, start while idle.
    func submitTask() async {
        if running == nil {
            await start()
        } else {
            await commitTask()
        }
    }

    /// Accepts an autocompletion: sets task and project.
    func accept(_ suggestion: TaskSuggestion) async {
        taskText = suggestion.task
        if let running {
            do {
                try await store.updateChain(of: running.id, task: suggestion.task, projectID: .some(suggestion.projectID))
                await refresh()
            } catch {
                report(error)
            }
        } else {
            await setDraftProject(suggestion.projectID)
        }
    }
}
