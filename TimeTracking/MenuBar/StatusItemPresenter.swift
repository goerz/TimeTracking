// StatusItemModel: what the menu bar item and its menu show
// (spec_menubar.md §1, §2, §4, §5).

import Foundation
import TimeTrackingCore

/// The status item's icon, title, badge, and accessibility label.
struct StatusItemContent: Equatable {
    /// SF Symbol name, template.
    var symbol: String
    var title: String
    /// The exclamation-mark badge of the tracker warning.
    var badge: Bool
    var accessibilityLabel: String
}

/// A key equivalent of a menu item.
struct MenuKey: Equatable {
    enum Modifier: Hashable {
        case command
        case shift
        case option
        case control
    }

    var key: String
    var modifiers: Set<Modifier>

    static func command(_ key: String, _ extra: Modifier...) -> Self {
        Self(key: key, modifiers: Set([.command] + extra))
    }

    /// "⌃⌥⇧⌘P" in the system's order.
    var display: String {
        let order: [(Modifier, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return order.filter { modifiers.contains($0.0) }.map(\.1).joined() + key.uppercased()
    }
}

/// What a menu item does.
enum MenuCommand: Hashable {
    case openTrackerSettings
    case new
    case continueLatest
    case stop
    case pomodoro(PomodoroAction)
    case showTimer
    case openPlanner
    case settings
    case quit
}

/// One line of the menu.
enum StatusMenuEntry: Equatable {
    /// A disabled informational line.
    case header(String)
    case separator
    case item(title: String, key: MenuKey?, enabled: Bool, command: MenuCommand)
}

/// The inputs of the status item, gathered from the Timer window's state.
struct StatusItemState {
    var running: TimeEntry?
    var chainStart: Date?
    var label: ProjectLabel
    var mostRecentOther: TimeEntry?
    var lastStoppedToday: TimeEntry?
    var pomodoro: Pomodoro
    var showTimer: Bool
    var showSeconds: Bool
    var showProject: Bool
    var warning: Bool
    var warningLine: String
    /// The recorded show/hide shortcut, `nil` when cleared.
    var showHideKey: MenuKey?
    var appName: String
}

/// The status item's presentation; pure, so tests drive it with any clock.
enum StatusItemPresenter {
    /// Maximum length of the project name, ellipsis included.
    static let projectLimit = 24
    /// Maximum length of the task header line.
    static let taskLimit = 60

    static func content(_ state: StatusItemState, at now: Date) -> StatusItemContent {
        var symbol = state.running == nil ? "stopwatch" : "stopwatch.fill"
        var time: String?
        var spoken = state.running == nil ? "Not tracking" : "Tracking"
        if state.pomodoro.state.isOn, let remaining = state.pomodoro.remaining(at: now) {
            symbol = state.pomodoro.state.isFocusPhase ? "hourglass" : "cup.and.saucer"
            let phase = state.pomodoro.state.isFocusPhase ? "focus" : "break"
            if state.pomodoro.state.isPendingConfirmation || remaining < 0 {
                time = "+" + DurationText.minutesSeconds(-min(remaining, 0))
                spoken = "Pomodoro \(phase) ended, \(spokenDuration(-min(remaining, 0), seconds: true)) ago"
            } else {
                time = DurationText.minutesSeconds(remaining)
                spoken = "Pomodoro \(phase), \(spokenDuration(remaining, seconds: true)) left"
            }
        } else if let chainStart = state.chainStart, state.running != nil {
            let elapsed = max(0, Int(now.timeIntervalSince(chainStart)))
            if state.showTimer {
                time = state.showSeconds ? DurationText.clock(elapsed) : DurationText.hoursMinutes(elapsed)
            }
            spoken = "Tracking, \(spokenDuration(elapsed, seconds: state.showSeconds))"
        }
        var title = time ?? ""
        if state.showProject, state.running != nil, !state.label.isNone {
            let name = truncated(state.label.name, to: projectLimit)
            title = title.isEmpty ? name : "\(title) · \(name)"
            spoken += ", \(state.label.name)"
        }
        if state.warning {
            spoken += ", tracker not running"
        }
        return StatusItemContent(symbol: symbol, title: title, badge: state.warning, accessibilityLabel: spoken)
    }

    /// The disabled header lines of §2.1.
    static func header(_ state: StatusItemState, at now: Date, calendar: Calendar = .current) -> [String] {
        var lines: [String] = []
        if let running = state.running {
            lines.append(truncated(running.task.isEmpty ? "No task" : running.task, to: taskLimit))
            lines.append(state.label.isNone ? "No project" : state.label.projectAndClient)
            let start = state.chainStart ?? running.start
            var started = time(start)
            if !calendar.isDate(start, inSameDayAs: now) {
                let yesterday = calendar.date(byAdding: .day, value: -1, to: now).map { calendar.isDate(start, inSameDayAs: $0) } ?? false
                started += yesterday ? " yesterday" : " " + start.formatted(.dateTime.month(.abbreviated).day())
            }
            let elapsed = DurationText.hoursMinutes(max(0, Int(now.timeIntervalSince(start))))
            lines.append("Started \(started), \(elapsed) elapsed")
        } else {
            lines.append("No entry running")
            if let last = state.lastStoppedToday, let end = last.end {
                lines.append("Last: \(last.task.isEmpty ? "No task" : last.task), stopped \(time(end))")
            }
        }
        if let remaining = state.pomodoro.remaining(at: now) {
            let phase = state.pomodoro.state.isFocusPhase ? "Focus" : "Break"
            if state.pomodoro.state.isPendingConfirmation || remaining < 0 {
                lines.append("\(phase) ended +\(DurationText.minutesSeconds(-min(remaining, 0)))")
            } else {
                lines.append("\(phase), \(DurationText.minutesSeconds(remaining)) left")
            }
        }
        return lines
    }

    /// The whole menu of §2.
    static func menu(_ state: StatusItemState, at now: Date) -> [StatusMenuEntry] {
        var entries: [StatusMenuEntry] = []
        if state.warning {
            entries.append(.header(state.warningLine))
            entries.append(.item(title: "Open Tracker Settings…", key: nil, enabled: true, command: .openTrackerSettings))
            entries.append(.separator)
        }
        entries += header(state, at: now).map(StatusMenuEntry.header)
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
        if !state.showTimer {
            return nil
        }
        return aligned(now, anchor: chainStart, period: 60)
    }

    /// The first instant after `now` that is a whole number of `period`s from `anchor`.
    static func aligned(_ now: Date, anchor: Date, period: TimeInterval) -> Date {
        let offset = now.timeIntervalSince(anchor)
        let steps = (offset / period).rounded(.down) + 1
        return anchor + steps * period
    }

    static func truncated(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
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
