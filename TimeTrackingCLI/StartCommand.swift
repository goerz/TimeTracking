// status, start, stop, continue (spec_automation.md §3.5).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct StartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start an entry, stopping the running one. Never infers a project."
    )

    @Argument(help: "The task.")
    var task: String?

    @Option(help: ArgumentHelp("The project (a name or Client/Project).", valueName: "name"))
    var project: String?

    @Option(name: .customLong("project-id"), help: ArgumentHelp("The project's id.", valueName: "uuid"))
    var projectID: String?

    @Option(help: ArgumentHelp("The project's client, when its name is ambiguous.", valueName: "name"))
    var client: String?

    @Option(parsing: .unconditional, help: ArgumentHelp("Start time, at most 24 hours back.", valueName: "time"))
    var at: String?

    @Flag(help: "Allow overlapping a stopped entry.")
    var force = false

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let (context, service) = try await ToolContext.open(global, writing: true)
        let at = try service.instant(ifGiven: at)
        let project = try await service.project(name: project, id: projectID, client: client)
        let result = try await service.start(task: task ?? "", projectID: project?.project.id, at: at, force: force)
        context.changed(Self.line(result, zone: context.timeZone)) {
            AutomationRecords.entry(result.entry, now: service.now, timeZone: context.timeZone)
        }
    }

    /// `Started "Task" on Project at 09:15.`, naming the stopped entry too.
    static func line(_ result: StartResult, zone: TimeZone) -> String {
        var line = "Started \(ToolFormat.subject(result.entry)) at \(ToolFormat.time(result.entry.entry.start, zone))."
        if let stopped = result.stopped {
            let seconds = stopped.entry.seconds(at: result.entry.entry.start)
            line += " Stopped \(ToolFormat.subject(stopped)) after \(ToolFormat.duration(seconds))."
        }
        return line
    }
}
