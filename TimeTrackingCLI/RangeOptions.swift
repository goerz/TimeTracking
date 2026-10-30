// RangeOptions: the range options of entries, report, and export
// (spec_automation.md §3.2).

import ArgumentParser
import Foundation
import TimeTrackingCore

/// `--from`, `--to`, `--day`, `--week`, `--month`, `--all-time`.
struct RangeOptions: ParsableArguments {
    @Option(help: ArgumentHelp("First day (2026-10-29, 2026-W44, 2026-10, today, -3d, ...).", valueName: "date"))
    var from: String?

    @Option(help: ArgumentHelp("First day excluded.", valueName: "date"))
    var to: String?

    @Option(help: ArgumentHelp("One day.", valueName: "date"))
    var day: String?

    @Option(help: ArgumentHelp("One week, Monday to Sunday.", valueName: "date"))
    var week: String?

    @Option(help: ArgumentHelp("One month.", valueName: "date"))
    var month: String?

    @Flag(name: .customLong("all-time"), help: "Allow a range over 366 days; without a range, all time.")
    var allTime = false

    var isEmpty: Bool {
        from == nil && to == nil && day == nil && week == nil && month == nil && !allTime
    }

    /// The range, or `defaultRange` when none is given; `nil` for all time.
    func resolve(_ service: AutomationService, default defaultRange: DayRange?) throws(AutomationError) -> DayRange? {
        let calendar = service.calendar
        let now = service.now
        func parse(_ text: String?) throws(AutomationError) -> DateArgument? {
            guard let text else {
                return nil
            }
            return try DateArgument.parse(text, now: now, calendar: calendar)
        }
        return try DayRange.resolve(
            from: parse(from),
            to: parse(to),
            day: parse(day),
            week: parse(week),
            month: parse(month),
            allTime: allTime,
            defaultRange: defaultRange,
            now: now,
            calendar: calendar
        )
    }
}
