// entries and entry show|create|edit|delete (spec_automation.md §3.6).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct EntriesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "entries",
        abstract: "List the entries starting in a range (default today)."
    )

    @OptionGroup var range: RangeOptions
    @OptionGroup var filter: FilterOptions

    @Flag(help: "Only the running entry, regardless of range.")
    var running = false

    @Option(help: "At most this many entries.")
    var limit: Int?

    @Option(help: "asc or desc (default asc).")
    var order = "asc"

    @OptionGroup var global: GlobalOptions

    func validate() throws {
        guard ["asc", "desc"].contains(order) else {
            throw ValidationError("--order takes asc or desc.")
        }
    }

    func run() async throws {
        let (context, service) = try await ToolContext.open(global, writing: false)
        let today = DayRange(from: service.today, to: service.today.adding(days: 1))
        let range = try running ? nil : range.resolve(service, default: today)
        let filter = try await filter.filter(service)
        let result = try await service.entries(in: range, filter: filter, runningOnly: running, limit: limit, descending: order == "desc")
        let zone = context.timeZone
        try context.emit(
            json: { AutomationRecords.entries(result, timeZone: zone) },
            csv: { ReportCSVWriter.entriesCSV(result.listings, now: result.now, timeZone: zone) },
            text: {
                result.listings.isEmpty ? "No entries."
                    : ToolFormat.entriesTable(
                        result.listings,
                        now: result.now,
                        zone: zone,
                        colors: context.colors,
                        total: result.totalSeconds
                    )
            }
        )
    }
}
