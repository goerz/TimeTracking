// status, start, stop, continue (automation.md §3.5).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct StopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "stop", abstract: "Stop the running entry.")

    @Option(parsing: .unconditional, help: ArgumentHelp("Stop time.", valueName: "time"))
    var at: String?

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let (context, service) = try await ToolContext.open(global, writing: true)
        let at = try service.instant(ifGiven: at)
        let stopped = try await service.stop(at: at)
        let end = stopped.entry.end ?? service.now
        let line = "Stopped \(ToolFormat.subject(stopped)) at \(ToolFormat.time(end, context.timeZone)) "
            + "after \(ToolFormat.duration(stopped.entry.seconds(at: end)))."
        context.changed(line) {
            AutomationRecords.entry(stopped, now: service.now, timeZone: context.timeZone)
        }
    }
}
