// The Tracked column's commands: drawing, moving, resizing, overlaps,
// deleting, splitting, duplicating (calendar.md §2).

import Foundation
import TimeTrackingCore

extension CalendarModel {
    // MARK: Drawing (§2.3)

    /// A finished vertical drag in empty space of the Tracked column.
    func draw(on day: TrackingDay, from: Date, to: Date, option: Bool = false) {
        switch editing(day, option: option).draw(from: from, to: to) {
        case let .interval(interval):
            selection = []
            draft = CalendarDraft(day: day, interval: interval, projectID: nil, task: "")
        case .tooShort:
            selection = []
        case .future:
            notice = CalendarNotice(text: CalendarEditing.futureNotice, duration: 3)
        }
    }

    /// Return in the popover: stores the draft (empty task and no project
    /// allowed). The draft is taken before the first suspension, so a second
    /// commit (Return and the Save button, or Return and a click outside)
    /// finds none; it comes back while the overlap prompt asks.
    func commitDraft() async {
        guard let draft else {
            return
        }
        self.draft = nil
        let neighbors = await neighbors(of: draft.interval, excluding: nil)
        switch OverlapResolution.resolve(draft.interval, neighbors: neighbors) {
        case let .clear(interval), let .trimmedSilently(interval):
            await create(draft, interval: interval)
        case let .ask(prompt):
            self.draft = draft
            pendingOverlap = PendingOverlap(prompt: prompt, action: .create(draft))
        }
    }

    /// Escape removes the draft; a click elsewhere commits it when a project
    /// or task was given.
    func dismissDraft(commit: Bool) async {
        guard let draft else {
            return
        }
        if commit, draft.projectID != nil || !draft.task.trimmed.isEmpty {
            await commitDraft()
        } else {
            self.draft = nil
        }
    }

    private func create(_ draft: CalendarDraft, interval: DateInterval) async {
        do {
            let id = try await store.create(EntryDraft(
                projectID: draft.projectID,
                task: draft.task.trimmed,
                start: interval.start,
                end: interval.end
            )).id
            registerUndo("Undo New Entry") { store in try await store.delete([id]) }
            self.draft = nil
            selection = [.entry(id)]
        } catch {
            self.draft = draft
            report(error)
        }
        await changed()
    }

    // MARK: Moving and resizing (§2.4)

    /// A body drag of `entry` by `offset` from the column `source` onto
    /// `day` (another day's Tracked column moves it there); refused when it
    /// cannot fit before now. With `option` it snaps to the minute.
    func move(
        _ id: EntryID,
        by offset: TimeInterval,
        to day: TrackingDay? = nil,
        from source: TrackingDay? = nil,
        option: Bool = false
    ) async {
        guard let entry = listing(id)?.entry else {
            return
        }
        guard let moved = movedInterval(of: entry, by: offset, to: day, from: source, option: option) else {
            notice = CalendarNotice(text: CalendarEditing.futureNotice, duration: 3)
            return
        }
        await change(id, to: moved, running: entry.isRunning)
    }

    /// Where a body drag puts `entry`, which the card's time label shows
    /// while it lasts; `nil` when it cannot fit before now.
    func movedInterval(
        of entry: TimeEntry,
        by offset: TimeInterval,
        to day: TrackingDay? = nil,
        from source: TrackingDay? = nil,
        option: Bool = false
    ) -> DateInterval? {
        let source = source ?? calendar.displayDay(of: entry)
        let target = day ?? source
        let dayShift = calendar.startOfDay(target).timeIntervalSince(calendar.startOfDay(source))
        if entry.isRunning {
            let column = crossesDayChange(entry) ? calendar.displayDay(of: entry) : target
            return DateInterval(start: editing(column, option: option).moveRunningStart(to: entry.start + offset), end: clock.now)
        }
        let interval = entry.interval(at: clock.now)
        let shifted = DateInterval(start: interval.start + dayShift, duration: interval.duration)
        return crossesDayChange(entry)
            ? editing(target, option: option).moveAcrossDays(shifted, by: offset)
            : editing(target, option: option).move(shifted, by: offset)
    }

    /// Whether `entry` has a piece in more than one column, so no column holds it.
    private func crossesDayChange(_ entry: TimeEntry) -> Bool {
        calendar.pieces(of: entry, at: clock.now).count > 1
    }

    /// An edge drag in the column `day`: the top (`start`) or bottom edge
    /// to `date`. With `option` it snaps to the minute.
    func resize(_ id: EntryID, top: Bool, to date: Date, on day: TrackingDay? = nil, option: Bool = false) async {
        guard let entry = listing(id)?.entry else {
            return
        }
        let editing = editing(day ?? calendar.displayDay(of: entry), option: option)
        if entry.isRunning {
            guard top else {
                return
            }
            await change(id, to: DateInterval(start: editing.moveRunningStart(to: date), end: clock.now), running: true)
            return
        }
        let interval = entry.interval(at: clock.now)
        await change(id, to: top ? editing.resizeStart(interval, to: date) : editing.resizeEnd(interval, to: date))
    }

    /// ⌘↑ / ⌘↓ and ⌥⌘↑ / ⌥⌘↓ on the selected entry.
    func nudgeSelection(steps: Int, lengthen: Bool) async {
        guard let id = selectedEntry, let entry = listing(id)?.entry, !entry.isRunning else {
            return
        }
        if lengthen {
            let last = calendar.pieces(of: entry, at: clock.now).last?.day ?? calendar.displayDay(of: entry)
            await change(id, to: editing(last).lengthen(entry.interval(at: clock.now), steps: steps))
        } else if let moved = movedInterval(of: entry, by: Double(steps * snapMinutes * 60)) {
            await change(id, to: moved)
        }
    }

    /// Applies a move or resize after the overlap check; one undo step.
    func change(_ id: EntryID, to interval: DateInterval, running: Bool = false, force: Bool = false) async {
        guard let entry = listing(id)?.entry else {
            return
        }
        if !force {
            let neighbors = await neighbors(of: interval, excluding: id)
            switch OverlapResolution.resolve(interval, neighbors: neighbors) {
            case .clear:
                break
            case let .trimmedSilently(trimmed):
                await change(id, to: trimmed, running: running, force: true)
                return
            case let .ask(prompt):
                pendingOverlap = PendingOverlap(prompt: prompt, action: .change(id))
                return
            }
        }
        let old = entry
        do {
            if running {
                _ = try await store.update(id, EntryChange(start: interval.start))
            } else if interval.duration == old.interval(at: clock.now).duration {
                _ = try await store.move(id, by: interval.start.timeIntervalSince(old.start))
            } else {
                _ = try await store.update(id, EntryChange(start: interval.start, end: interval.end))
            }
            registerUndo(running ? "Undo Resize Entry" : "Undo Move Entry") { store in
                _ = try await store.update(old.id, EntryChange(start: old.start, end: old.end))
            }
        } catch {
            report(error)
        }
        await changed()
    }

    // MARK: Overlaps (§2.6)

    enum OverlapChoice {
        case trim
        case overlap
        case cancel
    }

    /// Trim (default), Overlap, or Cancel (Escape).
    func resolveOverlap(_ choice: OverlapChoice) async {
        guard let pending = pendingOverlap else {
            return
        }
        pendingOverlap = nil
        let interval: DateInterval? = switch choice {
        case .trim: pending.prompt.trimmed
        case .overlap: pending.prompt.proposed
        case .cancel: nil
        }
        guard let interval else {
            if case .create = pending.action {
                draft = nil
            }
            return
        }
        switch pending.action {
        case let .create(draft):
            await create(draft, interval: interval)
        case let .change(id):
            let running = listing(id)?.entry.isRunning ?? false
            await change(id, to: interval, running: running, force: true)
        case let .duplicate(entry):
            await storeDuplicate(of: entry, interval: interval)
        }
    }

    /// The entries other than `excluded` overlapping `interval`.
    func neighbors(of interval: DateInterval, excluding excluded: EntryID?) async -> [OverlapNeighbor] {
        let draft = EntryDraft(projectID: nil, task: "", start: interval.start, end: interval.end)
        let found = await (try? store.overlaps(for: draft, excluding: excluded)) ?? []
        let listings = await (try? store.listings(for: found)) ?? []
        return listings.map { listing in
            let title = listing.entry.task.isEmpty ? (listing.project?.name ?? "No task") : listing.entry.task
            return OverlapNeighbor(id: listing.entry.id, title: title, interval: listing.entry.interval(at: clock.now))
        }
    }

    /// The entries of `day` drawn side by side, and their lanes.
    func lanes(on day: TrackingDay) -> [EntryID: CalendarLane] {
        CalendarLane.assign(entries(on: day).map { ($0.entry.id, $0.entry.interval(at: clock.now)) })
    }

    /// The entries with a part in the column of `day`; one crossing the
    /// day change is in the column of every day it lies on.
    func entries(on day: TrackingDay) -> [EntryListing] {
        let span = calendar.interval(of: day)
        return entries.filter { listing in
            let entry = listing.entry.interval(at: clock.now)
            return entry.start < span.end && (entry.end > span.start || entry.start >= span.start)
        }
        .sorted { $0.entry.start < $1.entry.start }
    }

    /// The ids of the day's overlapping entries ("⚠ 2 overlaps").
    func overlapping(on day: TrackingDay) -> Set<EntryID> {
        CalendarLane.overlapping(entries(on: day).map { ($0.entry.id, $0.entry.interval(at: clock.now)) })
    }

    /// The tooltip of a card's ⚠ badge: `Overlaps "Standup" by 12 min, …`
    /// for the entries of its day that overlap it (§2.6).
    func overlapHelp(for entry: TimeEntry) -> String {
        let now = clock.now
        let day = entries(on: calendar.displayDay(of: entry))
        let tasks = Dictionary(day.map { ($0.entry.id, $0.entry.task) }, uniquingKeysWith: { first, _ in first })
        let amounts = OverlapAmount.amounts(
            overlapping: entry.interval(at: now),
            of: entry.id,
            among: day.map { ($0.entry.id, $0.entry.interval(at: now)) }
        )
        return "Overlaps " + amounts.map { "\"\(tasks[$0.id] ?? "")\" by \(Int($0.seconds / 60)) min" }.joined(separator: ", ")
    }

    /// A click on the header's warning selects them.
    func selectOverlaps(on day: TrackingDay) {
        selection = Set(overlapping(on: day).map(CalendarItemID.entry))
    }

    // MARK: Selection and deleting (§2.5)

    var selectedEntry: EntryID? {
        for item in selection {
            if case let .entry(id) = item {
                return id
            }
        }
        return nil
    }

    var selectedEntries: [EntryID] {
        selection.compactMap { item in
            if case let .entry(id) = item {
                return id
            }
            return nil
        }
    }

    /// Selects `item`, or with `extend` adds it or takes it out.
    func select(_ item: CalendarItemID, extend: Bool = false) {
        if extend {
            selection.formSymmetricDifference([item])
        } else {
            selection = [item]
        }
    }

    /// A click on a card: ⇧ or ⌘ extends the selection. True for a plain
    /// click.
    @discardableResult
    func click(_ item: CalendarItemID) -> Bool {
        let extend = ModifierState.extendDown()
        select(item, extend: extend)
        return !extend
    }

    /// Tab / ⇧Tab through the visible entries by start.
    func stepSelection(by offset: Int) {
        let ordered = entries.sorted { $0.entry.start < $1.entry.start }.map(\.entry.id)
        guard !ordered.isEmpty else {
            return
        }
        let index = selectedEntry.flatMap { ordered.firstIndex(of: $0) }.map { $0 + offset } ?? (offset > 0 ? 0 : ordered.count - 1)
        selection = [.entry(ordered[(index % ordered.count + ordered.count) % ordered.count])]
    }

    /// Delete or ⌫: the selected entries, or time blocks; the running entry asks first.
    func deleteSelection(confirmed: Bool = false) async {
        let ids = selectedEntries
        let blocks = selection.compactMap { item -> CalendarEvent.ID? in
            if case let .timeBlock(id) = item {
                return id
            }
            return nil
        }
        if !blocks.isEmpty {
            await deleteTimeBlocks(blocks)
        }
        guard !ids.isEmpty else {
            return
        }
        let doomed = ids.compactMap { listing($0)?.entry }
        if doomed.contains(where: \.isRunning), !confirmed {
            confirmsRunningDelete = true
            return
        }
        confirmsRunningDelete = false
        let deletedAt = clock.now
        do {
            try await store.delete(ids)
            // One transaction, so no observer sees the restored entry running.
            let running = doomed.filter(\.isRunning).map(\.id)
            registerUndo("Undo Delete Entry") { store in
                try await store.transaction { transaction in
                    try transaction.restore(ids)
                    for id in running {
                        _ = try transaction.update(id, EntryChange(end: deletedAt))
                    }
                }
            }
            if let first = doomed.first {
                let title = first.task.isEmpty ? "No task" : first.task
                let text = doomed.count == 1
                    ? "Deleted '\(title)' (\(ActivityText.duration(first.seconds(at: deletedAt))))."
                    : "Deleted \(doomed.count) entries."
                notice = CalendarNotice(text: text, duration: 8, deleted: ids)
            }
            selection = []
        } catch {
            report(error)
        }
        await changed()
    }

    // MARK: Split, duplicate, continue (§2.5)

    /// Split Here at `time`, snapped; refused within 1 minute of either end.
    func split(_ id: EntryID, at time: Date) async {
        guard let entry = listing(id)?.entry else {
            return
        }
        let at = CalendarSnap(minutes: snapMinutes).snap(time, dayStart: calendar.startOfDay(entry.day))
        guard CalendarEditing.canSplit(start: entry.start, end: entry.end, at: at, now: clock.now) else {
            notice = CalendarNotice(text: "Can't split within a minute of either end", duration: 3)
            return
        }
        do {
            let (_, later) = try await store.split(id, at: at)
            let end = entry.end ?? later.end
            // One transaction, so the entry is never without its later part.
            registerUndo("Undo Split") { store in
                try await store.transaction { transaction in
                    try transaction.delete([later.id])
                    _ = try transaction.update(entry.id, EntryChange(end: end))
                }
            }
        } catch {
            report(error)
        }
        await changed()
    }

    /// ⌘D: the same time next day as a stopped entry, refused unless entirely past.
    func duplicateSelection() async {
        guard let id = selectedEntry, let entry = listing(id)?.entry else {
            return
        }
        guard let copy = CalendarEditing.duplicateToNextDay(entry.interval(at: clock.now), in: entry.zone, now: clock.now) else {
            notice = CalendarNotice(text: CalendarEditing.futureNotice, duration: 3)
            return
        }
        switch await OverlapResolution.resolve(copy, neighbors: neighbors(of: copy, excluding: nil)) {
        case let .clear(interval), let .trimmedSilently(interval):
            await storeDuplicate(of: entry, interval: interval)
        case let .ask(prompt):
            pendingOverlap = PendingOverlap(prompt: prompt, action: .duplicate(entry))
        }
    }

    private func storeDuplicate(of entry: TimeEntry, interval: DateInterval) async {
        do {
            let id = try await store.create(EntryDraft(
                projectID: entry.projectID,
                task: entry.task,
                start: interval.start,
                end: interval.end
            )).id
            registerUndo("Undo Duplicate") { store in try await store.delete([id]) }
        } catch {
            report(error)
        }
        await changed()
    }

    /// ▶ on a card (stops the running entry, as every start does).
    func continueEntry(_ id: EntryID) async {
        do {
            _ = try await store.continue(id, at: clock.now)
        } catch {
            report(error)
        }
        await changed()
    }

    /// ■ on the running card.
    func stopRunning() async {
        do {
            _ = try await store.stop(at: clock.now)
        } catch {
            report(error)
        }
        await changed()
    }

    // MARK: Helpers

    /// Registers one undo step that runs `undo` on the store and reloads.
    func registerUndo(_ name: String, _ undo: @escaping @Sendable (TimeStore) async throws -> Void) {
        guard let undoManager else {
            return
        }
        undoManager.registerUndo(withTarget: self) { model in
            model.pendingUndo = Task { @MainActor in
                do {
                    try await undo(model.store)
                } catch {
                    model.report(error)
                }
                await model.changed()
            }
        }
        undoManager.setActionName(String(name.dropFirst("Undo ".count)))
    }

    /// Reloads after a write and tells the Timer.
    func changed() async {
        await reload()
        await entriesChanged()
    }
}
