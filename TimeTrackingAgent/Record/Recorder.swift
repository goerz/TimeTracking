// Recorder: `--record <folder>` writes adapter outputs and the run's samples
// as fixtures, anonymized (spec_activity_tracking.md §5,
// spec_architecture.md §3.4).

import Foundation
import TimeTrackingCore

/// Writes `<folder>/<adapter>/<NNN>-<name>.txt` for every adapter output and
/// `<folder>/samples/<day>.jsonl` for the samples, with home-directory
/// paths, host names, and URL paths replaced by placeholders.
@MainActor
final class Recorder {
    let folder: URL
    private var anonymizer: Anonymizer
    private var counters: [String: Int] = [:]
    private var sampleHeaders: [String: Int] = [:]
    private static let browserContexts = Set(BrowserApp.known.values.map(\.context))

    init(folder: URL, homeDirectory: String, userName: String, hostNames: [String]) {
        self.folder = folder
        self.anonymizer = Anonymizer(homeDirectory: homeDirectory, userName: userName, hostNames: hostNames)
    }

    /// Records one adapter output.
    func record(output: String, adapter: String, name: String) {
        let count = (counters[adapter] ?? 0) + 1
        counters[adapter] = count
        let safeName = name.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(40)
        let url = folder.appending(path: adapter, directoryHint: .isDirectory)
            .appending(path: String(format: "%03d-%@.txt", count, String(safeName)), directoryHint: .notDirectory)
        write(anonymizer.text(output), to: url, append: false)
    }

    /// Appends one sample to its day's file.
    func record(_ sample: Sample, utcOffset: Int, device _: String) {
        let day = ActivityTimestamp.day(sample.time, utcOffset: utcOffset)
        let url = folder.appending(path: "samples", directoryHint: .isDirectory).appending(path: "\(day).jsonl", directoryHint: .notDirectory)
        var text = ""
        if sampleHeaders[day] != utcOffset {
            sampleHeaders[day] = utcOffset
            text += SampleCodec.headerLine(utcOffset: utcOffset, device: "mac") + "\n"
        }
        text += SampleCodec.line(anonymized(sample), utcOffset: utcOffset) + "\n"
        write(text, to: url, append: true)
    }

    private func anonymized(_ sample: Sample) -> Sample {
        var result = sample
        result.primary = sample.primary.map(anonymized)
        result.secondaries = sample.secondaries.map(anonymized)
        result.title = anonymizer.text(sample.title)
        result.url = anonymizer.text(sample.url)
        result.tmuxTarget = anonymizer.text(sample.tmuxTarget)
        return result
    }

    private func anonymized(_ item: SampleItem) -> SampleItem {
        var result = item
        if Self.browserContexts.contains(item.context), item.subject != ExclusionRules.privateMarker {
            result.subject = anonymizer.urlPath(item.subject, keepFirst: true)
            result.detail = anonymizer.urlPath(item.detail, keepFirst: false)
            result.groupKey = anonymizer.urlPath(item.groupKey, keepFirst: true)
        } else {
            result.subject = anonymizer.text(item.subject)
            result.detail = anonymizer.text(item.detail)
            result.groupKey = anonymizer.text(item.groupKey)
        }
        return result
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
            let adapter = arguments.first.map { ($0 as NSString).lastPathComponent } ?? "command"
            let name = arguments.dropFirst().filter { !$0.hasPrefix("-") && !$0.contains("/") && !$0.contains("#") }.prefix(2).joined(separator: "-")
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
