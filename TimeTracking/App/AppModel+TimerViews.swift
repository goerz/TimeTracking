// AppModel+TimerViews: the commands of the two Timer views, the Mini
// Timer's and the main window's, each acting on its own state
// (timer.md §1, §2.3, §3).

import Foundation
import TimeTrackingCore

extension AppModel {
    /// The Timer view menu commands go to: the one in the key window, else
    /// the Mini Timer while it is on screen, else the main window's.
    var activeTimer: TimerUIState {
        if let keyTimer {
            return keyTimer
        }
        return window?.isVisible == true ? miniTimer : mainTimer
    }

    /// The Timer view in the key window: the Mini Timer, or the main
    /// window while it shows its Timer.
    var keyTimer: TimerUIState? {
        switch keyWindow {
        case .miniTimer: miniTimer
        case .mainWindow: showsTimer ? mainTimer : nil
        case nil: nil
        }
    }

    /// The Mini Timer closed. Its window only hides, with its list as it
    /// was: it opens again at the top, without the filter (timer.md §1.3).
    func miniTimerClosed() async {
        openWindows.closed(.miniTimer)
        miniTimer.list.scrollToTop()
        await miniTimer.list.hideFilter()
    }

    /// A Pomodoro phase ended with the setting on: with no window to show,
    /// the "At launch, show" window opens, and the app comes forward
    /// (timer.md §5.2). Coming forward is last, because opening a window
    /// asks for a cooperative activation, which would replace it.
    func bringForward() {
        guard let router else {
            return
        }
        if !router.hasOpenWindow {
            router.show(settings.launchWindow)
        }
        router.bringForward()
    }

    /// The chip's picker in `view`, with task matching (timer.md §2.3).
    func openChipPicker(in view: TimerUIState) {
        view.pickerModel = ProjectPickerModel(store: store, currentProject: timer.chipProjectID, taskMatching: true)
    }

    /// A picker choice from `view`'s chip or `@` trigger.
    func choose(_ choice: ProjectPickerChoice, in view: TimerUIState) async {
        view.pickerModel = nil
        switch choice {
        case let .project(id):
            await timer.setProject(id)
        case let .create(name):
            view.dialogModel = ProjectDialogModel(store: store, mode: .create, name: name)
        }
    }

    /// The dialog opened from `view`'s picker closed; Create assigns the project.
    func dialogFinished(_ project: Project?, in view: TimerUIState) async {
        view.dialogModel = nil
        if let project {
            await timer.setProject(project.id)
        }
    }

    /// ⌘E in `view`: the running entry from the bar, else the selected row.
    func editEntry(in view: TimerUIState) {
        if view.listFocused, let selection = view.list.selection {
            view.editing = selection
        } else if timer.running != nil {
            editRunningEntry(in: view)
        } else {
            view.editing = view.list.selection
        }
    }

    /// The timer label, ⌘E, or the running row: stores the task typed in the
    /// bar first, so the popover opens on it (timer.md §4).
    @discardableResult
    func editRunningEntry(in view: TimerUIState) -> Task<Void, Never> {
        Task {
            await timer.commitTask()
            if let running = timer.running {
                view.editing = running.id
            }
        }
    }
}
