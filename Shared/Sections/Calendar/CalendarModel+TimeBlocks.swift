// Time blocks: drawing, editing, moving, deleting with undo, and the
// Calendar settings (calendar.md §4.1, §4.2, §6).

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

    /// Moves a block whole (all pieces of one crossing the day change) by
    /// `offset`, from the column `source` onto `day`, unlimited by the
    /// now-line. With `option` it snaps to the minute.
    func moveTimeBlock(
        _ id: CalendarEvent.ID,
        by offset: TimeInterval,
        to day: TrackingDay? = nil,
        from source: TrackingDay? = nil,
        option: Bool = false
    ) async {
        guard let block = timeBlocks.first(where: { $0.id == id }) else {
            return
        }
        await updateTimeBlock(block, interval: movedInterval(of: block, by: offset, to: day, from: source, option: option))
    }

    /// Where a body drag puts `block`, which the card's time label shows
    /// while it lasts.
    func movedInterval(
        of block: TimeBlock,
        by offset: TimeInterval,
        to day: TrackingDay? = nil,
        from source: TrackingDay? = nil,
        option: Bool = false
    ) -> DateInterval {
        let source = source ?? calendar.day(containing: block.event.start)
        let dayShift = calendar.startOfDay(day ?? source).timeIntervalSince(calendar.startOfDay(source))
        let start = block.event.start + dayShift + offset
        let dayStart = calendar.startOfDay(calendar.day(containing: start))
        let snapped = CalendarSnap(minutes: option ? 1 : snapMinutes).snap(start, dayStart: dayStart)
        return DateInterval(start: snapped, duration: block.event.interval.duration)
    }

    /// Resizes a block's top or bottom edge within the column `day`, by
    /// default the one the edge is in. With `option` it snaps to the minute.
    func resizeTimeBlock(_ id: CalendarEvent.ID, top: Bool, to date: Date, on day: TrackingDay? = nil, option: Bool = false) async {
        guard let block = timeBlocks.first(where: { $0.id == id }) else {
            return
        }
        let column = day ?? calendar.day(containing: top ? block.event.start : block.event.end - 1)
        let editing = editing(column, option: option, limitToNow: false)
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

    // MARK: Settings (§6)

    /// Shows or hides sleep or workouts on every device; the iPhone imports
    /// while either is on.
    func setShowHealth(_ kind: HealthPeriod.Kind, _ isOn: Bool) async {
        do {
            switch kind {
            case .sleep:
                try await store.set(.calendarShowSleep, isOn)
                showSleep = isOn
            case .workout:
                try await store.set(.calendarShowWorkouts, isOn)
                showWorkouts = isOn
            }
        } catch {
            report(error)
        }
        await reload()
    }

    func setSnapMinutes(_ minutes: Int) async {
        let value = CalendarSnap.choices.contains(minutes) ? minutes : 5
        do {
            try await store.set(.calendarSnapMinutes, value)
            snapMinutes = value
        } catch {
            report(error)
        }
    }

    /// The checklist: every event calendar except the time-block calendar, by account.
    var calendarChoices: [(account: String, calendars: [CalendarInfo])] {
        let others = calendars.filter { $0.id != timeBlockCalendar?.id }
        return Dictionary(grouping: others, by: \.sourceTitle)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted { $0.title < $1.title }) }
    }

    /// Checks or unchecks one calendar; checked calendars this device does
    /// not have stay in the synced list.
    func setShown(_ calendar: CalendarInfo, _ shown: Bool) async {
        var choices = shownCalendars.filter { $0 != calendar.choice }
        if shown {
            choices.append(calendar.choice)
        }
        do {
            try await store.set(.calendarShownCalendars, choices)
            shownCalendars = choices
        } catch {
            report(error)
        }
        await reload()
    }

    /// "Hide This Calendar" on an event.
    func hideCalendar(of event: CalendarEvent) async {
        if let calendar = calendars.first(where: { $0.id == event.calendarID }) {
            await setShown(calendar, false)
        }
    }

    /// Whether calendar access was granted, as of the last resolution.
    var hasCalendarAccess: Bool {
        timeBlockState != nil && timeBlockState != .noAccess
    }

    var timeBlockCalendar: CalendarInfo? {
        if case let .ready(calendar) = timeBlockState {
            return calendar
        }
        return nil
    }

    /// The time-block calendar's menu: the writable calendars of the iCloud account.
    var timeBlockCalendarChoices: [CalendarInfo] {
        TimeBlockCalendar.choices(store: events)
    }

    /// Makes `calendar` the time-block calendar on every device.
    func chooseTimeBlockCalendar(_ calendar: CalendarInfo) async {
        guard calendar.id != timeBlockCalendar?.id else {
            return
        }
        await apply(TimeBlockCalendar.choose(calendar))
        await loadSettings()
        await reload()
    }

    /// "New Calendar…": a new calendar in the iCloud account; updates the setting.
    func recreateTimeBlockCalendar() async {
        await apply(TimeBlockCalendar.recreate(store: events))
        await loadSettings()
        await reload()
    }
}
