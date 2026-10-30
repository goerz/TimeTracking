// TimeTrackingCommand: the `timetracking` tool's root command (spec_automation.md §1).

import ArgumentParser
import Foundation
import TimeTrackingCore

@main
nonisolated struct TimeTrackingCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "timetracking",
        abstract: "Read and change tracked time.",
        version: versionString
    )

    /// The tool's version, which equals the app's (the tool ships inside it).
    static var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
