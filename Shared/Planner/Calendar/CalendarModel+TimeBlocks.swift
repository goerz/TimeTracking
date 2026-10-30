// Time blocks: drawing, editing, moving, deleting with undo, and the
// calendar options (spec_planner_calendar.md §4.1, §4.2, §7).

import Foundation
import TimeTrackingCore

/// The block editor's fields (title, project, start, end, notes).
struct TimeBlockDraft: Equatable {
    /// The event being edited, `nil` for a new block.
    var eventID: CalendarEvent.ID?
    var title: String
    var projectID: ProjectID?
    var interval: DateInterval
    var notes: String
}

extension CalendarModel {
    /// Drawing works only with a time-block calendar.
    var canDrawTimeBlocks: Bool {
        timeBlockCalendar != nil
    }

    /// A drag in empty space of the Calendar column (not limited to the past).
    func drawTimeBlock(on day: TrackingDay, from: Date, to: Date, option: Bool = false) {
        guard canDrawTimeBlocks,
              case let .interval(interval) = editing(day, option: option, limitToNow: false).draw(from: from, to: to)
        else {
            return
        }
        blockDraft = TimeBlockDraft(title: "", projectID: nil, interval: interval, notes: "")
    }

    /// Return or a double-click on a block.
    func editTimeBlock(_ block: TimeBlock) {
        blockDraft = TimeBlockDraft(
            eventID: block.id,
            title: block.title,
            projectID: block.link.projectID,
            interval: block.event.interval,
            notes: block.event.notes ?? ""
        )
    }

    /// Return in the editor: creates or updates the event; the URL is the
    /// only link written, notes are kept as typed.
    func saveTimeBlock() async {
        guard let draft = blockDraft, let calendar = timeBlockCalendar else {
            return
        }
        blockDraft = nil
        let fields = TimeBlock.draft(
            calendarID: calendar.id,
            title: draft.title,
            project: draft.projectID,
            interval: draft.interval,
            notes: draft.notes.isEmpty ? nil : draft.notes,
            scheme: urlScheme
        )
        do {
            if let id = draft.eventID, let old = timeBlocks.first(where: { $0.id == id })?.event {
                let updated = try events.update(id, fields)
                registerEventUndo("Undo Edit Time Block") { store in _ = try store.update(updated.id, old.draft) }
            } else {
                let created = try events.create(fields)
                registerEventUndo("Undo New Time Block") { store in try store.remove(created.id) }
            }
        } catch {
            report(error)
        }
        await reload()
    }

    /// Moves a block (both pieces of one crossing midnight) by `offset`,
    /// unlimited by the now-line.
    func moveTimeBlock(_ id: CalendarEvent.ID, by offset: TimeInterval) async {
        guard let block = timeBlocks.first(where: { $0.id == id }) else {
            return
        }
        let day = calendar.day(containing: block.event.start)
        let snapped = CalendarSnap(minutes: snapMinutes).snap(block.event.start + offset, dayStart: calendar.startOfDay(day))
        await updateTimeBlock(block, interval: DateInterval(start: snapped, duration: block.event.interval.duration))
    }

    /// Resizes a block's top or bottom edge.
    func resizeTimeBlock(_ id: CalendarEvent.ID, top: Bool, to date: Date) async {
        guard let block = timeBlocks.first(where: { $0.id == id }) else {
            return
        }
        let editing = editing(calendar.day(containing: top ? block.event.start : block.event.end - 1), limitToNow: false)
        let interval = block.event.interval
        await updateTimeBlock(block, interval: top ? editing.resizeStart(interval, to: date) : editing.resizeEnd(interval, to: date))
    }

    private func updateTimeBlock(_ block: TimeBlock, interval: DateInterval) async {
        var fields = block.event.draft
        fields.start = interval.start
        fields.end = interval.end
        do {
            let updated = try events.update(block.id, fields)
            let old = block.event.draft
            registerEventUndo("Undo Move Time Block") { store in _ = try store.update(updated.id, old) }
        } catch {
            report(error)
        }
        await reload()
    }

    /// Delete or ⌫ on blocks; ⌘Z saves an identical event again.
    func deleteTimeBlocks(_ ids: [CalendarEvent.ID]) async {
        let removed = timeBlocks.filter { ids.contains($0.id) }.map(\.event.draft)
        for id in ids {
            do {
                try events.remove(id)
            } catch {
                report(error)
            }
        }
        registerEventUndo("Undo Delete Time Block") { store in
            for fields in removed {
                _ = try store.create(fields)
            }
        }
        selection.subtract(ids.map(CalendarItemID.timeBlock))
        blockDraft = nil
        await reload()
    }

    private func registerEventUndo(_ name: String, _ undo: @escaping @Sendable (any CalendarEventStore) throws -> Void) {
        guard let undoManager else {
            return
        }
        undoManager.registerUndo(withTarget: self) { model in
            model.pendingUndo = Task { @MainActor in
                do {
                    try undo(model.events)
                } catch {
                    model.report(error)
                }
                await model.reload()
            }
        }
        undoManager.setActionName(String(name.dropFirst("Undo ".count)))
    }

    // MARK: Options (§7)

    func setSnapMinutes(_ minutes: Int) async {
        try? await store.set(.calendarSnapMinutes, CalendarSnap.choices.contains(minutes) ? minutes : 5)
        await reload()
    }

    func setFillMinMinutes(_ minutes: Int) async {
        try? await store.set(.fillMinMinutes, min(30, max(1, minutes)))
        await reload()
    }

    func setTrainDays(_ days: Int) async {
        try? await store.set(.trainDays, min(730, max(30, days)))
        await reload()
    }

    /// The checklist: every event calendar except the time-block calendar, by account.
    var calendarChoices: [(account: String, calendars: [CalendarInfo])] {
        let others = calendars.filter { $0.id != timeBlockCalendar?.id }
        return Dictionary(grouping: others, by: \.sourceTitle)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted { $0.title < $1.title }) }
    }

    func setShown(_ calendar: CalendarInfo, _ shown: Bool) async {
        shownCalendars.removeAll { $0 == calendar.choice }
        if shown {
            shownCalendars.append(calendar.choice)
        }
        await reload()
    }

    /// "Hide This Calendar" on an event.
    func hideCalendar(of event: CalendarEvent) async {
        if let calendar = calendars.first(where: { $0.id == event.calendarID }) {
            await setShown(calendar, false)
        }
    }

    /// "Create New Calendar": a new calendar in the iCloud account; updates the setting.
    func recreateTimeBlockCalendar() async {
        let resolution = TimeBlockCalendar.recreate(store: events)
        if let id = resolution.settingToWrite {
            try? await store.set(.timeBlockCalendarID, id)
            device[.calendarTimeBlockCalendar] = id
        }
        await reload()
    }

    /// The titles of events and time blocks over the training window.
    func trainingTitles() -> [SuggestionCalendarTitle] {
        guard events.access() == .fullAccess else {
            return []
        }
        let now = clock.now
        let window = DateInterval(start: now - Double(trainDays) * 86_400, end: now)
        let ids = Set([timeBlockCalendar?.id].compactMap(\.self) + calendars.filter { shownCalendars.contains($0.choice) }.map(\.id))
        let found = (try? events.events(in: window, calendarIDs: ids)) ?? []
        return found.map { SuggestionCalendarTitle(title: $0.title, interval: $0.interval) }
    }

    /// "Relearn Suggestions": rebuilds the index.
    func rebuildIndex() async {
        await engine.rebuild(titles: trainingTitles())
    }
}
