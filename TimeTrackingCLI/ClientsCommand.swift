// projects, clients, areas, and the project, area, and client writes
// (automation.md §3.8, §3.9). There is no command to delete them.

import ArgumentParser
import Foundation
import TimeTrackingCore

struct ClientsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "clients", abstract: "List clients alphabetically.")

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let (context, service) = try await ToolContext.open(global, writing: false)
        let clients = try await service.clients()
        try context.emit(
            json: { AutomationRecords.clients(clients) },
            csv: { ReportCSVWriter.clientsCSV(clients.map(\.client)) },
            text: {
                var table = TextTable(headers: ["Client", "Areas", "Active projects"], rightAligned: [1, 2])
                for summary in clients {
                    table.add([summary.client.name, String(summary.areaCount), String(summary.activeProjectCount)])
                }
                return table.render(colors: context.colors)
            }
        )
    }
}
