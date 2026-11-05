// ToolFormat: times, dates, durations, and entry descriptions of the
// human-readable output, which may change between versions
// (spec_automation.md §1, §3).

import Foundation
import TimeTrackingCore

/// Times, dates, durations, and entry descriptions in the system zone.
nonisolated enum ToolFormat {
    static func time(_ date: Date, _ zone: TimeZone) -> String {
        String(ReportCSVWriter.timestamp(date, in: zone).dropFirst(11).prefix(5))
    }

    static func date(_ date: Date, _ zone: TimeZone) -> String {
        String(ReportCSVWriter.timestamp(date, in: zone).prefix(10))
    }

    static func duration(_ seconds: Int) -> String {
        ReportCSVWriter.duration(seconds)
    }

    static func hours(_ seconds: Int) -> String {
        String(format: "%.2f", Double(seconds) / 3600)
    }

    /// `"Clarify noise model" on Noise paper`, `"Task"`, `Noise paper`, or `an entry`.
    static func subject(_ listing: EntryListing) -> String {
        let task = listing.entry.task
        switch (task.isEmpty, listing.project?.name) {
        case let (false, name?): return "\"\(task)\" on \(name)"
        case (false, nil): return "\"\(task)\""
        case let (true, name?): return name
        case (true, nil): return "an entry"
        }
    }

    /// The table of entries with a subtotal at each change of shown day;
    /// a row keeps the real date of its start.
    static func entriesTable(_ listings: [EntryListing], now: Date, calendar: TrackingCalendar, colors: Bool, total: Int? = nil) -> String {
        let zone = calendar.timeZone
        var table = TextTable(headers: ["Date", "Start", "End", "Duration", "Project", "Client", "Task"], rightAligned: [3])
        var day: TrackingDay?
        var subtotal = 0
        func closeDay() {
            if let day {
                table.add(["", "", "", duration(subtotal), "", "", "Subtotal \(day)"])
                table.rule()
            }
        }
        for listing in listings {
            let entry = listing.entry
            let shownDay = calendar.day(containing: entry.start)
            if shownDay != day {
                closeDay()
                day = shownDay
                subtotal = 0
            }
            subtotal += entry.seconds(at: now)
            table.add([
                date(entry.start, zone), time(entry.start, zone), entry.end.map { time($0, zone) } ?? "running",
                duration(entry.seconds(at: now)),
                listing.project?.name ?? "", listing.client?.name ?? "", entry.task,
            ])
        }
        if listings.count > 1 {
            closeDay()
        }
        if let total {
            table.add(["", "", "", duration(total), "", "", "Total"])
        }
        return table.render(colors: colors)
    }
}
