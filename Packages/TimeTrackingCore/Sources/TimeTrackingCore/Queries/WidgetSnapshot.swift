// WidgetSnapshot: what the Now, Recent, Pinned, and Lock Screen widgets show,
// and when their timeline ends (spec_ios.md §3). The widget extension's
// providers only wrap a snapshot in a WidgetKit entry.

public import Foundation

/// The content of every widget kind at one moment.
public struct WidgetSnapshot: Hashable, Sendable {
    /// A project and task as a widget row or button shows it.
    public struct Row: Hashable, Sendable, Identifiable {
        public var projectID: ProjectID?
        public var task: String
        public var projectName: String?
        public var clientName: String?
        public var areaColor: String?

        public init(projectID: ProjectID?, task: String, projectName: String?, clientName: String?, areaColor: String?) {
            self.projectID = projectID
            self.task = task
            self.projectName = projectName
            self.clientName = clientName
            self.areaColor = areaColor
        }

        public var id: String {
            "\(projectID?.rawValue ?? "-")|\(task)"
        }
    }

    /// The running entry, from `LiveState` (it may not be in the store yet).
    public struct Running: Hashable, Sendable {
        public var entryID: EntryID
        public var row: Row
        /// The chain's earliest start: elapsed times count from here.
        public var chainStart: Date
    }

    /// A Pinned widget button.
    public struct PinnedButton: Hashable, Sendable, Identifiable {
        public var projectID: ProjectID
        public var name: String
        public var areaColor: String?
        /// The task a tap starts with ("last task" mode), else empty.
        public var task: String
        public var isArchived: Bool
        /// The running entry's project: the button stops it.
        public var isRunning: Bool

        public init(projectID: ProjectID, name: String, areaColor: String?, task: String, isArchived: Bool, isRunning: Bool) {
            self.projectID = projectID
            self.name = name
            self.areaColor = areaColor
            self.task = task
            self.isArchived = isArchived
            self.isRunning = isRunning
        }

        public var id: ProjectID {
            projectID
        }
    }

    public var date: Date
    /// Before the first sync delivered the store: "Open TimeTracking to finish setup".
    public var needsSetup: Bool
    public var running: Running?
    /// The most recent entry other than the running one (idle states).
    public var latest: Row?
    /// The latest entry's id, which Continue continues.
    public var latestEntryID: EntryID?
    /// Today's stopped seconds, the running entry excluded.
    public var todayStoppedSeconds: Int
    /// While running, the start of a live timer that shows today's total:
    /// `todayStoppedSeconds` before the later of the running start and midnight.
    public var todayTimerStart: Date?
    /// This device's Pomodoro.
    public var pomodoro: PomodoroState
    /// The Mac activity lines (spec_ios.md §2.3).
    public var macLines: [String]
    /// Recent distinct (task, project) pairs without the running pair.
    public var recent: [Row]
    public var pinned: [PinnedButton]
    /// The end of the one-entry timeline.
    public var reloadAt: Date
    /// Smart Stack relevance: 100 while running, 60 for an hour after a stop, 10 otherwise.
    public var relevance: Int

    /// The widget gallery's sample: a running entry of 0:42:27.
    public static func placeholder(at now: Date) -> Self {
        let row = Row(
            projectID: nil,
            task: "Clarify noise model",
            projectName: "Noise Model",
            clientName: "University",
            areaColor: "#2A9D8F"
        )
        return Self(
            date: now,
            needsSetup: false,
            running: Running(entryID: EntryID(), row: row, chainStart: now - 2547),
            latest: row,
            latestEntryID: nil,
            todayStoppedSeconds: 5898,
            todayTimerStart: now - 8445,
            pomodoro: .off,
            macLines: [],
            recent: [row],
            pinned: [],
            reloadAt: now + 3600,
            relevance: 10
        )
    }

    /// Today's total at `now` (tests and the inline family).
    public func todaySeconds(at now: Date) -> Int {
        guard let todayTimerStart else {
            return todayStoppedSeconds
        }
        return max(0, Int(now.timeIntervalSince(todayTimerStart)))
    }
}

/// Which task a pinned button starts with (spec_ios.md §2.9, §3.4).
public enum PinnedTaskMode: String, Codable, Sendable, CaseIterable {
    /// The project's most recent task.
    case latest
    /// An empty task.
    case blank
}

/// Builds snapshots from the store, the resolved `LiveState`, and this
/// device's Pomodoro.
public struct WidgetSnapshotBuilder: Sendable {
    /// Rows the Recent widget asks for at most (extra large: 14).
    public static let recentLimit = 14

    /// `nil` when the store cannot be opened (first launch).
    public let store: TimeStore?
    public let timeZone: TimeZone

    public init(store: TimeStore?, timeZone: TimeZone) {
        self.store = store
        self.timeZone = timeZone
    }

    /// The snapshot at `now`. `pinnedIDs` is the Pinned widget's explicit
    /// list, or `nil` for the synced `pinnedProjectIDs`.
    public func build(
        at now: Date,
        live: LiveState,
        setupComplete: Bool,
        pomodoro: PomodoroState = .off,
        // swiftlint:disable:next discouraged_optional_collection
        pinnedIDs: [ProjectID]? = nil,
        taskMode: PinnedTaskMode = .latest
    ) async -> WidgetSnapshot {
        let calendar = TrackingCalendar(timeZone: timeZone)
        let today = calendar.day(containing: now)
        let midnight = calendar.startOfDay(today)
        let running = live.running.map { running in
            WidgetSnapshot.Running(
                entryID: running.entryID,
                row: WidgetSnapshot.Row(
                    projectID: running.projectID,
                    task: running.task,
                    projectName: running.projectName,
                    clientName: running.clientName,
                    areaColor: running.areaColor
                ),
                chainStart: running.chainStart
            )
        }
        var snapshot = WidgetSnapshot(
            date: now,
            needsSetup: !setupComplete || store == nil,
            running: running,
            latest: nil,
            latestEntryID: nil,
            todayStoppedSeconds: 0,
            todayTimerStart: nil,
            pomodoro: pomodoro,
            macLines: MacActivityLine.lines(live, timeZone: timeZone),
            recent: [],
            pinned: [],
            reloadAt: Self.reloadDate(after: now, pomodoro: pomodoro, timeZone: timeZone),
            relevance: Self.relevance(live: live, at: now)
        )
        guard let store else {
            return snapshot
        }
        let rows = await (try? store.projects(filter: ProjectFilter(state: .all))) ?? []
        let byID = Dictionary(rows.map { ($0.project.id, $0) }, uniquingKeysWith: { first, _ in first })
        if var running {
            // The store knows the client even when LiveState was written before it.
            running.row = Self.row(projectID: running.row.projectID, task: running.row.task, in: byID, fallback: running.row)
            snapshot.running = running
        }
        await addToday(to: &snapshot, store: store, at: now, midnight: midnight, today: today)
        await addRecent(to: &snapshot, store: store, rows: byID)
        var ids = pinnedIDs ?? []
        if pinnedIDs == nil {
            ids = await (try? store.value(.pinnedProjectIDs)) ?? []
        }
        snapshot.pinned = await pinnedButtons(ids, store: store, rows: byID, taskMode: taskMode, running: running)
        return snapshot
    }

    private func addToday(to snapshot: inout WidgetSnapshot, store: TimeStore, at now: Date, midnight: Date, today: TrackingDay) async {
        let runningID = snapshot.running?.entryID
        let stopped = await ((try? store.entries(on: today)) ?? []).filter { $0.id != runningID && !$0.isRunning }
        snapshot.todayStoppedSeconds = stopped.reduce(0) { total, entry in
            let interval = entry.interval(at: now)
            let start = max(interval.start, midnight)
            return total + max(0, Int(interval.end.timeIntervalSince(start)))
        }
        if let running = snapshot.running {
            snapshot.todayTimerStart = max(running.chainStart, midnight) - TimeInterval(snapshot.todayStoppedSeconds)
        }
    }

    private func addRecent(to snapshot: inout WidgetSnapshot, store: TimeStore, rows: [ProjectID: ProjectRow]) async {
        let running = snapshot.running
        let recentEntries = await (try? store.recentEntries(before: nil, limit: 3)) ?? []
        if let latest = recentEntries.first(where: { $0.id != running?.entryID && !$0.isRunning }) {
            snapshot.latestEntryID = latest.id
            snapshot.latest = Self.row(projectID: latest.projectID, task: latest.task, in: rows)
        }
        let pairs = await (try? store.recentCombinations(limit: Self.recentLimit + 1)) ?? []
        snapshot.recent = pairs
            .filter { pair in !(running.map { $0.row.projectID == pair.0 && $0.row.task == pair.1 } ?? false) }
            .prefix(Self.recentLimit)
            .map { Self.row(projectID: $0.0, task: $0.1, in: rows) }
    }

    private func pinnedButtons(
        _ ids: [ProjectID],
        store: TimeStore,
        rows: [ProjectID: ProjectRow],
        taskMode: PinnedTaskMode,
        running: WidgetSnapshot.Running?
    ) async -> [WidgetSnapshot.PinnedButton] {
        var pinned: [WidgetSnapshot.PinnedButton] = []
        for id in ids {
            guard let row = rows[id] else {
                continue
            }
            let task = taskMode == .latest
                ? await ((try? store.distinctTasks(projectID: id, prefix: "", limit: 1)) ?? []).first?.task ?? ""
                : ""
            pinned.append(WidgetSnapshot.PinnedButton(
                projectID: id,
                name: row.project.name,
                areaColor: row.area?.color,
                task: task,
                isArchived: row.project.isArchived,
                isRunning: running?.row.projectID == id
            ))
        }
        return pinned
    }

    private static func row(
        projectID: ProjectID?,
        task: String,
        in rows: [ProjectID: ProjectRow],
        fallback: WidgetSnapshot.Row? = nil
    ) -> WidgetSnapshot.Row {
        guard let projectID, let row = rows[projectID] else {
            return fallback ?? WidgetSnapshot.Row(projectID: projectID, task: task, projectName: nil, clientName: nil, areaColor: nil)
        }
        return WidgetSnapshot.Row(
            projectID: projectID,
            task: task,
            projectName: row.project.name,
            clientName: row.client?.name,
            areaColor: row.area?.color
        )
    }

    /// The timeline's end: the running phase's end while a Pomodoro phase
    /// counts down on this device, else the next local midnight.
    public static func reloadDate(after now: Date, pomodoro: PomodoroState, timeZone: TimeZone) -> Date {
        switch pomodoro {
        case let .focus(end), let .onBreak(end):
            if end > now {
                return end
            }
        case .off, .focusOver, .breakOver:
            break
        }
        let calendar = TrackingCalendar(timeZone: timeZone)
        return calendar.startOfDay(calendar.day(containing: now).adding(days: 1))
    }

    /// Smart Stack relevance (spec_ios.md §3.1).
    public static func relevance(live: LiveState, at now: Date) -> Int {
        if live.running != nil {
            return 100
        }
        if let changed = live.changedAt, now.timeIntervalSince(changed) < 3600 {
            return 60
        }
        return 10
    }
}

/// The Mac activity line under the Timer card and in the medium widget's
/// footer (spec_ios.md §2.3).
public enum MacActivityLine {
    /// One line per Mac whose tracker runs, most recently updated first, at
    /// most two: "MacBook · tmux:paper draft · active".
    public static func lines(_ state: LiveState, timeZone: TimeZone, limit: Int = 2) -> [String] {
        state.activity.values
            .filter(\.agentRunning)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { line($0, timeZone: timeZone) }
    }

    static func line(_ activity: LiveState.MacActivity, timeZone: TimeZone) -> String {
        var parts = [activity.device]
        if let item = item(activity.primary) {
            parts.append(item)
        }
        if let presence = presence(activity, timeZone: timeZone) {
            parts.append(presence)
        }
        return parts.joined(separator: " · ")
    }

    /// The context and subject; the subject alone when the context is a
    /// plain app name (no `kind:name` form).
    static func item(_ primary: TrackerPrimaryItem?) -> String? {
        guard let primary else {
            return nil
        }
        if primary.subject.isEmpty {
            return primary.context.isEmpty ? nil : primary.context
        }
        if primary.context.contains(":") {
            return "\(primary.context) \(primary.subject)"
        }
        return primary.subject
    }

    /// "active", "passive", "idle since 14:02", "locked since 14:02", "asleep since 14:02".
    static func presence(_ activity: LiveState.MacActivity, timeZone: TimeZone) -> String? {
        guard let presence = activity.presence, !presence.isEmpty else {
            return nil
        }
        guard ["idle", "locked", "asleep"].contains(presence), let since = activity.since else {
            return presence
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return "\(presence) since \(formatter.string(from: since))"
    }
}
