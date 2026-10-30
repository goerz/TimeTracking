// EntryEditorModel: the edit popover's fields, commits, and notices
// (spec_timer_window.md §4). The Planner's Calendar reuses it.

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
    /// "Continued from …" and "Continues on … until …".
    private(set) var chainLines: [String] = []

    static let futureMessage = "Entries cannot be in the future"

    init(store: TimeStore, clock: any Clock, entry: TimeEntry) {
        self.store = store
        self.clock = clock
        self.entry = entry
    }

    var isRunning: Bool {
        entry.isRunning
    }

    /// Reloads the entry and resets every field to the stored values.
    func load() async {
        guard let current = try? await store.entry(entry.id) else {
            return
        }
        entry = current
        task = current.task
        if let listing = try? await store.listings(for: [current]).first {
            label = ProjectLabel(listing)
        }
        resetTimeFields()
        await loadChain()
    }

    /// The live duration of this entry (not the chain) for a running entry.
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
            try await store.updateChain(of: entry.id, task: task)
        }
    }

    func setProject(_ projectID: ProjectID?) async {
        guard projectID != entry.projectID else {
            return
        }
        let old = entry
        await perform(undo: old) { [store, entry] in
            try await store.updateChain(of: entry.id, projectID: .some(projectID))
        }
    }

    func commitStart() async {
        guard let seconds = DurationText.parseTimeOfDay(startText) else {
            resetTimeFields()
            return
        }
        await commit(.start(seconds))
    }

    func commitStop() async {
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
            let others = await (try? store.overlaps(for: draft, excluding: entry.id)) ?? []
            let chain = await Set(((try? store.chain(of: entry.id)) ?? []).map(\.id))
            if let other = others.first(where: { !chain.contains($0.id) }) {
                overlap = await OverlapNotice(text: overlapText(other), change: result)
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
        let edited = task != entry.task || startText != Self.time(entry.start) || stopText != stopDisplay
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
            message = error.localizedDescription
        }
    }

    // MARK: Helpers

    private func store(_ result: EntryEditResult) async {
        let old = entry
        await perform(undo: old) { [store, entry] in
            try await store.update(entry.id, result.change)
        }
    }

    private func perform(undo old: TimeEntry, _ write: @Sendable () async throws -> [TimeEntry]) async {
        do {
            let pieces = try await write()
            if let first = pieces.first(where: { $0.id == old.id }) ?? pieces.first {
                entry = first
            }
            registerUndo(restoring: old)
            task = entry.task
            resetTimeFields()
            await loadChain()
            if let listing = try? await store.listings(for: [entry]).first {
                label = ProjectLabel(listing)
            }
            await onChange?()
        } catch {
            message = error.localizedDescription
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
        entry.end.map(Self.time) ?? "running"
    }

    private func resetTimeFields() {
        startText = Self.time(entry.start)
        stopText = stopDisplay
        durationText = DurationText.clock(entry.seconds(at: clock.now))
        date = entry.start
    }

    private func loadChain() async {
        guard let chain = try? await store.chain(of: entry.id), let index = chain.firstIndex(where: { $0.id == entry.id }) else {
            chainLines = []
            return
        }
        var lines: [String] = []
        if index > 0 {
            let previous = chain[index - 1]
            lines.append("Continued from \(Self.day(previous.start)), \(Self.time(previous.start))")
        }
        if index + 1 < chain.count {
            let next = chain[index + 1]
            let until = next.end.map(Self.time) ?? "now"
            lines.append("Continues on \(Self.day(next.start)) until \(until)")
        }
        chainLines = lines
    }

    private func overlapText(_ other: TimeEntry) async -> String {
        var name = other.task
        if name.isEmpty, let listing = try? await store.listings(for: [other]).first {
            name = listing.project?.name ?? "No task"
        }
        let end = other.end.map(Self.time) ?? "now"
        return "Overlaps “\(name)” (\(Self.time(other.start)) to \(end))"
    }

    /// The time of day in the system's 12- or 24-hour format.
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Thu, Oct 29".
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
