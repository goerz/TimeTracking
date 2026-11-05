// health: the sleep and workout periods the iPhone imports from Apple Health
// (automation.md §3.8).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct HealthCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "health",
        abstract: "List the sleep and workouts imported from Apple Health that start in a range (default today)."
    )

    @OptionGroup var range: RangeOptions

    @Option(help: "workout or sleep (default both).")
    var kind: String?

    @OptionGroup var global: GlobalOptions

    func validate() throws {
        if let kind, HealthPeriod.Kind(rawValue: kind) == nil {
            throw ValidationError("--kind takes workout or sleep.")
        }
    }

    func run() async throws {
        let (context, service) = try await ToolContext.open(global, writing: false)
        let today = DayRange(from: service.today, to: service.today.adding(days: 1))
        let range = try range.resolve(service, default: today)
        let listing = try await service.health(in: range, kind: kind.flatMap(HealthPeriod.Kind.init(rawValue:)))
        let zone = context.timeZone
        try context.emit(json: { listing.json }, csv: { listing.csv }, text: { Self.table(listing, zone: zone, colors: context.colors) })
    }

    /// One row per period, then the last import.
    private static func table(_ listing: HealthListing, zone: TimeZone, colors: Bool) -> String {
        var lines: [String] = []
        if listing.periods.isEmpty {
            lines.append("No sleep or workouts.")
        } else {
            var table = TextTable(headers: ["Date", "Start", "End", "Duration", "Kind", "Activity", "Distance"])
            table.rightAligned = [3, 6]
            for period in listing.periods {
                table.add([
                    ToolFormat.date(period.start, zone),
                    ToolFormat.time(period.start, zone),
                    ToolFormat.time(period.end, zone),
                    ToolFormat.duration(HealthListing.seconds(period)),
                    period.kind.rawValue,
                    period.activity ?? "",
                    period.distance.map { String(format: "%.2f km", Double($0) / 1000) } ?? "",
                ])
            }
            lines.append(table.render(colors: colors))
        }
        if let status = listing.lastImport {
            let kinds = status.kinds.map(\.rawValue).joined(separator: ", ")
            let time = "\(ToolFormat.date(status.date, zone)) \(ToolFormat.time(status.date, zone))"
            lines.append("Last import: \(time) on \(status.device) (\(kinds))")
        } else {
            lines.append("Last import: none recorded")
        }
        return lines.joined(separator: "\n")
    }
}
