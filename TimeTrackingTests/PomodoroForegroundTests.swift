// Bringing the app forward at a Pomodoro phase end (timer.md §5.2).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct PomodoroForegroundTests {
    /// A running entry and a Pomodoro in focus.
    private func focusing(foreground: Bool = true) async throws -> TestApp {
        let test = try await TestApp()
        test.app.pomodoro.sleepUntil = { _ in try await Task.sleep(for: .seconds(3600)) }
        test.app.settings.pomodoroForeground = foreground
        await test.app.timer.start()
        test.app.perform(.start)
        return test
    }

    private func endFocus(_ test: TestApp) {
        test.clock.advance(by: 25 * 60)
        test.app.pomodoro.tick()
    }

    @Test("TM-56 a focus or break that runs out brings the app forward, with a window on screen nothing opens")
    func phaseEnds() async throws {
        let test = try await focusing()
        endFocus(test)
        #expect(test.router.calls == [.bringForward])
        test.app.perform(.startBreak)
        test.clock.advance(by: 5 * 60)
        test.app.pomodoro.tick()
        #expect(test.router.calls == [.bringForward, .bringForward])
    }

    @Test("TM-56 with no window on screen the At launch, show window opens", arguments: [
        (LaunchWindow.mainWindow, RecordingRouter.Call.showMainWindow(nil)),
        (LaunchWindow.miniTimer, RecordingRouter.Call.showTimer(focusTask: false)),
    ])
    func noWindow(setting: LaunchWindow, opened: RecordingRouter.Call) async throws {
        let test = try await focusing()
        test.router.hasOpenWindow = false
        test.app.settings.launchWindow = setting
        endFocus(test)
        #expect(test.router.calls == [opened, .bringForward])
    }

    @Test("TM-56 off by default, nothing comes forward, and the notification still posts")
    func off() async throws {
        #expect(AppSettings.ephemeral().pomodoroForeground == false)
        let test = try await focusing(foreground: false)
        test.router.hasOpenWindow = false
        endFocus(test)
        #expect(test.router.calls.isEmpty)
        #expect(test.notifier.posted.last?.category == .pomodoroFocusDone)
    }

    @Test("TM-56 End Focus Now brings nothing forward")
    func endFocusNow() async throws {
        let test = try await focusing()
        test.app.perform(.endFocusNow)
        #expect(test.router.calls.isEmpty)
    }

    @Test("TM-56 the setting persists")
    func persists() {
        let settings = AppSettings.ephemeral()
        settings.pomodoroForeground = true
        #expect(AppSettings(device: settings.device).pomodoroForeground)
    }
}
