// projects, clients, areas, and the project, area, and client writes
// (automation.md §3.8, §3.9). There is no command to delete them.

import ArgumentParser
import Foundation
import TimeTrackingCore

struct AreasCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "areas", abstract: "List areas by client.")

    @Option(help: ArgumentHelp("Only this client.", valueName: "name"))
    var client: String?

    @Flag(help: "Include retired areas.")
    var retired = false

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let (context, service) = try await ToolContext.open(global, writing: false)
        let areas = try await service.areas(client: client, includeRetired: retired)
        try context.emit(
            json: { AutomationRecords.areas(areas) },
            csv: { ReportCSVWriter.areasCSV(areas.map(\.area), clients: areas.compactMap(\.client)) },
            text: {
                var table = TextTable(headers: ["Area", "Client", "Color", "Retired", "Active projects"], rightAligned: [4])
                for summary in areas {
                    table.add([
                        summary.area.name + (summary.area.isGeneral ? " (general)" : ""), summary.client?.name ?? "",
                        summary.area.color.uppercased(), summary.area.isRetired ? "yes" : "", String(summary.activeProjectCount),
                    ])
                }
                return table.render(colors: context.colors)
            }
        )
    }
}
