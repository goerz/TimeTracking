// MonthFileRewriter: rewriting block-log and detail-log month files line by
// line (spec_activity_tracking.md §7.3).

import Foundation
import TimeTrackingCore

/// What to do with one block line.
nonisolated enum LineDecision {
    case keep
    case drop
    case replace(ActivityBlock, ActivityBlockDetail?)
}

/// Rewrites month files: unaffected lines (headers included) stay byte
/// identical, and each changed file is replaced atomically.
nonisolated enum MonthFileRewriter {
    /// Applies `decide` to every block line of `url`; returns the blocks
    /// dropped or replaced (their original form). A file without changes is
    /// not touched.
    @discardableResult
    static func rewrite(
        _ url: URL,
        decide: (ActivityBlock, ActivityBlockDetail?, [String: String]) -> LineDecision
    ) throws -> [ActivityBlock] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        var output = Data()
        var header: BlockLogHeader?
        var affected: [ActivityBlock] = []
        var changed = false
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        for line in lines {
            let text = Data(line)
            switch try? BlockLogLine.parse(text, header: header) {
            case let .header(value):
                header = value
                output.append(text)
            case let .block(block, detail):
                switch decide(block, detail, header?.contexts ?? [:]) {
                case .keep:
                    output.append(text)
                case .drop:
                    affected.append(block)
                    changed = true
                    continue
                case let .replace(newBlock, newDetail):
                    let encoded = Data(BlockLogLine.block(newBlock, detail: newDetail).jsonText.utf8)
                    if encoded != text {
                        affected.append(block)
                        changed = true
                    }
                    output.append(encoded)
                }
            case .other, nil:
                output.append(text)
            }
            output.append(UInt8(ascii: "\n"))
        }
        if changed {
            try AtomicFile.write(output, to: url)
        }
        return affected
    }

    /// The `YYYY-MM.jsonl` files of `folder` whose month overlaps `[from, to]` (days `YYYY-MM-DD`).
    static func monthFiles(in folder: URL, fromDay: String, toDay: String) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let first = String(fromDay.prefix(7))
        let last = String(toDay.prefix(7))
        return names.filter { $0.hasSuffix(".jsonl") }.map { String($0.dropLast(6)) }.filter { $0 >= first && $0 <= last }.sorted().map {
            folder.appending(path: "\($0).jsonl", directoryHint: .notDirectory)
        }
    }
}
