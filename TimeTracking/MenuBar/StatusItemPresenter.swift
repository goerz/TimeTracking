// StatusItemPresenter: what the menu bar item and its menu show
// (spec_menubar.md §1, §2, §4, §5).

import Foundation
import TimeTrackingCore

/// The status item's presentation; pure, so tests drive it with any clock.
enum StatusItemPresenter {
    /// Maximum length of the project name, ellipsis included.
    static let projectLimit = 24
    /// Maximum length of the task header line.
    static let taskLimit = 60

    static func content(_ state: StatusItemState, at now: Date) -> StatusItemContent {
        var dial: Double?
        var title = ""
        var spoken = state.running == nil ? "Not tracking" : "Tracking"
        let pomodoroRemaining = state.pomodoro.state.isOn ? state.pomodoro.remaining(at: now) : nil
        // "Countdown only" hides the elapsed time while a countdown shows.
        let hidesElapsed = pomodoroRemaining != nil && state.pomodoroDisplay == .countdown
        if let chainStart = state.chainStart, state.running != nil {
            let elapsed = max(0, Int(now.timeIntervalSince(chainStart)))
            // A minute hand: one turn per hour of the chain.
            dial = Double(elapsed / 60 % 60) / 60
            if state.showTimer, !hidesElapsed {
                title = state.showSeconds ? DurationText.clock(elapsed) : DurationText.hoursMinutes(elapsed)
            }
            spoken = "Tracking, \(spokenDuration(elapsed, seconds: state.showSeconds))"
        }
        if state.showProject, state.running != nil, !state.label.isNone {
            let name = truncated(state.label.name, to: projectLimit)
            title = title.isEmpty ? name : "\(title) · \(name)"
            spoken += ", \(state.label.name)"
        }
        // The countdown is secondary: it follows the title, behind the phase
        // glyph. "Timer only" leaves it to the menu and the spoken label.
        var segment: StatusItemContent.PomodoroSegment?
        // During a Pomodoro the dial shows the phase's progress instead.
        let focusLength = TimeInterval(state.focusMinutes * 60)
        let breakLength = TimeInterval(state.breakMinutes * 60)
        if state.pomodoro.state.isOn, let progress = state.pomodoro.progress(at: now, focus: focusLength, break: breakLength) {
            dial = progress
        }
        if let remaining = pomodoroRemaining {
            let focus = state.pomodoro.state.isFocusPhase
            let phase = focus ? "focus" : "break"
            let phaseSeconds = (focus ? state.focusMinutes : state.breakMinutes) * 60
            if let text = state.pomodoro.menuBarCountdown(at: now, paddedTo: phaseSeconds) {
                segment = .init(symbol: AppSymbol.phase(isFocus: focus), text: text)
            }
            if let over = state.pomodoro.overtime(at: now) {
                spoken += ", Pomodoro \(phase) ended \(spokenDuration(over, seconds: true)) ago"
            } else {
                spoken += ", Pomodoro \(phase), \(spokenDuration(remaining, seconds: true)) left"
            }
        }
        if state.pomodoroDisplay == .timer {
            segment = nil
        }
        if state.warning {
            spoken += ", tracker not running"
        }
        return StatusItemContent(dial: dial, title: title, pomodoro: segment, badge: state.warning, accessibilityLabel: spoken)
    }

    /// The disabled header lines of §2.1 as plain text.
    static func header(_ state: StatusItemState, at now: Date, calendar: Calendar = .current) -> [String] {
        headerLines(state, at: now, calendar: calendar).map(\.plain)
    }

    /// The disabled header lines of §2.1 with their styles.
    static func headerLines(_ state: StatusItemState, at now: Date, calendar: Calendar = .current) -> [MenuHeaderLine] {
        var lines: [MenuHeaderLine] = []
        if let running = state.running {
            lines.append(MenuHeaderLine(truncated(running.task.isEmpty ? "No task" : running.task, to: taskLimit), style: .title))
            if state.label.isNone {
                lines.append(MenuHeaderLine("No project", style: .primary, dot: ""))
            } else {
                let client = state.label.client.map { " · \($0)" }
                lines.append(MenuHeaderLine(state.label.name, secondary: client, style: .primary, dot: state.label.color ?? ""))
            }
            let start = state.chainStart ?? running.start
            var started = LocalDateText.time(start)
            if !calendar.isDate(start, inSameDayAs: now) {
                let yesterday = calendar.date(byAdding: .day, value: -1, to: now).map { calendar.isDate(start, inSameDayAs: $0) } ?? false
                started += yesterday ? " yesterday" : " " + start.formatted(.dateTime.month(.abbreviated).day())
            }
            let elapsed = DurationText.hoursMinutes(max(0, Int(now.timeIntervalSince(start))))
            lines.append(MenuHeaderLine("Started \(started) · \(elapsed) elapsed", style: .secondary, symbol: "clock"))
        } else {
            lines.append(MenuHeaderLine("Not tracking", style: .title))
            if let last = state.lastStoppedToday, let end = last.end {
                lines.append(MenuHeaderLine(
                    "Last: \(last.task.isEmpty ? "No task" : last.task), stopped \(LocalDateText.time(end))",
                    style: .secondary,
                    symbol: "clock"
                ))
            }
        }
        if let countdown = state.pomodoro.menuBarCountdown(at: now) {
            let focus = state.pomodoro.state.isFocusPhase
            let phase = focus ? "Focus" : "Break"
            let text = state.pomodoro.overtime(at: now) == nil ? "\(phase) · \(countdown) left" : "\(phase) ended · \(countdown)"
            lines.append(MenuHeaderLine(text, style: .primary, symbol: AppSymbol.phase(isFocus: focus)))
        }
        return lines
    }

    /// The tracker warning line; the warning symbol replaces a leading sign.
    static func warningLine(_ text: String) -> MenuHeaderLine {
        let trimmed = text.hasPrefix("⚠") ? String(text.dropFirst()).trimmingCharacters(in: .whitespaces) : text
        return MenuHeaderLine(trimmed, style: .warning, symbol: "exclamationmark.triangle")
    }

    /// The whole menu of §2.
    static func menu(_ state: StatusItemState, at now: Date) -> [StatusMenuEntry] {
        var entries: [StatusMenuEntry] = []
        if state.warning {
            entries.append(.header(warningLine(state.warningLine)))
            entries.append(.item(title: "Open Tracker Settings…", key: nil, enabled: true, command: .openTrackerSettings))
            entries.append(.separator)
        }
        entries += headerLines(state, at: now).map(StatusMenuEntry.header)
        entries.append(.separator)
        entries += [
            .item(title: "New", key: .command("n"), enabled: true, command: .new),
            .item(title: "Continue", key: .command("o"), enabled: state.mostRecentOther != nil, command: .continueLatest),
            .item(title: "Stop", key: .command("s"), enabled: state.running != nil, command: .stop),
            .separator,
        ]
        entries += pomodoroItems(state.pomodoro, isRunning: state.running != nil)
        entries += [
            .separator,
            .item(title: "Show Timer Window", key: state.showHideKey, enabled: true, command: .showTimer),
            .item(title: "Open Planner", key: .command("p", .option), enabled: true, command: .openPlanner),
            .item(title: "Settings…", key: .command(","), enabled: true, command: .settings),
            .separator,
            .item(title: "Quit \(state.appName)", key: .command("q"), enabled: true, command: .quit),
        ]
        return entries
    }

    /// The Pomodoro group of §2.3.
    static func pomodoroItems(_ pomodoro: Pomodoro, isRunning: Bool) -> [StatusMenuEntry] {
        guard pomodoro.state.isOn else {
            return [.item(title: "Start Pomodoro", key: .command("p", .shift), enabled: isRunning, command: .pomodoro(.start))]
        }
        return pomodoro.actions(isRunning: isRunning).map { action in
            let key: MenuKey? = switch action {
            case .cancel: .command("p", .shift)
            case .skipBreak: nil
            default: .command("p", .control)
            }
            return .item(title: action.title, key: key, enabled: true, command: .pomodoro(action))
        }
    }

    /// The Dock menu of §4: New Entry, Continue Latest, Stop.
    static func dockMenu(_ state: StatusItemState) -> [StatusMenuEntry] {
        [
            .item(title: "New Entry", key: nil, enabled: true, command: .new),
            .item(title: "Continue Latest", key: nil, enabled: state.mostRecentOther != nil, command: .continueLatest),
            .item(title: "Stop", key: nil, enabled: state.running != nil, command: .stop),
        ]
    }

    /// The next tick of §5, or `nil` when none is needed.
    static func nextTick(_ state: StatusItemState, after now: Date, menuOpen: Bool) -> Date? {
        if let end = state.pomodoro.state.phaseEnd {
            return aligned(now, anchor: end, period: 1)
        }
        guard state.running != nil, let chainStart = state.chainStart else {
            return nil
        }
        if menuOpen || state.showSeconds {
            return aligned(now, anchor: chainStart, period: 1)
        }
        // Also without the timer text: the dial moves every minute.
        return aligned(now, anchor: chainStart, period: 60)
    }

    /// The first instant after `now` that is a whole number of `period`s from `anchor`.
    static func aligned(_ now: Date, anchor: Date, period: TimeInterval) -> Date {
        let offset = now.timeIntervalSince(anchor)
        let steps = (offset / period).rounded(.down) + 1
        return anchor + steps * period
    }

    /// The countdown as `m:ss`, led by figure spaces to the width of the
    /// phase's full length, so the item keeps its width when the minutes lose
    /// a digit (`25:00` … `\u{2007}9:59`).
    static func paddedCountdown(_ remaining: Int, phaseSeconds: Int) -> String {
        let text = DurationText.minutesSeconds(remaining)
        let width = DurationText.minutesSeconds(max(phaseSeconds, remaining)).count
        return String(repeating: "\u{2007}", count: max(0, width - text.count)) + text
    }

    static func truncated(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }

    /// "40 minutes", "12 minutes 34 seconds", "1 hour 5 minutes".
    static func spokenDuration(_ seconds: Int, seconds withSeconds: Bool) -> String {
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        var parts: [String] = []
        if hours > 0 {
            parts.append("\(hours) hour\(hours == 1 ? "" : "s")")
        }
        if minutes > 0 || (hours == 0 && !withSeconds) {
            parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")")
        }
        if withSeconds, seconds % 60 > 0 || parts.isEmpty {
            parts.append("\(seconds % 60) second\(seconds % 60 == 1 ? "" : "s")")
        }
        return parts.joined(separator: " ")
    }
}
