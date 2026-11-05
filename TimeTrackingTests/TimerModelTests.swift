// The running-entry bar and its commands (spec_timer.md §2).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct TimerModelTests {
    @Test("MB-20 the menu's Last line names an entry stopped today that started before Midnight")
    func lastStoppedAcrossMidnight() async throws {
        let test = try await TestApp()
        try await test.store.set(.midnightHour, 4)
        _ = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Dawn",
            start: TestApp.date("2024-03-14T03:00"),
            end: TestApp.date("2024-03-14T05:00")
        ))
        await test.app.timer.refresh()
        #expect(test.app.timer.lastStoppedToday?.task == "Dawn")
    }

    @Test("TM-6 start, New, stop, continue, and discard; New and Continue stop the running entry at the same instant")
    func actions() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Noise Model"])
        let timer = test.app.timer
        // Start with the field's task and the chip's project.
        timer.taskText = "Clarify noise model"
        await timer.setProject(projects[0].id)
        await timer.start()
        let first = try #require(timer.running)
        #expect(first.task == "Clarify noise model")
        #expect(first.projectID == projects[0].id)
        #expect(timer.chipLabel.name == "Noise Model")
        // ⌘N stops it at the same instant and starts an empty entry.
        test.clock.advance(by: 600)
        await test.app.newEntry()
        let second = try #require(timer.running)
        #expect(second.task.isEmpty && second.projectID == nil)
        #expect(try await test.store.entry(first.id)?.end == second.start)
        #expect(test.router.calls.last == .showTimer(focusTask: true))
        // Stop: the field and chip go blank.
        timer.taskText = "Write"
        await timer.commitTask()
        test.clock.advance(by: 60)
        await timer.stop()
        #expect(timer.running == nil)
        #expect(timer.taskText.isEmpty)
        #expect(timer.chipProjectID == nil)
        // ⌘O without selection continues the most recent other entry.
        test.clock.advance(by: 60)
        await test.app.continueCommand(timerKey: true)
        #expect(timer.running?.task == "Write")
        let third = try #require(timer.running)
        test.clock.advance(by: 60)
        await test.app.continueCommand(timerKey: false)
        // The most recent entry other than the running one is "Write" (second).
        #expect(try await test.store.entry(third.id)?.end == timer.running?.start)
        #expect(timer.running?.task == "Write")
        // Discard deletes the running entry (⌥-click skips the alert).
        let running = try #require(timer.running)
        await timer.requestDiscard(skipAlert: true)
        #expect(try await test.store.entry(running.id) == nil)
        #expect(timer.running == nil)
    }

    @Test("TM-7 a task edit of the running entry is stored after the 500 ms debounce; Escape reverts it")
    func taskDebounce() async throws {
        let test = try await TestApp()
        let timer = test.app.timer
        #expect(TimerModel.taskCommitDelay == .milliseconds(500))
        var waited: [Duration] = []
        timer.debounce = { @MainActor duration in waited.append(duration) }
        await timer.start()
        timer.taskText = "Draft intro"
        timer.taskTextChanged()
        await timer.pendingTaskCommit?.value
        #expect(waited == [.milliseconds(500)])
        #expect(try await test.store.runningEntry()?.task == "Draft intro")
        // Escape reverts an unsaved edit; a second Escape leaves the field.
        timer.debounce = { _ in try await Task.sleep(for: .seconds(3600)) }
        timer.taskText = "Draft intro and methods"
        timer.taskTextChanged()
        #expect(timer.revertTask())
        #expect(timer.taskText == "Draft intro")
        #expect(!timer.revertTask())
        #expect(try await test.store.runningEntry()?.task == "Draft intro")
    }

    @Test("TM-41 a task typed within the debounce stays on the running entry when New, Continue, or Start Timer replaces it")
    func taskTypedBeforeReplacing() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Noise Model"])
        let timer = test.app.timer
        timer.debounce = { _ in try await Task.sleep(for: .seconds(3600)) }
        await timer.start()
        let first = try #require(timer.running)
        timer.taskText = "Draft intro"
        timer.taskTextChanged()
        test.clock.advance(by: 60)
        await test.app.newEntry()
        #expect(try await test.store.entry(first.id)?.task == "Draft intro")
        #expect(timer.taskText.isEmpty)

        let second = try #require(timer.running)
        timer.taskText = "Read paper"
        timer.taskTextChanged()
        test.clock.advance(by: 60)
        await timer.continueEntry(first.id)
        #expect(try await test.store.entry(second.id)?.task == "Read paper")
        #expect(timer.taskText == "Draft intro")

        let third = try #require(timer.running)
        timer.taskText = "Draft intro and methods"
        timer.taskTextChanged()
        test.clock.advance(by: 60)
        await timer.startEmpty(on: projects[0].id)
        #expect(try await test.store.entry(third.id)?.task == "Draft intro and methods")
        #expect(timer.running?.projectID == projects[0].id)
    }

    @Test("TM-12 discard asks first and ⌘Z restores; an archived project's entry continues only after Restore Project and Continue")
    func discardAndArchived() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Old"])
        let timer = test.app.timer
        await timer.start()
        test.clock.advance(by: 754)
        let running = try #require(timer.running)
        await timer.requestDiscard(skipAlert: false)
        #expect(timer.alert == .discard(elapsed: "0:12:34"))
        #expect(timer.alert?.message == "Discard the running entry? 0:12:34 will be lost.")
        #expect(timer.running?.id == running.id)
        timer.alert = nil
        await timer.discard()
        #expect(timer.running == nil)
        #expect(timer.taskText.isEmpty)
        #expect(timer.chipProjectID == nil)
        await test.undoLast()
        #expect(timer.running?.id == running.id)
        await timer.stop()

        let old = try await test.entry("Legacy", projects[0], from: "08:00", to: "08:30")
        try await test.store.archive(projects[0].id)
        await timer.continueEntry(old.id)
        #expect(timer.alert == .restoreProject(old.id, projectName: "Old"))
        #expect(timer.running == nil)
        timer.alert = nil
        await timer.restoreProjectAndContinue(old.id)
        #expect(timer.running?.task == "Legacy")
        #expect(try await test.store.project(projects[0].id)?.isArchived == false)
    }

    @Test("TM-13 TM-14 the label counts from 23:10 and reads 0:55:00 at 00:05; today's total rises per second")
    func labelAndTotal() async throws {
        let test = try await TestApp(now: "2024-03-13T23:30")
        let timer = test.app.timer
        _ = try await test.store.start(projectID: nil, task: "Night", at: test.date("2024-03-13T23:10"))
        try test.clock.set(test.date("2024-03-14T00:05"))
        await test.app.afterChange()
        #expect(timer.timerText(at: test.clock.now) == "0:55:00")
        // The list shows the earlier piece under its own day.
        let days = test.app.activeTimer.list.days
        #expect(days.map(\.day) == [TrackingDay(year: 2024, month: 3, day: 14), TrackingDay(year: 2024, month: 3, day: 13)])
        #expect(days[1].rows.first?.entry.task == "Night")
        // Today's total includes the running piece and ticks.
        #expect(days[0].totalSeconds(at: test.clock.now) == 300)
        test.clock.advance(by: 1)
        #expect(days[0].totalSeconds(at: test.clock.now) == 301)
        #expect(timer.timerText(at: test.clock.now) == "0:55:01")
    }

    @Test("TM-5 a login-item launch reopens the windows open at the last quit, none without any; quitting leaves the entry running")
    func loginItemAndQuit() async throws {
        let test = try await TestApp()
        let record = test.app.openWindows
        // Kept current as the windows open and close.
        test.app.mainWindowOpened()
        record.opened(.miniTimer)
        #expect(record.windows == [.mainWindow, .miniTimer])
        test.app.mainWindowClosed()
        #expect(record.windows == [.miniTimer])
        // The closes while the app quits leave the record alone.
        record.freeze()
        record.closed(.miniTimer)
        #expect(record.windows == [.miniTimer])
        // The next launch takes the record and starts it empty.
        let next = OpenWindowsRecord(device: test.app.settings.device)
        let atQuit = next.takeOpenAtQuit()
        #expect(atQuit == [.miniTimer])
        #expect(next.windows.isEmpty)
        #expect(LaunchWindow.opened(setting: .mainWindow, launchedAsLoginItem: true, openAtQuit: atQuit) == [.miniTimer])
        #expect(LaunchWindow.opened(setting: .mainWindow, launchedAsLoginItem: true, openAtQuit: []).isEmpty)
        let both = LaunchWindow.opened(setting: .miniTimer, launchedAsLoginItem: true, openAtQuit: [.miniTimer, .mainWindow])
        #expect(both == [.mainWindow, .miniTimer])
        await test.app.timer.start()
        test.app.perform(.start)
        // Quit: the Pomodoro ends, the entry keeps running.
        test.app.pomodoro.reset()
        test.app.stop()
        #expect(test.app.pomodoro.state == .off)
        #expect(try await test.store.runningEntry() != nil)
    }

    @Test("TM-38 At launch, show: the Mini Timer instead of the main window at a launch other than a login launch, whatever was open")
    func launchWindowSetting() {
        let settings = AppSettings.ephemeral()
        #expect(settings.launchWindow == .mainWindow)
        settings.launchWindow = .miniTimer
        #expect(AppSettings(device: settings.device).launchWindow == .miniTimer)
        #expect(LaunchWindow.opened(setting: .miniTimer, launchedAsLoginItem: false, openAtQuit: []) == [.miniTimer])
        #expect(LaunchWindow.opened(setting: .miniTimer, launchedAsLoginItem: false, openAtQuit: [.mainWindow]) == [.miniTimer])
        #expect(LaunchWindow.opened(setting: .mainWindow, launchedAsLoginItem: false, openAtQuit: [.miniTimer]) == [.mainWindow])
    }

    @Test("TM-31 the continue/stop shortcut stops or continues; Show the Mini Timer when an entry starts shows it")
    func continueStopShortcut() async throws {
        let test = try await TestApp()
        try await test.entry("Review", from: "08:00", to: "08:30")
        await test.app.continueOrStop()
        #expect(test.app.timer.running?.task == "Review")
        // Without the focus setting the window is not shown.
        #expect(test.router.calls.isEmpty)
        await test.app.continueOrStop()
        #expect(test.app.timer.running == nil)
        test.app.settings.focusOnStart = true
        await test.app.continueOrStop()
        #expect(test.router.calls == [.showTimer(focusTask: true)])
    }
}
