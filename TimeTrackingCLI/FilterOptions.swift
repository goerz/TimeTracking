// FilterOptions: the name filter options of entries, report, and export
// (automation.md §3.6, §3.7).

import ArgumentParser
import Foundation
import TimeTrackingCore

/// `--project`, `--client`, `--area`, `--task`, `--no-project`.
struct FilterOptions: ParsableArguments {
    @Option(help: ArgumentHelp("Only this project (a name or Client/Project).", valueName: "name"))
    var project: String?

    @Option(help: ArgumentHelp("Only this client.", valueName: "name"))
    var client: String?

    @Option(help: ArgumentHelp("Only this area.", valueName: "name"))
    var area: String?

    @Option(help: ArgumentHelp("Only tasks containing this text.", valueName: "text"))
    var task: String?

    @Flag(name: .customLong("no-project"), help: "Only entries without a project.")
    var noProject = false

    func filter(_ service: AutomationService) async throws(AutomationError) -> EntryFilter {
        try await service.filter(project: project, client: client, area: area, task: task, noProject: noProject)
    }
}
