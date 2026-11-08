// Recorder: `--record <folder>` writes adapter outputs and the run's Samples
// as fixtures, anonymized (activity_tracking.md §5, architecture.md §3.4).

import Foundation
import TimeTrackingCore

/// Writes `<folder>/<adapter>/<NNN>-<name>.txt` for every adapter output, and
/// `<folder>/samples.jsonl` and `fixture.json` as a replay fixture
/// (`SampleFixture`), with home-directory paths, host names, and URL paths
/// replaced by placeholders.
@MainActor
final class Recorder {
    let folder: URL
    private var anonymizer: Anonymizer
    private var counters: [String: Int] = [:]
    private let zone: TimeZone

    init(folder: URL, homeDirectory: String, userName: String, hostNames: [String], zone: TimeZone, macName: String) {
        self.folder = folder
        // The Mac's computer name is one of its host names.
        self.anonymizer = Anonymizer(homeDirectory: homeDirectory, userName: userName, hostNames: hostNames + [macName])
        self.zone = zone
        let description = SampleFixture.Description(zone: zone.identifier, mac: Self.macID, names: [Self.macID: anonymizer.text(macName)])
        if let data = try? JSONEncoder().encode(description) {
            write(String(decoding: data, as: UTF8.self), to: folder.appending(path: "fixture.json"), append: false)
        }
    }

    /// The Mac's device id in recorded Samples.
    static let macID = "mac"

    /// Records one adapter output.
    func record(output: String, adapter: String, name: String) {
        let count = (counters[adapter] ?? 0) + 1
        counters[adapter] = count
        let safeName = name.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(40)
        let url = folder.appending(path: adapter, directoryHint: .isDirectory)
            .appending(path: String(format: "%03d-%@.txt", count, String(safeName)), directoryHint: .notDirectory)
        write(anonymizer.text(output), to: url, append: false)
    }

    /// Appends one Sample to `samples.jsonl`, the Mac's id replaced.
    func record(_ sample: Sample) {
        var anonymous = sample.mapItems { anonymized($0) }
        anonymous.deviceID = Self.macID
        let line = SampleFixture.line(anonymous, utcOffset: zone.secondsFromGMT(for: sample.time))
        write(line + "\n", to: folder.appending(path: "samples.jsonl"), append: true)
    }

    private func anonymized(_ item: ActivityItem) -> ActivityItem {
        var result = item
        result.window = anonymizer.text(item.window)
        result.host = anonymizer.text(item.host)
        result.session = anonymizer.text(item.session)
        result.location = anonymizer.text(item.location)
        result.documents = item.documents.map { anonymizer.text($0) }
        result.command = anonymizer.text(item.command)
        result.workspace = anonymizedWorkspace(item)
        return result
    }

    /// A workspace a URL pattern named (`owner/MyApp` of a GitHub page) is
    /// URL path, anonymized like the location's path; a path, a domain, or
    /// an app name is anonymized as text.
    private func anonymizedWorkspace(_ item: ActivityItem) -> String {
        let workspace = item.workspace
        let isPath = workspace.hasPrefix("/") || workspace.hasPrefix("~")
        guard !isPath, workspace.contains("/"), item.location.contains("://") else {
            return anonymizer.text(workspace)
        }
        return anonymizer.urlPath(workspace, keepFirst: false)
    }

    private func write(_ text: String, to url: URL, append: Bool) {
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard append, manager.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) else {
            try? Data(text.utf8).write(to: url)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }
}

/// A command runner that records each output for its adapter (the
/// executable's name).
struct RecordingCommandRunner: CommandRunning {
    let base: any CommandRunning
    let recorder: Recorder

    func run(_ arguments: [String]) async -> String? {
        let output = await base.run(arguments)
        if let output {
            let adapter = arguments.first.map(PathText.lastComponent) ?? "command"
            let name = arguments.dropFirst().filter { !$0.hasPrefix("-") && !$0.contains("/") && !$0.contains("#") }.prefix(2)
                .joined(separator: "-")
            recorder.record(output: output, adapter: adapter, name: name.isEmpty ? "output" : name)
        }
        return output
    }
}

/// An AppleScript runner that records each answer under `applescript`.
struct RecordingScripts: AppleScripting {
    let base: any AppleScripting
    let recorder: Recorder

    func run(_ source: String) -> ScriptResult {
        let result = base.run(source)
        if case let .value(text) = result {
            let target = source.firstMatch(of: /application id "([^"]+)"/).map { String($0.1) } ?? "script"
            recorder.record(output: text, adapter: "applescript", name: target.replacing(".", with: "-"))
        }
        return result
    }
}
