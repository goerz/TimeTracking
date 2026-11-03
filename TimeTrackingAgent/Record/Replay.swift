// Replay: `--replay <fixture>` runs the Blocker over a recorded sample stream
// and compares the blocks with `<fixture>.expected.jsonl`
// (spec_activity_tracking.md §5, spec_architecture.md ARCH-16, TRK-29).

import Foundation
import TimeTrackingCore

/// Replays `<day>.jsonl` with the settings of `<day>.settings.toml` or
/// `settings.toml` beside it (the defaults without either), writes the
/// block log the Blocker produces, and compares it byte for byte with
/// `<day>.expected.jsonl` after normalizing the headers' `dev`.
nonisolated enum Replay {
    struct Outcome {
        var produced: String
        var expected: String?
        /// The first differing line, 1-based, or `nil` when equal.
        var firstDifference: Int?

        var matches: Bool {
            expected != nil && firstDifference == nil
        }
    }

    /// The expected file of `fixture`: `<day>.expected.jsonl`.
    static func expectedURL(for fixture: URL) -> URL {
        let name = fixture.deletingPathExtension().lastPathComponent
        return fixture.deletingLastPathComponent().appending(path: "\(name).expected.jsonl", directoryHint: .notDirectory)
    }

    /// The settings for `fixture`.
    static func settings(for fixture: URL) throws -> TrackerSettings {
        let folder = fixture.deletingLastPathComponent()
        let name = fixture.deletingPathExtension().lastPathComponent
        for candidate in ["\(name).settings.toml", "settings.toml"] {
            let url = folder.appending(path: candidate, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: url.path) {
                return try TrackerSettings(contentsOf: url)
            }
        }
        return TrackerSettings.defaults
    }

    /// The block log lines the Blocker produces for `text` (a sample file).
    static func blockLog(samplesText text: String, settings: TrackerSettings) throws -> String {
        let parsed = SampleCodec.samples(inFile: text)
        let offset = text.split(separator: "\n").lazy.compactMap { SampleCodec.header($0)?.utcOffset }.first ?? 0
        let timeZone = TimeZone(secondsFromGMT: offset) ?? .gmt
        let device = parsed.device.isEmpty ? "mac" : parsed.device
        let (result, _) = Timeline.run(
            TimelineInputs(mac: parsed.samples),
            settings: settings.blocks,
            timeZone: timeZone,
            mac: device,
            flush: true
        )
        let folder = FileManager.default.temporaryDirectory.appending(path: "replay-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        var writer = BlockLogWriter(folder: folder, device: device)
        var stretches = result.stretches.sorted { $0.stretch.start < $1.stretch.start }[...]
        for block in result.closed {
            while let stretch = stretches.first, stretch.stretch.start < block.block.start {
                try writer.append(stretch.stretch, contexts: stretch.contexts)
                stretches.removeFirst()
            }
            try writer.append(block.block, contexts: block.contexts)
        }
        for stretch in stretches {
            try writer.append(stretch.stretch, contexts: stretch.contexts)
        }
        return try monthFilesText(in: folder)
    }

    /// The `.jsonl` month files of a log folder, concatenated oldest first.
    static func monthFilesText(in folder: URL) throws -> String {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { $0.hasSuffix(".jsonl") }.sorted() ?? []
        var output = ""
        for name in names {
            output += try String(contentsOf: folder.appending(path: name, directoryHint: .notDirectory), encoding: .utf8)
        }
        return output
    }

    /// Replays `fixture` and compares.
    static func run(fixture: URL) throws -> Outcome {
        let text = try String(contentsOf: fixture, encoding: .utf8)
        let produced = try blockLog(samplesText: text, settings: settings(for: fixture))
        let expectedURL = expectedURL(for: fixture)
        guard let expected = try? String(contentsOf: expectedURL, encoding: .utf8) else {
            return Outcome(produced: produced, expected: nil, firstDifference: 1)
        }
        let left = normalized(produced)
        let right = normalized(expected)
        var difference: Int?
        for index in 0 ..< max(left.count, right.count) where index >= left.count || index >= right.count || left[index] != right[index] {
            difference = index + 1
            break
        }
        return Outcome(produced: produced, expected: expected, firstDifference: difference)
    }

    /// Lines with each header's `dev` emptied.
    static func normalized(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            guard line.hasPrefix("{\"type\":\"header\"") else {
                return String(line)
            }
            return String(line).replacing(/"dev":"(?:[^"\\]|\\.)*"/, with: "\"dev\":\"\"")
        }
    }

    /// The `--replay` flag: prints the produced log to standard output and
    /// the first difference to standard error; 0 when equal.
    static func main(fixture: URL) -> Int32 {
        do {
            let outcome = try run(fixture: fixture)
            FileHandle.standardOutput.write(Data(outcome.produced.utf8))
            if outcome.expected == nil {
                FileHandle.standardError.write(Data("replay: no \(expectedURL(for: fixture).lastPathComponent)\n".utf8))
                return 1
            }
            if let line = outcome.firstDifference {
                FileHandle.standardError
                    .write(Data("replay: line \(line) differs from \(expectedURL(for: fixture).lastPathComponent)\n".utf8))
                return 1
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("replay: \(error.localizedDescription)\n".utf8))
            return 2
        }
    }
}
