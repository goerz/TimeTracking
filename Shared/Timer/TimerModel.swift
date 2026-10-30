// TimerModel: the running-entry bar's state and the timer commands
// (spec_timer_window.md §2, §2.1, §2.2, §13).

import Foundation
import Observation
import os
import TimeTrackingCore

/// An alert the Timer window shows.
enum TimerAlert: Equatable, Identifiable {
    /// "Discard the running entry? 0:12:34 will be lost."
    case discard(elapsed: String)
    /// Continuing an archived project's entry.
    case restoreProject(EntryID, projectName: String)
    /// "Delete this entry? 0:25:00, Household"
    case deleteEntry(EntryID, summary: String)

    var id: String {
        switch self {
        case .discard: "discard"
        case let .restoreProject(id, _): "restore-\(id)"
        case let .deleteEntry(id, _): "delete-\(id)"
        }
    }

    var message: String {
        switch self {
        case let .discard(elapsed): "Discard the running entry? \(elapsed) will be lost."
        case let .restoreProject(_, name): "“\(name)” is archived."
        case let .deleteEntry(_, summary): "Delete this entry? \(summary)"
        }
    }
}

/// The running entry, the draft, and the commands New, Start, Stop,
/// Continue, and Discard.
@Observable
final class TimerModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let notifier: NotificationAuthorizing
    @ObservationIgnored weak var undoManager: UndoManager?
    /// Called after an entry starts or stops through this model.
    @ObservationIgnored var onChange: (() async -> Void)?
    /// Waits between the last keystroke and the task commit.
    @ObservationIgnored var debounce: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    @ObservationIgnored var pendingTaskCommit: Task<Void, Never>?
    @ObservationIgnored private let logger = Logging.logger(category: "Timer")
    /// The undo action in flight (tests await it).
    @ObservationIgnored private(set) var pendingUndo: Task<Void, Never>?
    @ObservationIgnored private var askedForNotifications = false

    /// The task field's debounce interval (§2.2).
    static let taskCommitDelay = Duration.milliseconds(500)

    private(set) var running: TimeEntry?
    private(set) var runningLabel: ProjectLabel = .noProject
    /// The earliest start of the running entry's midnight chain.
    private(set) var chainStart: Date?
    /// The most recent entry other than the running one.
    private(set) var mostRecentOther: TimeEntry?
    /// The latest entry stopped today, for the menu bar header.
    private(set) var lastStoppedToday: TimeEntry?
    /// The task field's text: the running entry's task or the draft.
    var taskText = ""
    /// The draft's project while nothing runs.
    private(set) var draftProjectID: ProjectID?
    private(set) var draftLabel: ProjectLabel = .noProject
    /// Bumped to move keyboard focus into the task field.
    private(set) var focusTaskFieldRequest = 0
    var alert: TimerAlert?
    private(set) var lastError: String?

    init(store: TimeStore, clock: any Clock, notifier: NotificationAuthorizing) {
        self.store = store
        self.clock = clock
        self.notifier = notifier
    }

    var isRunning: Bool {
        running != nil
    }

    /// The chip's project: the running entry's, else the draft's.
    var chipLabel: ProjectLabel {
        running == nil ? draftLabel : runningLabel
    }

    /// The chip's project id.
    var chipProjectID: ProjectID? {
        running == nil ? draftProjectID : running?.projectID
    }

    /// Seconds since the chain start, or 0 when idle.
    func elapsedSeconds(at now: Date) -> Int {
        guard let chainStart else {
            return 0
        }
        return max(0, Int(now.timeIntervalSince(chainStart).rounded(.down)))
    }

    /// The timer label without a Pomodoro: `h:mm:ss`, `0:00:00` when idle.
    func timerText(at now: Date) -> String {
        DurationText.clock(elapsedSeconds(at: now))
    }

    func requestTaskFieldFocus() {
        focusTaskFieldRequest += 1
    }

    // MARK: Loading

    /// Re-reads the running entry and what the menu bar shows.
    func refresh() async {
        do {
            let current = try await store.runningEntry()
            let previous = running
            if current?.id != previous?.id {
                pendingTaskCommit?.cancel()
                pendingTaskCommit = nil
                if let current {
                    taskText = current.task
                } else if let previous {
                    // Stopped elsewhere: the stopped entry becomes the draft.
                    await setDraftProject(previous.projectID)
                }
            } else if let current, pendingTaskCommit == nil, current.task != previous?.task {
                taskText = current.task
            }
            running = current
            if let current {
                runningLabel = try await ProjectLabel(store.listings(for: [current])[0])
                chainStart = try await store.chainStart(of: current.id)
            } else {
                runningLabel = .noProject
                chainStart = nil
            }
            mostRecentOther = try await store.recentEntries(before: nil, limit: 2).first { $0.id != current?.id }
            let stopped = try await store.lastStoppedEntry(excluding: current?.id)
            let today = TrackingCalendar(timeZone: .current).day(containing: clock.now)
            lastStoppedToday = stopped.flatMap { $0.day == today ? $0 : nil }
        } catch {
            report(error)
        }
    }

    // MARK: Commands

    /// Starts an entry with the field's task and the chip's project.
    func start() async {
        await perform { [store, clock, taskText, draftProjectID] in
            try await store.start(projectID: draftProjectID, task: taskText, at: clock.now)
        }
    }

    /// ⌘N: starts an empty entry.
    func new() async {
        taskText = ""
        await perform { [store, clock] in
            try await store.start(projectID: nil, task: "", at: clock.now)
        }
        requestTaskFieldFocus()
    }

    /// Stops the running entry; its task and project stay as the draft.
    func stop() async {
        guard let running else {
            return
        }
        await commitTask()
        do {
            try await store.stop(at: clock.now)
            await setDraftProject(running.projectID)
            await refresh()
            await onChange?()
        } catch {
            report(error)
        }
    }

    /// Continues `id`, or the most recent entry other than the running one.
    /// An archived project raises the restore alert instead.
    func continueEntry(_ id: EntryID? = nil) async {
        guard let id = id ?? mostRecentOther?.id else {
            return
        }
        do {
            guard let source = try await store.entry(id) else {
                return
            }
            if let projectID = source.projectID, let project = try await store.project(projectID), project.isArchived {
                alert = .restoreProject(id, projectName: project.name)
                return
            }
            await perform { [store, clock] in try await store.continue(id, at: clock.now) }
        } catch {
            report(error)
        }
    }

    /// "Restore Project and Continue".
    func restoreProjectAndContinue(_ id: EntryID) async {
        do {
            guard let projectID = try await store.entry(id)?.projectID else {
                return
            }
            try await store.restoreProject(projectID)
            await perform { [store, clock] in try await store.continue(id, at: clock.now) }
        } catch {
            report(error)
        }
    }

    /// The continue/stop shortcut: stop, or continue the most recent entry.
    func continueOrStop() async {
        if running != nil {
            await stop()
        } else {
            await continueEntry()
        }
    }

    /// The discard button or ⌥⌘⌫; ⌥-click skips the alert.
    func requestDiscard(skipAlert: Bool) async {
        guard let running else {
            return
        }
        if skipAlert {
            await discard()
        } else {
            alert = .discard(elapsed: DurationText.clock(running.seconds(at: clock.now)))
        }
    }

    /// Deletes the running entry; undoable.
    func discard() async {
        guard let running else {
            return
        }
        pendingTaskCommit?.cancel()
        pendingTaskCommit = nil
        do {
            try await store.delete([running.id])
            registerUndo(name: "Discard") { model in
                try? await model.store.restore([running.id])
                await model.refresh()
                await model.onChange?()
            }
            self.running = nil
            await setDraftProject(running.projectID)
            await refresh()
            await onChange?()
        } catch {
            report(error)
        }
    }

    /// Assigns a project from the picker: the running entry's (whole
    /// chain) at once, or the draft's.
    func setProject(_ id: ProjectID?) async {
        guard let running else {
            await setDraftProject(id)
            return
        }
        do {
            try await store.updateChain(of: running.id, projectID: .some(id))
            await refresh()
        } catch {
            report(error)
        }
    }

    // MARK: Helpers

    func setDraftProject(_ id: ProjectID?) async {
        draftProjectID = id
        draftLabel = await label(for: id)
    }

    private func label(for id: ProjectID?) async -> ProjectLabel {
        guard let id else {
            return .noProject
        }
        let probe = TimeEntry(
            projectID: id,
            task: "",
            start: clock.now,
            end: clock.now,
            timeZone: "UTC",
            deviceID: DeviceID(),
            createdAt: clock.now,
            modifiedAt: clock.now
        )
        guard let listing = try? await store.listings(for: [probe]).first else {
            return .noProject
        }
        return ProjectLabel(listing)
    }

    /// Runs a start-like write, then refreshes and notifies.
    private func perform(_ write: @Sendable () async throws -> TimeEntry) async {
        do {
            let entry = try await write()
            taskText = entry.task
            if !askedForNotifications {
                askedForNotifications = true
                notifier.requestAuthorization()
            }
            await refresh()
            await onChange?()
        } catch {
            report(error)
        }
    }

    private func registerUndo(name: String, _ action: @escaping @MainActor (TimerModel) async -> Void) {
        guard let undoManager else {
            return
        }
        undoManager.registerUndo(withTarget: self) { model in
            model.pendingUndo = Task { @MainActor in await action(model) }
        }
        undoManager.setActionName(name)
    }

    func report(_ error: any Error) {
        lastError = String(describing: error)
        logger.error("Timer command failed: \(String(describing: error), privacy: .public)")
    }
}
