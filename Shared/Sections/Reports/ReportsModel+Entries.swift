// ReportsModel+Entries: the entry list's order and commands, exports, and
// copying rows (reports.md §6, §7).

import Foundation
import TimeTrackingCore

extension ReportsModel {
    // MARK: Entry list

    /// The listed entries in the list's sort order.
    var listings: [EntryListing] {
        let listings = snapshot?.entries.listings ?? []
        let now = clock.now
        let ascending = state.listAscending
        func key(_ listing: EntryListing) -> String {
            switch state.listSort {
            case .date, .start: String(format: "%015.0f", listing.entry.start.timeIntervalSince1970)
            case .stop: String(format: "%015.0f", (listing.entry.end ?? .distantFuture).timeIntervalSince1970)
            case .duration: String(format: "%012d", listing.entry.seconds(at: now))
            case .client: listing.client?.name.folded ?? ""
            case .project: listing.project?.name.folded ?? ""
            case .task: listing.entry.task.folded
            }
        }
        return listings.sorted { lhs, rhs in
            let left = (key(lhs), lhs.entry.start, lhs.id)
            let right = (key(rhs), rhs.entry.start, rhs.id)
            return ascending ? left < right : left > right
        }
    }

    func sortList(by column: EntryListColumn) {
        if state.listSort == column {
            state.listAscending.toggle()
        } else {
            state.listSort = column
            state.listAscending = column != .date && column != .start && column != .duration
        }
    }

    /// "Total 18h 50m 14s · 22 entries".
    func listFooter(at now: Date) -> String {
        let entries = snapshot?.entries
        let count = entries?.listings.count ?? 0
        return "Total \(ReportText.seconds(entries?.totalSeconds(at: now) ?? 0)) · \(count) \(count == 1 ? "entry" : "entries")"
    }

    /// ↩, double-click, and "Edit…": the Timer's edit popover.
    func edit(_ id: EntryID) {
        editing = id
    }

    /// The popover saved an edit: tiles, chart, and table follow.
    func editorChanged() async {
        await entriesChanged()
        await reload()
    }

    /// "Continue".
    func continueListing(_ id: EntryID) async {
        await continueEntry(id)
        await reload()
    }

    /// "Show in Calendar".
    func showInCalendar(_ listing: EntryListing) {
        router?.showCalendar(day: listing.entry.day)
    }

    // MARK: Export

    /// "Report 2026-10-26 to 2026-11-01.csv" or "Entries …".
    func exportFileName(entries: Bool) -> String {
        let days = range.days
        return "\(entries ? "Entries" : "Report") \(days.lowerBound) to \(days.upperBound).csv"
    }

    /// Export… and File › Export… (⇧⌘E): the card shown.
    func requestExport() {
        exportRequested = true
    }

    /// The shown card's CSV and file name.
    var exportDocument: CSVDocument {
        let entries = state.card == .entries
        return CSVDocument(text: entries ? entriesCSV : breakdownCSV, name: exportFileName(entries: entries))
    }

    /// Breakdown (CSV): the library writer the tool uses.
    var breakdownCSV: String {
        snapshot?.breakdownCSV ?? ""
    }

    /// Entries (CSV).
    var entriesCSV: String {
        snapshot?.entriesCSV() ?? ""
    }

    /// ⌘C (reports.md §7): the selected rows of the card that
    /// shows, with times as the list shows them.
    func copySelectedRows() -> String {
        switch state.card {
        case .breakdown: copyBreakdownRows()
        case .entries: copyListRows { $0.formatted(date: .omitted, time: .shortened) }
        }
    }

    /// ⌘C on table rows: the visible columns, levels in separate columns.
    func copyBreakdownRows() -> String {
        let total = snapshot?.tree.seconds ?? 0
        return breakdownRows.filter { tableSelection.contains($0.path) }.map { row in
            var columns = Array(repeating: "", count: state.levels.count)
            for index in row.path.indices {
                if let node = snapshot?.tree.node(at: Array(row.path[...index])) {
                    columns[index] = node.displayName(level: state.levels[index])
                }
            }
            return (columns + [
                ReportText.seconds(row.node.seconds), ReportText.share(row.node.seconds, of: total), String(row.node.entryCount),
            ]).joined(separator: "\t")
        }
        .joined(separator: "\n")
    }

    /// ⌘C on list rows.
    func copyListRows(timeText: (Date) -> String) -> String {
        let now = clock.now
        return listings.filter { listSelection.contains($0.id) }.map { listing in
            [
                DayText.weekdayShortDate(listing.entry.day), timeText(listing.entry.start),
                listing.entry.end.map(timeText) ?? "running", ReportText.seconds(listing.entry.seconds(at: now)),
                listing.client?.name ?? "–", listing.project?.name ?? "–", listing.entry.task,
            ].joined(separator: "\t")
        }
        .joined(separator: "\n")
    }
}
