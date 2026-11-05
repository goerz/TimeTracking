// The status item's Pomodoro display setting and the open menu's refresh
// (menubar.md §1.1, §2.1, §6).

import AppKit
import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct StatusItemDisplayTests {
    private func content(_ test: TestApp) -> StatusItemContent {
        StatusItemPresenter.content(test.app.statusState, at: test.clock.now)
    }

    @Test("MB-15 during a focus, Countdown only drops the elapsed time and Timer only drops the segment")
    func pomodoroDisplay() async throws {
        let test = try await TestApp()
        test.app.pomodoro.sleepUntil = { _ in try await Task.sleep(for: .seconds(3600)) }
        let projects = try await test.projects(["Thesis"])
        await test.app.timer.setProject(projects[0].id)
        await test.app.timer.start()
        test.clock.advance(by: 2400)
        test.app.perform(.start)
        test.app.settings.menuBarPomodoroDisplay = .countdown
        #expect(content(test).title.isEmpty)
        #expect(content(test).pomodoro == .init(symbol: SymbolName.pomodoro, text: "25:00"))
        #expect(content(test).accessibilityLabel == "Tracking, 40 minutes, Pomodoro focus, 25 minutes left")
        test.app.settings.menuBarShowProject = true
        #expect(content(test).title == "Thesis")
        test.app.settings.menuBarShowProject = false
        test.app.settings.menuBarPomodoroDisplay = .timer
        #expect(content(test).title == "0:40")
        #expect(content(test).pomodoro == nil)
        #expect(content(test).accessibilityLabel == "Tracking, 40 minutes, Pomodoro focus, 25 minutes left")
        test.app.perform(.cancel)
        for display in [MenuBarPomodoroDisplay.countdown, .timer] {
            test.app.settings.menuBarPomodoroDisplay = display
            #expect(content(test).title == "0:40")
            #expect(content(test).pomodoro == nil)
        }
    }

    @Test("MB-16 the per-second refresh of an unchanged menu finds the same shape, so the open menu keeps its items")
    func menuShape() async throws {
        let test = try await TestApp()
        await test.app.timer.start()
        test.app.perform(.start)
        let shape = { StatusMenuRow.rows(StatusItemPresenter.menu(test.app.statusState, at: test.clock.now)).map(\.shape) }
        let first = shape()
        // Fresh entries each time: key modifier sets, whose iteration order
        // varies between instances, must not make the shapes differ.
        for _ in 0 ..< 20 {
            test.clock.advance(by: 1)
            #expect(shape() == first)
        }
        test.app.perform(.cancel)
        #expect(shape() != first)
    }

    @Test("MB-17 the dial: empty when idle, a minute hand while tracking, the Pomodoro phase progress, minute ticks without text")
    func dial() async throws {
        let test = try await TestApp()
        test.app.pomodoro.sleepUntil = { _ in try await Task.sleep(for: .seconds(3600)) }
        #expect(content(test).dial == nil)
        await test.app.timer.start()
        test.clock.advance(by: 95 * 60 + 20)
        #expect(content(test).dial == 35.0 / 60)
        test.app.settings.menuBarShowTimer = false
        let tick = StatusItemPresenter.nextTick(test.app.statusState, after: test.clock.now, menuOpen: false)
        #expect(tick == test.clock.now + 40)
        test.app.perform(.start)
        test.clock.advance(by: 10 * 60)
        #expect(abs((content(test).dial ?? 0) - 0.4) < 1e-9)
        test.clock.advance(by: 16 * 60)
        test.app.pomodoro.tick()
        #expect(content(test).dial == 1)
        test.app.perform(.cancel)
        // 121 minutes into the entry.
        #expect(content(test).dial == 1.0 / 60)
        let image = StatusItemController.dialImage(0.5, badge: false)
        #expect(image.isTemplate && image.size == NSSize(width: 16, height: 16))
        #expect(StatusItemController.dialImage(nil, badge: true).size.width == 18)
    }

    @Test("MB-18 the countdown keeps its width: a focus under ten minutes is led by a figure space")
    func countdownWidth() async throws {
        let test = try await TestApp()
        test.app.pomodoro.sleepUntil = { _ in try await Task.sleep(for: .seconds(3600)) }
        await test.app.timer.start()
        test.app.perform(.start)
        #expect(content(test).pomodoro?.text == "25:00")
        test.clock.advance(by: 15 * 60 + 1)
        #expect(content(test).pomodoro?.text == "\u{2007}9:59")
        #expect(StatusItemPresenter.paddedCountdown(299, phaseSeconds: 300) == "4:59")
        #expect(StatusItemPresenter.paddedCountdown(59, phaseSeconds: 90 * 60) == "\u{2007}0:59")
    }
}
