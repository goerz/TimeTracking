// EntryEditorModel: the edit popover's fields, commits, and notices
// (spec_timer.md §4). The Calendar reuses it.

import Foundation
import Observation
import TimeTrackingCore

/// The inline overlap notice with its pending change.
struct OverlapNotice: Equatable {
    /// "Overlaps “Morning Review” (9:00 to 9:25)".
    var text: String
    var change: EntryEditResult
}

/// The fields of one entry; each commits on Return or focus loss.
@Observable
final class EntryEditorModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored weak var undoManager: UndoManager?
    /// Called after a change was stored.
    @ObservationIgnored var onChange: (() async -> Void)?
    /// Called when the entry was deleted (closes the popover).
    @ObservationIgnored var onDelete: (() -> Void)?

    private(set) var entry: TimeEntry
    private(set) var label: ProjectLabel = .noProject
    var task = ""
    var startText = ""
    var stopText = ""
    var durationText = ""
    var date = Date()
    /// "Entries cannot be in the future", shown until the next edit.
    private(set) var message: String?
    private(set) var overlap: OverlapNotice?

    static let futureMessage = "Entries cannot be in the future"

    /// The fields show `entry` at once: a field that loses focus before
    /// `load()` returns commits what it shows, never an empty task.
    init(store: TimeStore, clock: any Clock, entry: TimeEntry) {
        self.store = store
        self.clock = clock
        self.entry = entry
        self.task = entry.task
        resetTimeFields()
    }

    var isRunning: Bool {
        entry.isRunning
    }

    /// Reloads the entry and resets the time fields to the stored values;
    /// the task follows the store unless it was edited meanwhile.
    func load() async {
        guard let current = try? await store.entry(entry.id) else {
            return
        }
        if task == entry.task {
            task = current.task
        }
        entry = current
        if let listing = try? await store.listings(for: [current]).first {
            label = ProjectLabel(listing)
        }
        resetTimeFields()
    }

    /// The live duration of a running entry.
    func durationDisplay(at now: Date) -> String {
        isRunning ? DurationText.clock(entry.seconds(at: now)) : durationText
    }

    // MARK: Commits

    func commitTask() async {
        guard task.trimmed != entry.task else {
            return
        }
        let old = entry
        await perform(undo: old) { [store, entry, task] in
            try await store.update(entry.id, EntryChange(task: task))
        }
    }

    func setProject(_ projectID: ProjectID?) async {
        guard projectID != entry.projectID else {
            return
        }
        let old = entry
        await perform(undo: old) { [store, entry] in
            try await store.update(entry.id, EntryChange(projectID: .some(projectID)))
        }
    }

    /// An unchanged field stores nothing: focus only passed through it.
    func commitStart() async {
        guard startText != LocalDateText.time(entry.start) else {
            return
        }
        guard let seconds = DurationText.parseTimeOfDay(startText) else {
            resetTimeFields()
            return
        }
        await commit(.start(seconds))
    }

    func commitStop() async {
        guard stopText != stopDisplay else {
            return
        }
        guard let seconds = DurationText.parseTimeOfDay(stopText) else {
            resetTimeFields()
            return
        }
        await commit(.stop(seconds))
    }

    func commitDuration() async {
        guard let seconds = DurationText.parseDuration(durationText) else {
            resetTimeFields()
            return
        }
        await commit(.duration(seconds))
    }

    func commitDate() async {
        let day = TrackingCalendar(timeZone: entry.zone).day(containing: date)
        guard day != entry.day else {
            return
        }
        await commit(.date(day))
    }

    /// Applies the rules of §4.2; future times are refused, overlaps ask first.
    func commit(_ edit: EntryFieldEdit) async {
        message = nil
        overlap = nil
        switch EntryEditRules.apply(edit, to: entry, now: clock.now) {
        case let .failure(error):
            if error == .inFuture {
                message = Self.futureMessage
            }
            resetTimeFields()
        case let .success(result):
            guard result.start != entry.start || result.end != entry.end else {
                resetTimeFields()
                return
            }
            let draft = EntryDraft(projectID: entry.projectID, task: entry.task, start: result.start, end: result.end)
            if let other = await (try? store.overlaps(for: draft, excluding: entry.id))?.first {
                overlap = await OverlapNotice(text: OverlapNotice.text(for: other, in: store), change: result)
                return
            }
            await store(result)
        }
    }

    /// "Keep": stores the overlapping change.
    func keepOverlap() async {
        guard let overlap else {
            return
        }
        self.overlap = nil
        await store(overlap.change)
    }

    /// "Revert": restores the field.
    func revertOverlap() {
        overlap = nil
        resetTimeFields()
    }

    /// Escape in an edited field: revert. Returns `false` when nothing was
    /// edited (the popover closes).
    func revertFields() -> Bool {
        let edited = task != entry.task || startText != LocalDateText.time(entry.start) || stopText != stopDisplay
            || durationText != DurationText.clock(entry.seconds(at: clock.now))
        task = entry.task
        resetTimeFields()
        return edited
    }

    /// Delete (after the alert); undoable.
    func delete() async {
        let id = entry.id
        do {
            try await store.delete([id])
            undoManager?.registerUndo(withTarget: store) { store in
                Task { try? await store.restore([id]) }
            }
            undoManager?.setActionName("Delete Entry")
            await onChange?()
            onDelete?()
        } catch {
            message = UserMessage.logged(error, category: "Editor")
        }
    }

    // MARK: Helpers

    private func store(_ result: EntryEditResult) async {
        let old = entry
        guard let change = result.changeIfAny(from: old) else {
            return
        }
        await perform(undo: old) { [store, entry] in
            try await store.update(entry.id, change)
        }
    }

    private func perform(undo old: TimeEntry, _ write: @Sendable () async throws -> TimeEntry) async {
        do {
            entry = try await write()
            registerUndo(restoring: old)
            task = entry.task
            resetTimeFields()
            if let listing = try? await store.listings(for: [entry]).first {
                label = ProjectLabel(listing)
            }
            await onChange?()
        } catch {
            message = UserMessage.logged(error, category: "Editor")
            resetTimeFields()
        }
    }

    private func registerUndo(restoring old: TimeEntry) {
        guard let undoManager else {
            return
        }
        let change = EntryChange(projectID: .some(old.projectID), task: old.task, start: old.start, end: old.end)
        undoManager.registerUndo(withTarget: store) { store in
            Task { _ = try? await store.update(old.id, change) }
        }
        undoManager.setActionName("Edit Entry")
    }

    private var stopDisplay: String {
        entry.end.map(LocalDateText.time) ?? "running"
    }

    private func resetTimeFields() {
        startText = LocalDateText.time(entry.start)
        stopText = stopDisplay
        durationText = DurationText.clock(entry.seconds(at: clock.now))
        date = entry.start
    }
}
