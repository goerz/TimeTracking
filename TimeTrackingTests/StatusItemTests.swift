// The menu bar item, its menu, and the Dock menu (spec_menubar.md).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct StatusItemTests {
    private func content(_ test: TestApp) -> StatusItemContent {
        StatusItemPresenter.content(test.app.statusState, at: test.clock.now)
    }

    private func titles(_ entries: [StatusMenuEntry]) -> [String] {
        entries.compactMap { entry in
            if case let .item(title, _, _, _) = entry {
                return title
            }
            return nil
        }
    }

    /// A menu item's key, enablement, and command.
    private struct Item {
        var key: MenuKey?
        var enabled: Bool
        var command: MenuCommand
    }

    private func item(_ title: String, in entries: [StatusMenuEntry]) -> Item? {
        for entry in entries {
            if case let .item(itemTitle, key, enabled, command) = entry, itemTitle == title {
                return Item(key: key, enabled: enabled, command: command)
            }
        }
        return nil
    }

    @Test("MB-1 with nothing running the title is empty, the image stopwatch, and no tick is scheduled")
    func idle() async throws {
        let test = try await TestApp()
        let content = content(test)
        #expect(content.title.isEmpty)
        #expect(content.dial == nil)
        #expect(content.accessibilityLabel == "Not tracking")
        #expect(StatusItemPresenter.nextTick(test.app.statusState, after: test.clock.now, menuOpen: false) == nil)
    }

    @Test("MB-2 at T + 4 min 33 s the title is 0:04 or 0:04:33 with seconds; at T + 25 h it is 25:00")
    func elapsed() async throws {
        let test = try await TestApp(now: "2024-03-13T08:00")
        await test.app.timer.start()
        test.clock.advance(by: 273)
        #expect(content(test).title == "0:04")
        #expect(content(test).dial == 4.0 / 60)
        test.app.settings.menuBarShowSeconds = true
        #expect(content(test).title == "0:04:33")
        test.app.settings.menuBarShowSeconds = false
        try test.clock.set(test.date("2024-03-14T09:00"))
        try await test.store.checkInvariants()
        await test.app.afterChange()
        #expect(content(test).title == "25:00")
        #expect(content(test).accessibilityLabel == "Tracking, 25 hours")
    }

    @Test("MB-3 with an entry running since 23:10, at 00:05 the title is 0:55")
    func midnight() async throws {
        let test = try await TestApp(now: "2024-03-13T23:20")
        _ = try await test.store.start(projectID: nil, task: "", at: test.date("2024-03-13T23:10"))
        try test.clock.set(test.date("2024-03-14T00:05"))
        try await test.store.checkInvariants()
        await test.app.afterChange()
        #expect(content(test).title == "0:55")
    }

    @Test("MB-4 Show project truncates at 24 characters with an ellipsis; with timer and project off the title is empty")
    func project() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["A project name with thirty ch"])
        test.app.timer.taskText = "Task"
        await test.app.timer.setProject(projects[0].id)
        await test.app.timer.start()
        test.clock.advance(by: 2400)
        test.app.settings.menuBarShowProject = true
        let title = content(test).title
        #expect(title.hasPrefix("0:40 · "))
        let name = title.dropFirst("0:40 · ".count)
        #expect(name.count == 24 && name.hasSuffix("…"))
        #expect(content(test).accessibilityLabel == "Tracking, 40 minutes, A project name with thirty ch")
        test.app.settings.menuBarShowTimer = false
        #expect(content(test).title == String(name))
        test.app.settings.menuBarShowProject = false
        #expect(content(test).title.isEmpty)
        #expect(content(test).dial == 40.0 / 60)
    }

    @Test("MB-5 MB-9 a 25-minute focus keeps the elapsed title and adds timer 25:00; 2 min past focusEnd +2:00; Start Break moves to break")
    func pomodoro() async throws {
        let test = try await TestApp()
        test.app.pomodoro.sleepUntil = { _ in try await Task.sleep(for: .seconds(3600)) }
        await test.app.timer.start()
        // off: Start Pomodoro, disabled while nothing runs.
        #expect(StatusItemPresenter.pomodoroItems(Pomodoro(), isRunning: false) == [
            .item(title: "Start Pomodoro", key: .command("p", .shift), enabled: false, command: .pomodoro(.start)),
        ])
        test.app.perform(.start)
        #expect(content(test).title == "0:00")
        #expect(content(test).dial == 0)
        #expect(content(test).pomodoro == .init(symbol: AppSymbol.pomodoro, text: "25:00"))
        #expect(content(test).visibleText == "0:00 25:00")
        #expect(content(test).accessibilityLabel == "Tracking, 0 minutes, Pomodoro focus, 25 minutes left")
        var menu = StatusItemPresenter.menu(test.app.statusState, at: test.clock.now)
        #expect(titles(menu).contains("End Focus Now") && titles(menu).contains("Cancel Pomodoro"))
        #expect(item("End Focus Now", in: menu)?.key == .command("p", .control))
        test.clock.advance(by: 27 * 60)
        test.app.pomodoro.tick()
        #expect(content(test).title == "0:27")
        #expect(content(test).pomodoro == .init(symbol: AppSymbol.pomodoro, text: "+2:00"))
        menu = StatusItemPresenter.menu(test.app.statusState, at: test.clock.now)
        let pomodoroTitles = titles(menu).filter { ["Start Break", "Skip Break", "Cancel Pomodoro", "End Focus Now"].contains($0) }
        #expect(pomodoroTitles == ["Start Break", "Skip Break", "Cancel Pomodoro"])
        #expect(item("Skip Break", in: menu)?.key == nil)
        test.app.perform(.startBreak)
        #expect(test.app.pomodoro.state == .onBreak(end: test.clock.now + 300))
        #expect(content(test).pomodoro == .init(symbol: "cup.and.saucer", text: "5:00"))
        menu = StatusItemPresenter.menu(test.app.statusState, at: test.clock.now)
        #expect(titles(menu).contains("End Break Now"))
        test.clock.advance(by: 300)
        test.app.pomodoro.tick()
        menu = StatusItemPresenter.menu(test.app.statusState, at: test.clock.now)
        #expect(titles(menu).contains("Start Focus") && !titles(menu).contains("Skip Break"))
    }

    @Test("MB-6 header lines for a running entry, no entry, and a Pomodoro")
    func header() async throws {
        let test = try await TestApp(now: "2024-03-14T13:38")
        let projects = try await test.projects(["Noise Model"])
        test.app.timer.taskText = "Clarify noise model"
        await test.app.timer.setProject(projects[0].id)
        await test.app.timer.start()
        test.clock.advance(by: 2400)
        let started = try LocalDateText.time(test.date("2024-03-14T13:38"))
        #expect(StatusItemPresenter.header(test.app.statusState, at: test.clock.now) == [
            "Clarify noise model", "Noise Model · University", "Started \(started) · 0:40 elapsed",
        ])
        test.app.perform(.start)
        test.clock.advance(by: 26)
        #expect(StatusItemPresenter.header(test.app.statusState, at: test.clock.now).last == "Focus · 24:34 left")
        await test.app.stopEntry()
        let stopped = LocalDateText.time(test.clock.now)
        #expect(StatusItemPresenter.header(test.app.statusState, at: test.clock.now) == [
            "Not tracking", "Last: Clarify noise model, stopped \(stopped)",
        ])
        // A chain from yesterday says so.
        let late = try await TestApp(now: "2024-03-13T23:20")
        _ = try await late.store.start(projectID: nil, task: "", at: late.date("2024-03-13T23:10"))
        try late.clock.set(late.date("2024-03-14T00:15"))
        try await late.store.checkInvariants()
        await late.app.afterChange()
        let lines = StatusItemPresenter.header(late.app.statusState, at: late.clock.now)
        #expect(lines[0] == "No task" && lines[1] == "No project")
        #expect(try lines[2] == "Started \(LocalDateText.time(late.date("2024-03-13T23:10"))) yesterday · 1:05 elapsed")
    }

    @Test("MB-7 enablement and actions: Continue does not show the window, New focuses the task field, Stop stops")
    func commands() async throws {
        let test = try await TestApp()
        var menu = StatusItemPresenter.menu(test.app.statusState, at: test.clock.now)
        #expect(item("New", in: menu)?.enabled == true)
        #expect(item("Continue", in: menu)?.enabled == false)
        #expect(item("Stop", in: menu)?.enabled == false)
        #expect(item("Open Planner", in: menu)?.key == .command("p", .option))
        #expect(item("Settings…", in: menu)?.key == .command(","))
        #expect(item("Quit TimeTracking", in: menu)?.key == .command("q") || titles(menu).last?.hasPrefix("Quit ") == true)
        try await test.entry("Review", from: "08:00", to: "08:30")
        menu = StatusItemPresenter.menu(test.app.statusState, at: test.clock.now)
        #expect(item("Continue", in: menu)?.enabled == true)
        await test.app.continueLatest()
        #expect(test.app.timer.running?.task == "Review")
        #expect(test.router.calls.isEmpty)
        menu = StatusItemPresenter.menu(test.app.statusState, at: test.clock.now)
        #expect(item("Stop", in: menu)?.enabled == true)
        await test.app.stopEntry()
        #expect(test.app.timer.running == nil)
        let focus = test.app.timer.focusTaskFieldRequest
        await test.app.newEntry()
        #expect(test.app.timer.focusTaskFieldRequest == focus + 1)
        #expect(test.router.calls == [.showTimer(focusTask: true)])
    }

    @Test("MB-8 TW-4 Show Timer Window displays the recorded show/hide shortcut and none when cleared")
    func showHideKey() async throws {
        let test = try await TestApp()
        test.app.shortcutSource = { .command("r", .option) }
        test.app.refreshShortcutDisplay()
        var menu = StatusItemPresenter.menu(test.app.statusState, at: test.clock.now)
        #expect(item("Show Timer Window", in: menu)?.key?.display == "⌥⌘R")
        test.app.shortcutSource = { nil }
        test.app.refreshShortcutDisplay()
        menu = StatusItemPresenter.menu(test.app.statusState, at: test.clock.now)
        #expect(item("Show Timer Window", in: menu)?.key == nil)
        #expect(item("Show Timer Window", in: menu)?.command == .showTimer)
    }

    @Test("MB-10 the Dock menu has New Entry, Continue Latest, and Stop with the enablement of the menu")
    func dockMenu() async throws {
        let test = try await TestApp()
        var dock = StatusItemPresenter.dockMenu(test.app.statusState)
        #expect(titles(dock) == ["New Entry", "Continue Latest", "Stop"])
        #expect(item("Continue Latest", in: dock)?.enabled == false)
        #expect(item("Stop", in: dock)?.enabled == false)
        try await test.entry("Review", from: "08:00", to: "08:30")
        await test.app.continueLatest()
        dock = StatusItemPresenter.dockMenu(test.app.statusState)
        #expect(item("Continue Latest", in: dock)?.enabled == true)
        #expect(item("Stop", in: dock)?.enabled == true)
        #expect(test.app.settings.showDockIcon)
    }

    @Test("MB-11 ticks: 60 s at the chain start's second, 1 s with seconds or a Pomodoro; after a 2 h sleep the render includes it")
    func ticks() async throws {
        let test = try await TestApp()
        _ = try await test.store.start(projectID: nil, task: "", at: test.date("2024-03-14T09:59:17"))
        await test.app.afterChange()
        var state = test.app.statusState
        let now = test.clock.now
        #expect(try StatusItemPresenter.nextTick(state, after: now, menuOpen: false) == (test.date("2024-03-14T10:00:17")))
        #expect(StatusItemPresenter.nextTick(state, after: now, menuOpen: true) == now + 1)
        test.app.settings.menuBarShowSeconds = true
        state = test.app.statusState
        #expect(StatusItemPresenter.nextTick(state, after: now, menuOpen: false) == now + 1)
        test.app.settings.menuBarShowSeconds = false
        test.clock.advance(by: 7200)
        #expect(content(test).title == "2:00")
    }

    @Test("MB-12 a running-entry change from sync updates the item without a tick")
    func syncChange() async throws {
        let test = try await TestApp()
        let revision = test.app.revision
        // Another device's start arrives as a store change.
        _ = try await test.store.start(projectID: nil, task: "From iPhone", at: test.clock.now - 60)
        await test.app.storeChanged(.runningEntry(nil))
        #expect(test.app.revision > revision)
        #expect(content(test).dial == 1.0 / 60)
        #expect(content(test).title == "0:01")
    }

    @Test("MB-14 the badge and warning lines appear for a stopped tracker after 2 min awake; Open Tracker Settings opens the pane")
    func trackerWarning() async throws {
        let tick = try TestApp.date("2024-03-14T09:57")
        let state = TrackerState(
            device: "mac",
            openBlock: nil,
            primary: nil,
            presence: TrackerPresence(state: .active, since: tick),
            health: TrackerHealth(lastTick: tick, version: "1.0 (1)", sources: [])
        )
        let test = try await TestApp(trackerState: state)
        test.agent.registration = .enabled
        await test.app.tracker.becamePresent(at: test.clock.now - 600)
        #expect(test.app.tracker.warningActive)
        #expect(content(test).badge)
        #expect(content(test).accessibilityLabel == "Not tracking, tracker not running")
        let menu = StatusItemPresenter.menu(test.app.statusState, at: test.clock.now)
        #expect(menu.first == .header(MenuHeaderLine(
            "Tracker not running since \(LocalDateText.time(tick))",
            style: .warning,
            symbol: "exclamationmark.triangle"
        )))
        #expect(item("Open Tracker Settings…", in: menu)?.command == .openTrackerSettings)
        // Awake only one minute: no warning.
        await test.app.tracker.becamePresent(at: test.clock.now - 60)
        #expect(!test.app.tracker.warningActive)
        // Not enabled: no warning.
        test.agent.registration = .notRegistered
        await test.app.tracker.becamePresent(at: test.clock.now - 600)
        #expect(!test.app.tracker.warningActive)
    }
}
