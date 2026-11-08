// tracker: the tracker's liveness, presence, sources, and recording state
// (automation.md §3.13).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct TrackerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tracker",
        abstract: "Show whether the tracker runs, its sources' status, and whether this Mac records."
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let (context, service) = try await ToolContext.open(global, writing: false)
        let reader = try context.activityReader()
        var owner: String?
        var ownerReadable = true
        if let log = context.activityFolders?.blockFolders.first {
            do {
                owner = try BlockLogOwner.owner(of: log)
            } catch {
                ownerReadable = false
            }
        }
        let report = await TrackerReport(
            state: reader.currentState(),
            thisMac: HardwareUUID.current,
            owner: owner,
            ownerReadable: ownerReadable,
            newestDateFile: reader.newestDateFile(),
            now: service.now,
            timeZone: context.timeZone
        )
        try context.emit(json: { report.json }, text: { Self.text(report) })
    }

    /// "  Terminal tab: Limited: <reason>", with the Tracker pane's words.
    private static func sourceLine(_ source: TrackerSourceHealth) -> String {
        let word = switch source.status {
        case .active: "On"
        case .fallback: "Limited"
        case .off: "Off"
        }
        return "  \(source.name): \(word)" + (source.reason.isEmpty ? "" : ": \(source.reason)")
    }

    private static func text(_ report: TrackerReport) -> String {
        let zone = report.timeZone
        func time(_ date: Date) -> String {
            "\(ToolFormat.date(date, zone)) \(ToolFormat.time(date, zone))"
        }
        guard let state = report.state else {
            return "Tracker not running: no current.json."
        }
        let status = switch report.liveness {
        case .running: "running"
        case .delayed: "delayed"
        case .notRunning: "not running"
        }
        var lines = [
            "Tracker \(status), last tick \(time(state.health.lastTick)), version \(state.health.version)",
            "Presence: \(state.presence.state.rawValue) since \(time(state.presence.since))",
        ]
        if let item = state.foreground {
            lines.append("Foreground: \(item.label) · \(item.workspaceName)")
        }
        lines += state.health.sources.map(sourceLine)
        switch report.recorder {
        case .thisMac: lines.append("This Mac records the block log.")
        case .otherMac: lines.append("Another Mac records the block log.")
        case .unclaimed: lines.append("No Mac has claimed the block log yet.")
        }
        if let newest = report.newestDateFile {
            lines.append("Newest date file: \(newest.day)" + (newest.modified.map { ", changed \(time($0))" } ?? ""))
        }
        return lines.joined(separator: "\n")
    }
}
