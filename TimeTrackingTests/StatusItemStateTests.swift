// The menu bar's Pomodoro lines and items, the Dock icon policy, and
// sleep and wake (spec_menubar.md §2.1, §2.3, §4, §5).

import AppKit
import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct StatusItemStateTests {
    private func item(_ title: String, in entries: [StatusMenuEntry]) -> MenuCommand? {
        for entry in entries {
            if case let .item(itemTitle, _, _, command) = entry, itemTitle == title {
                return command
            }
        }
        return nil
    }

    private func header(_ test: TestApp) -> [String] {
        StatusItemPresenter.header(test.app.statusState, at: test.clock.now)
    }

    /// The Pomodoro group as "Title ⌃⌘P" lines: the items between the
    /// separator after Stop and the next separator.
    private func pomodoroGroup(_ test: TestApp) -> [String] {
        let entries = StatusItemPresenter.menu(test.app.statusState, at: test.clock.now)
        let stop = entries.firstIndex { entry in
            if case let .item(title, _, _, _) = entry {
                return title == "Stop"
            }
            return false
        }
        guard let stop, entries[stop + 1] == .separator else {
            return []
        }
        return entries[(stop + 2)...].prefix { $0 != .separator }.map { entry in
            guard case let .item(title, key, enabled, command) = entry, case .pomodoro = command else {
                return "unexpected \(entry)"
            }
            return [title, key?.display, enabled ? nil : "(disabled)"].compactMap(\.self).joined(separator: " ")
        }
    }

    /// The command of the Pomodoro item `title`.
    private func pomodoroAction(_ title: String, _ test: TestApp) -> PomodoroAction? {
        if case let .pomodoro(action) = item(title, in: StatusItemPresenter.menu(test.app.statusState, at: test.clock.now)) {
            return action
        }
        return nil
    }

    @Test("MB-6 the task line truncates at 60 characters; the Pomodoro line reads Focus ended, Break left, and Break ended")
    func pomodoroHeader() async throws {
        let test = try await TestApp()
        test.app.pomodoro.sleepUntil = { _ in try await Task.sleep(for: .seconds(3600)) }
        test.app.timer.taskText = String(repeating: "a", count: 59) + "bcd"
        await test.app.timer.start()
        let task = try #require(header(test).first)
        #expect(task == String(repeating: "a", count: 59) + "…")
        #expect(task.count == 60)
        let sixty = String(repeating: "b", count: 60)
        #expect(StatusItemPresenter.truncated(sixty, to: StatusItemPresenter.taskLimit) == sixty)
        test.app.perform(.start)
        // Styles: the task as the title, the hollow dot of no project, the
        // start time and the Pomodoro with their symbols.
        let styled = StatusItemPresenter.headerLines(test.app.statusState, at: test.clock.now)
        #expect(styled.map(\.style) == [.title, .primary, .secondary, .primary])
        #expect(styled[1].dot?.isEmpty == true && styled[2].symbol == "clock" && styled[3].symbol == SymbolName.pomodoro)
        // With "Show timer" off the item keeps the countdown.
        test.app.settings.menuBarShowTimer = false
        let content = StatusItemPresenter.content(test.app.statusState, at: test.clock.now)
        #expect(content.title.isEmpty && content.pomodoro == .init(symbol: SymbolName.pomodoro, text: "25:00"))
        test.clock.advance(by: 25 * 60 + 75)
        test.app.pomodoro.tick()
        #expect(header(test).last == "Focus ended · +1:15")
        test.app.perform(.startBreak)
        test.clock.advance(by: 30)
        #expect(header(test).last == "Break · 4:30 left")
        test.clock.advance(by: 270 + 9)
        test.app.pomodoro.tick()
        #expect(header(test).last == "Break ended · +0:09")
    }

    @Test("MB-9 each Pomodoro state's group has exactly the items and keys of 2.3; Start Break in focusOver moves to break")
    func pomodoroGroups() async throws {
        let test = try await TestApp()
        test.app.pomodoro.sleepUntil = { _ in try await Task.sleep(for: .seconds(3600)) }
        #expect(pomodoroGroup(test) == ["Start Pomodoro ⇧⌘P (disabled)"])
        await test.app.timer.start()
        #expect(pomodoroGroup(test) == ["Start Pomodoro ⇧⌘P"])
        try test.app.perform(#require(pomodoroAction("Start Pomodoro", test)))
        #expect(pomodoroGroup(test) == ["End Focus Now ⌃⌘P", "Cancel Pomodoro ⇧⌘P"])
        test.clock.advance(by: 25 * 60)
        test.app.pomodoro.tick()
        #expect(pomodoroGroup(test) == ["Start Break ⌃⌘P", "Skip Break", "Cancel Pomodoro ⇧⌘P"])
        try test.app.perform(#require(pomodoroAction("Start Break", test)))
        #expect(test.app.pomodoro.state == .onBreak(end: test.clock.now + 300))
        #expect(pomodoroGroup(test) == ["End Break Now ⌃⌘P", "Cancel Pomodoro ⇧⌘P"])
        test.clock.advance(by: 300)
        test.app.pomodoro.tick()
        #expect(pomodoroGroup(test) == ["Start Focus ⌃⌘P", "Cancel Pomodoro ⇧⌘P"])
        try test.app.perform(#require(pomodoroAction("Cancel Pomodoro", test)))
        #expect(pomodoroGroup(test) == ["Start Pomodoro ⇧⌘P"])
    }

    @Test("MB-10 Show Dock icon off switches to accessory and keeps the open window key; on restores the regular policy")
    func dockIconPolicy() async throws {
        let test = try await TestApp()
        let application = FakeApplication()
        let window = FakeWindow()
        test.app.settings.showDockIcon = false
        ActivationPolicy.apply(showDockIcon: test.app.settings.showDockIcon, keyWindow: window, application: application)
        #expect(application.policy == .accessory)
        #expect(application.activations == 1)
        #expect(window.madeKey == 1)
        // Already accessory: nothing changes.
        ActivationPolicy.apply(showDockIcon: false, keyWindow: window, application: application)
        #expect(application.activations == 1)
        test.app.settings.showDockIcon = true
        ActivationPolicy.apply(showDockIcon: test.app.settings.showDockIcon, keyWindow: window, application: application)
        #expect(application.policy == .regular)
        #expect(application.activations == 1)
        #expect(window.madeKey == 1)
        // Without the Mini Timer the app's key window stays key; a hidden one is left alone.
        application.keyWindowTarget = window
        ActivationPolicy.apply(showDockIcon: false, keyWindow: nil, application: application)
        #expect(window.madeKey == 2)
        application.policy = .regular
        window.isVisible = false
        ActivationPolicy.apply(showDockIcon: false, keyWindow: window, application: application)
        #expect(application.policy == .accessory)
        #expect(window.madeKey == 2)
        #expect(test.app.settings.device[.showDockIcon] == true)
    }

    @Test("MB-11 sleep cancels the item's tick; the first render after a 2 h sleep includes the 2 h and re-arms the tick")
    func sleepAndWake() async throws {
        let test = try await TestApp()
        _ = try await test.store.start(projectID: nil, task: "", at: test.date("2024-03-14T09:59:17"))
        await test.app.afterChange()
        let controller = StatusItemController(app: test.app)
        defer { controller.remove() }
        let workspace = NotificationCenter()
        let events = SystemEvents(app: test.app, statusItem: controller, workspace: workspace, distributed: NotificationCenter())
        events.start(polling: false)
        #expect(controller.renderedTitle == "0:00")
        #expect(try controller.nextTickDate == test.date("2024-03-14T10:00:17"))
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(controller.nextTickDate == nil)
        test.clock.advance(by: 7200)
        #expect(controller.renderedTitle == "0:00")
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(controller.renderedTitle == "2:00")
        #expect(try controller.nextTickDate == test.date("2024-03-14T12:00:17"))
    }

    @Test("MB-11 a Pomodoro ticks every second on its phase end's fraction of a second")
    func pomodoroTick() async throws {
        let test = try await TestApp()
        test.app.pomodoro.sleepUntil = { _ in try await Task.sleep(for: .seconds(3600)) }
        test.clock.advance(by: 0.25)
        await test.app.timer.start()
        test.app.perform(.start)
        let end = try #require(test.app.pomodoro.state.phaseEnd)
        #expect(try end == test.date("2024-03-14T10:25") + 0.25)
        test.clock.advance(by: 0.5)
        #expect(try StatusItemPresenter.nextTick(test.app.statusState, after: test.clock.now, menuOpen: false)
            == test.date("2024-03-14T10:00:01") + 0.25)
    }
}

/// Records what `ActivationPolicy` does to the application.
@MainActor
final class FakeApplication: ActivationTarget {
    var policy: NSApplication.ActivationPolicy = .regular
    var activations = 0
    var keyWindowTarget: (any KeyWindowTarget)?

    func activationPolicy() -> NSApplication.ActivationPolicy {
        policy
    }

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        policy = activationPolicy
        return true
    }

    func activate() {
        activations += 1
    }
}

/// Counts how often it was made key.
@MainActor
final class FakeWindow: KeyWindowTarget {
    var isVisible = true
    var madeKey = 0

    func makeKeyAndOrderFront(_: Any?) {
        madeKey += 1
    }
}
