// The Pomodoro state machine (spec_timer_window.md §5.3).

import Foundation
import Testing
import TimeTrackingCore

struct PomodoroTests {
    let start = Date(timeIntervalSinceReferenceDate: 750_000_000)
    let focus: TimeInterval = 25 * 60
    let pause: TimeInterval = 5 * 60

    @Test("TW-23 a Pomodoro counts down, then shows +0:00 counting up at focusEnd with Focus done and Start Break")
    func countdownAndOvertime() {
        var pomodoro = Pomodoro()
        #expect(pomodoro.buttonTitle(at: start) == "Pomodoro")
        pomodoro.perform(.start, at: start, focus: focus, break: pause, isRunning: true)
        #expect(pomodoro.countdownText(at: start) == "25:00")
        #expect(pomodoro.buttonTitle(at: start + 1) == "Focus 24:59")
        #expect(pomodoro.advance(to: start + focus - 1).isEmpty)
        #expect(pomodoro.advance(to: start + focus) == [.notifyFocusDone])
        #expect(pomodoro.state == .focusOver(end: start + focus))
        #expect(pomodoro.countdownText(at: start + focus) == "+0:00")
        #expect(pomodoro.countdownText(at: start + focus + 80) == "+1:20")
        #expect(pomodoro.buttonTitle(at: start + focus + 80) == "Focus +1:20")
        #expect(pomodoro.confirmationTitle == "Start Break")
        // An hour or more counts down as h:mm:ss.
        var long = Pomodoro()
        long.perform(.start, at: start, focus: 90 * 60, break: pause, isRunning: true)
        #expect(long.countdownText(at: start) == "1:30:00")
    }

    @Test("TW-25 every transition of the state machine holds; turning off removes pending notifications")
    func transitions() {
        var pomodoro = Pomodoro()
        // Start needs a running entry.
        #expect(pomodoro.perform(.start, at: start, focus: focus, break: pause, isRunning: false).isEmpty)
        #expect(pomodoro.state == .off)
        #expect(pomodoro.actions(isRunning: false).isEmpty)
        #expect(pomodoro.actions(isRunning: true) == [.start])

        pomodoro.perform(.start, at: start, focus: focus, break: pause, isRunning: true)
        #expect(pomodoro.state == .focus(end: start + focus))
        #expect(pomodoro.actions(isRunning: true) == [.endFocusNow, .cancel])

        let early = start + 600
        pomodoro.perform(.endFocusNow, at: early, focus: focus, break: pause, isRunning: true)
        #expect(pomodoro.state == .onBreak(end: early + pause))
        #expect(pomodoro.actions(isRunning: true) == [.endBreakNow, .cancel])

        pomodoro.perform(.endBreakNow, at: early + 60, focus: focus, break: pause, isRunning: true)
        #expect(pomodoro.state == .focus(end: early + 60 + focus))

        let focusEnd = early + 60 + focus
        #expect(pomodoro.advance(to: focusEnd) == [.notifyFocusDone])
        #expect(pomodoro.actions(isRunning: true) == [.startBreak, .skipBreak, .cancel])
        pomodoro.perform(.skipBreak, at: focusEnd + 10, focus: focus, break: pause, isRunning: true)
        #expect(pomodoro.state == .focus(end: focusEnd + 10 + focus))

        let secondEnd = focusEnd + 10 + focus
        pomodoro.advance(to: secondEnd)
        pomodoro.perform(.startBreak, at: secondEnd + 5, focus: focus, break: pause, isRunning: true)
        #expect(pomodoro.state == .onBreak(end: secondEnd + 5 + pause))
        let breakEnd = secondEnd + 5 + pause
        #expect(pomodoro.advance(to: breakEnd) == [.notifyBreakOver])
        #expect(pomodoro.state == .breakOver(end: breakEnd))
        #expect(pomodoro.confirmationTitle == "Start Focus")
        #expect(pomodoro.actions(isRunning: true) == [.startFocus, .cancel])
        #expect(pomodoro.nextPhaseAction == .startFocus)
        pomodoro.perform(.startFocus, at: breakEnd + 1, focus: focus, break: pause, isRunning: true)
        #expect(pomodoro.state == .focus(end: breakEnd + 1 + focus))

        // Cancel, stop, and quit turn it off; off removes notifications.
        var cancelled = pomodoro
        #expect(cancelled.perform(.cancel, at: breakEnd + 2, focus: focus, break: pause, isRunning: true) == [.removeNotifications])
        #expect(cancelled.state == .off)
        var stopped = pomodoro
        #expect(stopped.runningEntryEnded() == [.removeNotifications])
        #expect(stopped.state == .off)
        var quit = pomodoro
        quit.reset()
        #expect(quit.state == .off)
        // A new or continued entry changes nothing: the owner does not call the machine.
        var off = Pomodoro()
        #expect(off.runningEntryEnded().isEmpty)
    }

    @Test("TW-26 a focus duration change during focus keeps focusEnd; waking after focusEnd lands in focusOver and notifies")
    func durationChangeAndWake() {
        var pomodoro = Pomodoro()
        pomodoro.perform(.start, at: start, focus: focus, break: pause, isRunning: true)
        // The new duration is passed only at the next phase start.
        #expect(pomodoro.state.phaseEnd == start + focus)
        // The Mac sleeps through focusEnd and wakes 10 minutes later.
        let wake = start + focus + 600
        #expect(pomodoro.advance(to: wake) == [.notifyFocusDone])
        #expect(pomodoro.state == .focusOver(end: start + focus))
        #expect(pomodoro.countdownText(at: wake) == "+10:00")
        pomodoro.perform(.startBreak, at: wake, focus: 50 * 60, break: 10 * 60, isRunning: true)
        #expect(pomodoro.state == .onBreak(end: wake + 600))
    }
}
