// WidgetSnapshotBuilder: builds the widgets' snapshot from the store, the
// resolved LiveState, and this device's Pomodoro, and decides when the
// timeline ends (ios.md §3).

public import Foundation

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
        let calendar = store?.displayCalendar(timeZone: timeZone) ?? TrackingCalendar(timeZone: timeZone)
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
                start: running.start
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
            reloadAt: Self.reloadDate(after: now, pomodoro: pomodoro, timeZone: timeZone, startOfDayHour: calendar.startOfDayHour),
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
        await addToday(to: &snapshot, store: store, at: now, calendar: calendar)
        await addRecent(to: &snapshot, store: store, rows: byID)
        var ids = pinnedIDs ?? []
        if pinnedIDs == nil {
            ids = await (try? store.value(.pinnedProjectIDs)) ?? []
        }
        snapshot.pinned = await pinnedButtons(ids, store: store, rows: byID, taskMode: taskMode, running: running)
        return snapshot
    }

    private func addToday(to snapshot: inout WidgetSnapshot, store: TimeStore, at now: Date, calendar: TrackingCalendar) async {
        let today = calendar.day(containing: now)
        let midnight = calendar.startOfDay(today)
        let runningID = snapshot.running?.entryID
        let stored = await (try? store.entries(reaching: today ... today, in: calendar)) ?? []
        let stopped = stored
            .filter { $0.id != runningID && !$0.isRunning }
            .flatMap { calendar.pieces(of: $0, at: now) }
            .filter { $0.day == today }
        snapshot.todayStoppedSeconds = stopped.reduce(0) { total, entry in
            let interval = entry.interval(at: now)
            let start = max(interval.start, midnight)
            return total + max(0, Int(interval.end.timeIntervalSince(start)))
        }
        if let running = snapshot.running {
            snapshot.todayTimerStart = max(running.start, midnight) - TimeInterval(snapshot.todayStoppedSeconds)
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
    /// counts down on this device, else the start of the next day.
    public static func reloadDate(after now: Date, pomodoro: PomodoroState, timeZone: TimeZone, startOfDayHour: Int = 0) -> Date {
        switch pomodoro {
        case let .focus(end), let .onBreak(end):
            if end > now {
                return end
            }
        case .off, .focusOver, .breakOver:
            break
        }
        let calendar = TrackingCalendar(timeZone: timeZone, startOfDayHour: startOfDayHour)
        return calendar.startOfDay(calendar.day(containing: now).adding(days: 1))
    }

    /// Smart Stack relevance (ios.md §3.1).
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
