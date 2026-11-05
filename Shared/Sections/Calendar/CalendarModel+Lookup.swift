// The Calendar model's lookups: entries, projects, labels, and calendar
// colors by identifier (spec_calendar.md §2, §4.3).

import Foundation
import TimeTrackingCore

extension CalendarModel {
    /// The color of an external event's calendar.
    func color(of event: CalendarEvent) -> String {
        calendars.first { $0.id == event.calendarID }?.color ?? "#8E8E93"
    }

    func listing(_ id: EntryID) -> EntryListing? {
        entries.first { $0.entry.id == id }
    }

    func project(_ id: ProjectID?) -> Project? {
        id.flatMap { id in projects.first { $0.id == id } }
    }

    /// The chip label of a project: name, client, area, color.
    func label(_ id: ProjectID?) -> ProjectLabel {
        id.flatMap { projectRows[$0] }.map(ProjectLabel.init) ?? .noProject
    }

    /// The label of a time block's linked project, with its area color;
    /// `nil` for an unlinked block (§4.2).
    func label(of block: TimeBlock) -> ProjectLabel? {
        block.link.projectID.flatMap { projectRows[$0] }.map(ProjectLabel.init)
    }

    /// Waits for a pending undo (tests).
    func waitForUndo() async {
        await pendingUndo?.value
    }
}
