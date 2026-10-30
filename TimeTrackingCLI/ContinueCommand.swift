// status, start, stop, continue (spec_automation.md §3.5).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct ContinueCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "continue",
        abstract: "Start a new entry with the task and project of the latest entry, a given entry, or the latest match."
    )

    @Option(name: .customLong("entry-id"), help: ArgumentHelp("Continue this entry.", valueName: "uuid"))
    var entryID: String?

    @Option(help: ArgumentHelp("Continue the latest entry of this project.", valueName: "name"))
    var project: String?

    @Option(help: ArgumentHelp("The project's client.", valueName: "name"))
    var client: String?

    @Option(help: ArgumentHelp("Continue the latest entry whose task contains this text.", valueName: "text"))
    var task: String?

    @OptionGroup var global: GlobalOptions

    func validate() throws {
        if [entryID, project, task].compactMap(\.self).count > 1 {
            throw ValidationError("Give at most one of --entry-id, --project, --task.")
        }
    }

    func run() async throws {
        let context = ToolContext(global)
        let service = try await context.service(writing: true)
        let source: AutomationService.ContinueSource = if let entryID {
            try await .entry(service.store.resolveEntry(entryID).id)
        } else if let project {
            try await .project(service.store.resolveProject(project, client: client, includeArchived: true).project.id)
        } else if let task {
            .task(task)
        } else {
            .latest
        }
        let result = try await service.continue(source)
        try context.changed(StartCommand.line(result, zone: context.timeZone)) {
            AutomationRecords.entry(result.entry, now: service.now, timeZone: context.timeZone)
        }
    }
}
