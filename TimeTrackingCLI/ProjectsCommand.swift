// projects, clients, areas, and the project, area, and client writes
// (spec_automation.md §3.8, §3.9). There is no command to delete them.

import ArgumentParser
import Foundation
import TimeTrackingCore

struct ProjectsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "projects", abstract: "List projects (default active).")

    @Flag(help: "Active projects (default).")
    var active = false

    @Flag(help: "Archived projects.")
    var archived = false

    @Flag(help: "Active and archived projects.")
    var all = false

    @Option(help: ArgumentHelp("Only this client.", valueName: "name"))
    var client: String?

    @Option(help: ArgumentHelp("Only this area.", valueName: "name"))
    var area: String?

    @Option(help: "name, client, area, or last-entry (default client).")
    var sort = "client"

    @OptionGroup var global: GlobalOptions

    func validate() throws {
        if [active, archived, all].count(where: \.self) > 1 {
            throw ValidationError("Give one of --active, --archived, --all.")
        }
        if AutomationService.ProjectSort(rawValue: sort) == nil {
            throw ValidationError("--sort takes name, client, area, or last-entry.")
        }
    }

    func run() async throws {
        let (context, service) = try await ToolContext.open(global, writing: false)
        let state: ProjectFilter.State = all ? .all : archived ? .archived : .active
        let rows = try await service.projects(
            state: state,
            client: client,
            area: area,
            sort: AutomationService.ProjectSort(rawValue: sort) ?? .client
        )
        let zone = context.timeZone
        try context.emit(
            json: { AutomationRecords.projects(rows, timeZone: zone) },
            csv: { ReportCSVWriter.projectsCSV(rows, timeZone: zone) },
            text: {
                var table = TextTable(headers: ["Project", "Client", "Area", "Color", "State", "Last entry"])
                for row in rows {
                    table.add([
                        row.project.name, row.client?.name ?? "", row.area?.name ?? "", row.area?.color.uppercased() ?? "",
                        row.project.isArchived ? "archived" : "active", row.lastUsed.map { ToolFormat.date($0, zone) } ?? "",
                    ])
                }
                return table.render(colors: context.colors)
            }
        )
    }
}
