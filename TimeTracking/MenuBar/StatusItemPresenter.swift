// StatusItemModel: what the menu bar item and its menu show
// (spec_menubar.md §1, §2, §4, §5).

import Foundation
import TimeTrackingCore

/// The status item's icon, title, Pomodoro segment, badge, and accessibility label.
struct StatusItemContent: Equatable {
    /// The Pomodoro countdown after the title: the phase glyph and `m:ss`
    /// (`+m:ss` once the phase has ended).
    struct PomodoroSegment: Equatable {
        /// Symbol name, template: `AppSymbol.pomodoro` or `cup.and.saucer`.
        var symbol: String
        var text: String
    }

    /// SF Symbol name, template.
    var symbol: String
    /// The elapsed time and the project, as the settings ask.
    var title: String
    var pomodoro: PomodoroSegment?
    /// The exclamation-mark badge of the tracker warning.
    var badge: Bool
    var accessibilityLabel: String

    /// Everything the item shows as text: the accessibility title.
    var visibleText: String {
        [title, pomodoro?.text ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// A disabled line at the top of the menu (spec_menubar.md §2.1).
struct MenuHeaderLine: Equatable {
    enum Style: Equatable {
        /// The running task or "Not tracking": the menu font, semibold.
        case title
        /// The project and Pomodoro lines: primary text, then `secondary` in the secondary color.
        case primary
        /// The start time and the last entry: the secondary color.
        case secondary
        /// The tracker warning.
        case warning
    }

    var text: String
    /// Text after `text` in the secondary color (" · client").
    var secondary: String?
    var style: Style
    /// An SF Symbol shown as the item's image.
    var symbol: String?
    /// The area dot shown as the item's image: an `#RRGGBB` color, or `""`
    /// for the hollow dot of no project.
    var dot: String?

    init(_ text: String, secondary: String? = nil, style: Style, symbol: String? = nil, dot: String? = nil) {
        self.text = text
        self.secondary = secondary
        self.style = style
        self.symbol = symbol
        self.dot = dot
    }

    /// The line as plain text.
    var plain: String {
        text + (secondary ?? "")
    }
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
    case header(MenuHeaderLine)
    case separator
    case item(title: String, key: MenuKey?, enabled: Bool, command: MenuCommand)
}

/// A menu entry as shown: consecutive header lines form one item.
enum StatusMenuRow: Equatable {
    case header([MenuHeaderLine])
    case entry(StatusMenuEntry)

    static func rows(_ entries: [StatusMenuEntry]) -> [Self] {
        var rows: [Self] = []
        var pending: [MenuHeaderLine] = []
        for entry in entries {
            if case let .header(line) = entry {
                pending.append(line)
                continue
            }
            if !pending.isEmpty {
                rows.append(.header(pending))
                pending = []
            }
            rows.append(.entry(entry))
        }
        if !pending.isEmpty {
            rows.append(.header(pending))
        }
        return rows
    }

    /// The row without header text: equal shapes need no rebuild. Compared
    /// by value, not by description: a key's modifier set describes itself
    /// in varying order, which rebuilt the open menu every few seconds.
    var shape: Self {
        switch self {
        case let .header(lines): .header(lines.map { _ in MenuHeaderLine("", style: .title) })
        case .entry: self
        }
    }

    /// The header lines as a one-element array, else empty.
    var headerGroup: [[MenuHeaderLine]] {
        if case let .header(lines) = self {
            return [lines]
        }
        return []
    }
}

extension MenuCommand {
    /// The item's SF Symbol (spec_design.md §5), or `nil` for none.
    var symbol: String? {
        switch self {
        case .new: "plus"
        case .continueLatest: "play.fill"
        case .stop: "stop.fill"
        // The phase glyph for the items that start a phase.
        case .pomodoro(.start), .pomodoro(.startFocus): AppSymbol.pomodoro
        case .pomodoro(.startBreak): "cup.and.saucer"
        case .showTimer: "stopwatch"
        case .openPlanner: "calendar"
        case .settings: "gearshape"
        case .openTrackerSettings: "waveform.path.ecg"
        case .pomodoro, .quit: nil
        }
    }
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
    var pomodoroDisplay: MenuBarPomodoroDisplay = .both
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
        let symbol = state.running == nil ? "stopwatch" : "stopwatch.fill"
        var title = ""
        var spoken = state.running == nil ? "Not tracking" : "Tracking"
        let pomodoroRemaining = state.pomodoro.state.isOn ? state.pomodoro.remaining(at: now) : nil
        // "Countdown only" hides the elapsed time while a countdown shows.
        let hidesElapsed = pomodoroRemaining != nil && state.pomodoroDisplay == .countdown
        if let chainStart = state.chainStart, state.running != nil {
            let elapsed = max(0, Int(now.timeIntervalSince(chainStart)))
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
        if let remaining = pomodoroRemaining {
            let focus = state.pomodoro.state.isFocusPhase
            let phase = focus ? "focus" : "break"
            let glyph = focus ? AppSymbol.pomodoro : "cup.and.saucer"
            if state.pomodoro.state.isPendingConfirmation || remaining < 0 {
                let over = -min(remaining, 0)
                segment = .init(symbol: glyph, text: "+" + DurationText.minutesSeconds(over))
                spoken += ", Pomodoro \(phase) ended \(spokenDuration(over, seconds: true)) ago"
            } else {
                segment = .init(symbol: glyph, text: DurationText.minutesSeconds(remaining))
                spoken += ", Pomodoro \(phase), \(spokenDuration(remaining, seconds: true)) left"
            }
        }
        if state.pomodoroDisplay == .timer {
            segment = nil
        }
        if state.warning {
            spoken += ", tracker not running"
        }
        return StatusItemContent(symbol: symbol, title: title, pomodoro: segment, badge: state.warning, accessibilityLabel: spoken)
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
            var started = time(start)
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
                    "Last: \(last.task.isEmpty ? "No task" : last.task), stopped \(time(end))",
                    style: .secondary,
                    symbol: "clock"
                ))
            }
        }
        if let remaining = state.pomodoro.remaining(at: now) {
            let focus = state.pomodoro.state.isFocusPhase
            let phase = focus ? "Focus" : "Break"
            let text = if state.pomodoro.state.isPendingConfirmation || remaining < 0 {
                "\(phase) ended · +\(DurationText.minutesSeconds(-min(remaining, 0)))"
            } else {
                "\(phase) · \(DurationText.minutesSeconds(remaining)) left"
            }
            lines.append(MenuHeaderLine(text, style: .primary, symbol: focus ? AppSymbol.pomodoro : "cup.and.saucer"))
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
