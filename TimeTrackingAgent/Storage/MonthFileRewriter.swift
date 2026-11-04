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

/// What to do with one background stretch line.
nonisolated enum StretchDecision {
    case keep
    case drop
    case replace(ActivityBackgroundStretch)
}

/// Rewrites month files: unaffected lines (headers included) stay byte
/// identical, and each changed file is replaced atomically.
nonisolated enum MonthFileRewriter {
    /// Applies `decide` to every block line of `url` and `decideStretch` to
    /// every background stretch line; returns the blocks dropped or replaced
    /// (their original form). A file without changes is not touched.
    @discardableResult
    static func rewrite(
        _ url: URL,
        decideStretch: (ActivityBackgroundStretch, [String: String]) -> StretchDecision = { _, _ in .keep },
        decide: (ActivityBlock, ActivityBlockDetail?, [String: String]) -> LineDecision
    ) throws -> [ActivityBlock] {
        if ICloudFile.isPending(url) {
            throw ICloudFile.pendingError(url)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let result = try rewritten(Data(contentsOf: url), decideStretch: decideStretch, decide: decide)
        if result.changed {
            try AtomicFile.write(result.data, to: url)
        }
        return result.affected
    }

    /// A rewritten file: its content, the blocks dropped or replaced (in
    /// their original form), and whether anything changed.
    struct Rewritten {
        var data: Data
        var affected: [ActivityBlock]
        var changed: Bool
    }

    // One switch over the line kinds and decisions.
    // swiftlint:disable cyclomatic_complexity

    /// The content of a month or day file after applying `decide` and
    /// `decideStretch` to `data`. Unaffected lines stay byte identical.
    static func rewritten(
        _ data: Data,
        decideStretch: (ActivityBackgroundStretch, [String: String]) -> StretchDecision = { _, _ in .keep },
        decide: (ActivityBlock, ActivityBlockDetail?, [String: String]) -> LineDecision
    ) -> Rewritten {
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
            case let .background(stretch):
                switch decideStretch(stretch, header?.contexts ?? [:]) {
                case .keep:
                    output.append(text)
                case .drop:
                    changed = true
                    continue
                case let .replace(newStretch):
                    let encoded = Data(BlockLogLine.background(newStretch).jsonText.utf8)
                    changed = changed || encoded != text
                    output.append(encoded)
                }
            case .other, nil:
                output.append(text)
            }
            output.append(UInt8(ascii: "\n"))
        }
        return Rewritten(data: output, affected: affected, changed: changed)
    }

    // swiftlint:enable cyclomatic_complexity

    /// The day files `YYYY-MM-DD.jsonl` of `folder` from `fromDay` to `toDay`.
    static func dayFiles(in folder: URL, fromDay: String, toDay: String) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let days = names.filter { $0.hasSuffix(".jsonl") }.map { String($0.dropLast(6)) }
            .filter { $0.count == 10 && $0 >= fromDay && $0 <= toDay }
        return days.sorted().map { day in folder.appending(path: "\(day).jsonl", directoryHint: .notDirectory) }
    }

    /// The `YYYY-MM.jsonl` files of `folder` whose month overlaps `[from, to]` (days `YYYY-MM-DD`).
    static func monthFiles(in folder: URL, fromDay: String, toDay: String) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let first = String(fromDay.prefix(7))
        let last = String(toDay.prefix(7))
        let months = names.filter { $0.hasSuffix(".jsonl") }.map { String($0.dropLast(6)) }
            .filter { $0.count == 7 && $0 >= first && $0 <= last }
        return months.sorted().map { month in folder.appending(path: "\(month).jsonl", directoryHint: .notDirectory) }
    }
}
