// Entries from activity blocks, time blocks, and events; Add Entry, Start
// Timer Now, rules from a block, and Delete This Activity (spec_planner_calendar.md
// §3.2 to §3.4, §4.4, §5.3).

import Foundation
import TimeTrackingCore

extension CalendarModel {
    /// The query for `interval` of `block` (with a covering event's title).
    func query(for blocks: [ActivityBlock], interval: DateInterval) -> SuggestionQuery {
        let previous = entries.filter { $0.entry.end.map { $0 <= interval.start } ?? false }.max { $0.entry.start < $1.entry.start }
        let titles = (timeBlocks.map(\.event) + externalEvents).map { SuggestionCalendarTitle(title: $0.title, interval: $0.interval) }
        return SuggestionQuery(
            blocks: blocks,
            interval: interval,
            calendarTitle: SuggestionCalendarTitle.covering(interval, in: titles),
            previousProject: previous?.entry.projectID,
            previousKnown: previous != nil,
            timeZone: calendar.timeZone
        )
    }

    /// The candidates for a block (the hover popover's "Suggested").
    func suggestions(for block: ActivityBlock) async -> [SuggestionCandidate] {
        await engine.suggest(query(for: [block], interval: DateInterval(start: block.start, end: block.end)), rules: rules)
    }

    /// The block's longest untracked stretch, clamped at now (§3.3).
    func untrackedStretch(of block: ActivityBlock) -> DateInterval? {
        let tracked = entries.map { $0.entry.interval(at: clock.now) }
        return CalendarCoverage.longestUntracked(
            DateInterval(start: block.start, end: max(block.start, block.end)),
            entries: tracked,
            now: clock.now
        )
    }

    /// The parts of `block` covered by entries (dimmed to 50 %).
    func coveredParts(of block: ActivityBlock) -> [DateInterval] {
        CalendarCoverage.covered(
            DateInterval(start: block.start, end: max(block.start, block.end)),
            by: entries.map { $0.entry.interval(at: clock.now) }
        )
    }

    /// "+", a drag into Tracked, Create Entry…, and Space: a provisional
    /// entry over the longest untracked stretch with the top suggestion.
    func createEntry(from block: ActivityBlock) async {
        guard let stretch = untrackedStretch(of: block) else {
            notice = CalendarNotice(text: CalendarEditing.futureNotice, duration: 3)
            return
        }
        let query = query(for: [block], interval: stretch)
        let candidates = await engine.suggest(query, rules: rules)
        let top = candidates.first.flatMap { $0.isConfident ? $0 : nil }
        draft = CalendarDraft(
            day: TrackingDay(block.localDay) ?? calendar.day(containing: stretch.start),
            interval: stretch,
            projectID: top?.projectID,
            task: top?.task ?? "",
            candidates: candidates,
            query: query,
            source: .block(block)
        )
    }

    /// Add Entry: above `suggestAuto` with project and task the entry is created
    /// directly (`accepted`); otherwise the popover opens.
    func log(_ block: ActivityBlock) async {
        guard let stretch = untrackedStretch(of: block) else {
            return
        }
        let query = query(for: [block], interval: stretch)
        let candidates = await engine.suggest(query, rules: rules)
        guard let top = candidates.first, top.logsDirectly else {
            await createEntry(from: block)
            return
        }
        draft = CalendarDraft(
            day: TrackingDay(block.localDay) ?? calendar.day(containing: stretch.start),
            interval: stretch,
            projectID: top.projectID,
            task: top.task ?? "",
            candidates: candidates,
            query: query,
            source: .block(block)
        )
        await commitDraft()
    }

    /// Start Timer Now on the open block: an entry now with the top suggestion.
    func startNow(_ block: ActivityBlock) async {
        let top = await suggestions(for: block).first.flatMap { $0.isConfident ? $0 : nil }
        do {
            _ = try await store.start(projectID: top?.projectID, task: top?.task ?? "", at: clock.now)
        } catch {
            report(error)
        }
        await changed()
    }

    /// Dragging a time block or event into Tracked, or its "+": its interval
    /// clamped at now (refused when entirely future). A time block supplies
    /// its project, else the engine's; an event the engine's, with its title
    /// as fallback task.
    func createEntry(fromEvent event: CalendarEvent, timeBlock: TimeBlock?) async {
        guard event.start < clock.now else {
            notice = CalendarNotice(text: CalendarEditing.futureNotice, duration: 3)
            return
        }
        let day = calendar.day(containing: event.start)
        let interval = DateInterval(
            start: max(event.start, calendar.startOfDay(day)),
            end: min(event.end, clock.now, calendar.interval(of: day).end)
        )
        let blocks = blocks.filter { $0.start < interval.end && $0.end > interval.start }
        var query = query(for: blocks, interval: interval)
        query.calendarTitle = event.title
        var draft = CalendarDraft(day: day, interval: interval, projectID: nil, task: event.title, source: .event(event))
        if let timeBlock {
            draft.source = .timeBlock(timeBlock)
        }
        if let project = timeBlock?.link.projectID {
            draft.projectID = project
        } else {
            let candidates = await engine.suggest(query, rules: rules)
            draft.candidates = candidates
            draft.query = query
            if let top = candidates.first, top.isConfident {
                draft.projectID = top.projectID
                if timeBlock == nil, let task = top.task {
                    draft.task = task
                }
            }
        }
        self.draft = draft
    }

    /// Space on the selection: an entry from the selected block, time block, or event.
    func createEntryFromSelection() async {
        for item in selection {
            switch item {
            case let .block(id):
                if let block = blocks.first(where: { $0.id == id }) {
                    await createEntry(from: block)
                }
            case let .timeBlock(id):
                if let timeBlock = timeBlocks.first(where: { $0.id == id }) {
                    await createEntry(fromEvent: timeBlock.event, timeBlock: timeBlock)
                }
            case let .event(id):
                if let event = externalEvents.first(where: { $0.id == id }) {
                    await createEntry(fromEvent: event, timeBlock: nil)
                }
            case .entry:
                continue
            }
            return
        }
    }

    // MARK: Rules from a block (§5.3)

    /// "Always Suggest for “<name>”": a group-key rule.
    func alwaysUseProject(_ project: ProjectID, for block: ActivityBlock, task: String? = nil) async {
        await setRules(rules + [SuggestionRule(kind: .groupKey, pattern: block.groupKey, projectID: project, task: task)])
    }

    /// "Don't Suggest for “<name>”": a group-key ignore rule.
    func ignoreGroupKey(of block: ActivityBlock) async {
        await setRules(rules + [SuggestionRule(kind: .groupKey, pattern: block.groupKey, ignore: true)])
    }

    func setRules(_ rules: [SuggestionRule]) async {
        do {
            try await store.set(.suggestionRules, rules)
            self.rules = rules
        } catch {
            report(error)
        }
    }

    // MARK: Delete This Activity (§3.4)

    /// Whether the block's menu offers "Delete This Activity…" (Mac, closed blocks).
    func canDeleteFromLog(_ block: ActivityBlock) -> Bool {
        sendTrackerCommand != nil && isRecordingMac && !block.isOpen
    }

    /// Asks first; Delete sends one `delete-block <dev> <s>`.
    func confirmDeleteFromLog(_ block: ActivityBlock) {
        guard canDeleteFromLog(block) else {
            return
        }
        blockToDelete = block
    }

    func deleteBlockFromLog(confirmed: Bool) async {
        guard let block = blockToDelete else {
            return
        }
        blockToDelete = nil
        guard confirmed, let send = sendTrackerCommand else {
            return
        }
        let command = TrackerCommand.deleteBlock(
            device: block.device,
            start: ActivityTimestamp.text(block.start, utcOffset: block.utcOffset)
        )
        if let error = await send(command.line) {
            trackerError = error
        }
    }
}
