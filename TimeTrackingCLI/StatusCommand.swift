// status, start, stop, continue (spec_automation.md §3.5).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the running entry, today's total, and the unsent change count."
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let (context, service) = try await ToolContext.open(global, writing: false)
        let status = try await service.status()
        let zone = context.timeZone
        try context.emit(json: { AutomationRecords.status(status, timeZone: zone) }, text: {
            var lines: [String] = []
            if let running = status.running {
                let entry = running.entry
                var line = "Running: \(ToolFormat.subject(running))"
                if let client = running.client?.name {
                    line += " (\(client))"
                }
                line += " since \(ToolFormat.time(entry.start, zone)), \(ToolFormat.duration(entry.seconds(at: status.asOf)))"
                lines.append(line)
            } else {
                lines.append("No entry running.")
            }
            lines.append("Today: \(ToolFormat.duration(status.todaySeconds))")
            lines.append("Unsent changes: \(status.pendingChanges)")
            return lines.joined(separator: "\n")
        })
    }
}
