// status, start, stop, continue (spec_automation.md §3.5).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct StopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "stop", abstract: "Stop the running entry.")

    @Option(help: ArgumentHelp("Stop time.", valueName: "time"))
    var at: String?

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let context = ToolContext(global)
        let service = try await context.service(writing: true)
        let at = try at.map { text throws(AutomationError) in try service.instant(text) }
        let stopped = try await service.stop(at: at)
        let end = stopped.entry.end ?? service.now
        let line = "Stopped \(ToolFormat.subject(stopped)) at \(ToolFormat.time(end, context.timeZone)) "
            + "after \(ToolFormat.duration(stopped.entry.seconds(at: end)))."
        try context.changed(line) {
            AutomationRecords.entry(stopped, now: service.now, timeZone: context.timeZone)
        }
    }
}
