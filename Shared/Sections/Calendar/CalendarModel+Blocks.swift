// CalendarModel+Blocks: entries from activity blocks, time blocks, and
// events, and Delete This Activity (calendar.md §3.3, §3.4, §4.4).

import Foundation
import TimeTrackingCore

extension CalendarModel {
    /// The block's longest untracked stretch, clamped at now (§3.3).
    func untrackedStretch(of block: ActivityBlock) -> DateInterval? {
        let tracked = entries.map { $0.entry.interval(at: clock.now) }
        return CalendarCoverage.longestUntracked(
            block.interval,
            entries: tracked,
            now: clock.now
        )
    }

    /// The parts of `block` in the column of `day` covered by entries
    /// (dimmed to 50 %).
    func coveredParts(of block: ActivityBlock, on day: TrackingDay) -> [DateInterval] {
        guard let shown = block.interval.intersection(with: calendar.interval(of: day)) else {
            return []
        }
        return CalendarCoverage.covered(shown, by: entries.map { $0.entry.interval(at: clock.now) })
    }

    /// "+", a drag into Tracked, Create Entry…, and Space: a provisional
    /// entry over the longest untracked stretch.
    func createEntry(from block: ActivityBlock) {
        guard let stretch = untrackedStretch(of: block) else {
            notice = CalendarNotice(text: CalendarEditing.futureNotice, duration: 3)
            return
        }
        draft = CalendarDraft(
            day: calendar.startOfDayHour == 0 ? block.day : calendar.day(containing: stretch.start),
            interval: stretch,
            projectID: nil,
            task: ""
        )
    }

    /// Dragging a time block or event into Tracked, or its "+": its interval
    /// clamped at now (refused when entirely future), its title as task, and
    /// a time block's linked project.
    func createEntry(fromEvent event: CalendarEvent, timeBlock: TimeBlock?) {
        guard event.start < clock.now else {
            notice = CalendarNotice(text: CalendarEditing.futureNotice, duration: 3)
            return
        }
        let day = calendar.day(containing: event.start)
        let interval = DateInterval(
            start: max(event.start, calendar.startOfDay(day)),
            end: min(event.end, clock.now, calendar.interval(of: day).end)
        )
        draft = CalendarDraft(day: day, interval: interval, projectID: timeBlock?.link.projectID, task: event.title)
    }

    /// Space on the selection: an entry from the selected block, time block, or event.
    func createEntryFromSelection() {
        for item in selection {
            switch item {
            case let .block(id):
                if let block = blocks.first(where: { $0.id == id }) {
                    createEntry(from: block)
                }
            case let .timeBlock(id):
                if let timeBlock = timeBlocks.first(where: { $0.id == id }) {
                    createEntry(fromEvent: timeBlock.event, timeBlock: timeBlock)
                }
            case let .event(id):
                if let event = externalEvents.first(where: { $0.id == id }) {
                    createEntry(fromEvent: event, timeBlock: nil)
                }
            case .entry:
                continue
            }
            return
        }
    }

    // MARK: Delete This Activity (§3.4)

    /// Whether the block's menu offers "Delete This Activity…" (Mac, closed blocks).
    func canDeleteFromLog(_ block: ActivityBlock) -> Bool {
        sendTrackerCommand != nil && isMac && !block.isOpen
    }

    /// Asks first; Delete sends one `delete-block <s> <e>`, the range shown,
    /// which the agent deletes whole even when a tick split the block meanwhile.
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
            start: ActivityTimestamp.textWithOffset(block.start, utcOffset: block.utcOffset),
            end: ActivityTimestamp.textWithOffset(block.end, utcOffset: block.endUTCOffset)
        )
        if let error = await send(command.line) {
            trackerError = error
        }
    }
}
