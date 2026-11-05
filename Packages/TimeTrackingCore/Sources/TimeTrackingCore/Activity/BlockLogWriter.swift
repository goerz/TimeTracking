// BlockLogWriter: appending blocks to the month files of the block log or
// the day files of the detail log (activity_tracking.md §4.2, §4.3).

public import Foundation

/// Appends blocks and background stretches to `<folder>/YYYY-MM.jsonl` (the block log) or
/// `<folder>/YYYY-MM-DD.jsonl` (the detail log), writing a header where
/// the format requires one.
///
/// A header goes at the start of a file, after a time zone change, and
/// before the first block using a context the current header's `contexts`
/// lacks; the new header carries the earlier contexts plus the new ones.
/// The header at the start of a file also carries the legend `keys`.
/// The writer keeps no global state: it caches each file's last header
/// with the file size it saw and rescans the file when the size differs.
public struct BlockLogWriter: Sendable {
    /// The folder of the month files, e.g. `Activity/blocks/`.
    public let folder: URL
    /// The recording Mac's name for headers.
    public let device: String
    /// Whether a file holds a month or a day.
    public let period: Period
    private var known: [String: KnownFile] = [:]

    /// The span of one file.
    public enum Period: Sendable {
        case month
        case day

        /// The file name of `block`'s file without the extension.
        func key(of block: ActivityBlock) -> String {
            self == .month ? block.month : block.localDay
        }
    }

    public init(folder: URL, device: String, period: Period = .month) {
        self.folder = folder
        self.device = device
        self.period = period
    }

    /// The file `<key>.jsonl`, e.g. `2026-10.jsonl` or `2026-10-28.jsonl`.
    public func fileURL(for key: String) -> URL {
        folder.appending(path: "\(key).jsonl", directoryHint: .notDirectory)
    }

    /// Appends `block` to the file of its local month or day. `contexts` maps the
    /// block's contexts to bundle identifiers or process names (a context
    /// missing from it is recorded with `""`). With `detail`, the line is a
    /// detail-log line: the uncut items plus URLs, files, and presence.
    public mutating func append(
        _ block: ActivityBlock,
        contexts: [String: String],
        detail: ActivityBlockDetail? = nil
    ) throws(ActivityError) {
        try appendLine(
            .block(block, detail: detail),
            key: period.key(of: block),
            utcOffset: block.utcOffset,
            lineContexts: block.contexts + (detail?.items.map(\.context) ?? []),
            contexts: contexts
        )
    }

    /// Appends a background stretch to the block log's file of its local month.
    public mutating func append(_ stretch: ActivityBackgroundStretch, contexts: [String: String]) throws(ActivityError) {
        try appendLine(
            .background(stretch),
            key: period == .month ? stretch.month : stretch.localDay,
            utcOffset: stretch.utcOffset,
            lineContexts: stretch.contexts,
            contexts: contexts
        )
    }

    /// Appends `line`, preceded by a header when the file has none yet, the
    /// time zone changed, or the header lacks one of `lineContexts`; a
    /// file's first header carries the legend of its log.
    private mutating func appendLine(
        _ line: BlockLogLine,
        key: String,
        utcOffset: Int,
        lineContexts: [String],
        contexts: [String: String]
    ) throws(ActivityError) {
        let url = fileURL(for: key)
        var state = try knownFile(key: key, url: url)
        var text = ""
        let missing = lineContexts.filter { state.header?.contexts[$0] == nil }
        if state.header?.utcOffset != utcOffset || !missing.isEmpty {
            var merged = state.header?.contexts ?? [:]
            for context in missing {
                merged[context] = contexts[context] ?? ""
            }
            var header = BlockLogHeader(utcOffset: utcOffset, device: device, contexts: merged)
            if state.header == nil {
                header.keys = if case .block(_, detail: .some) = line {
                    BlockLogHeader.detailLogKeys
                } else {
                    BlockLogHeader.blockLogKeys
                }
            }
            text += BlockLogLine.header(header).jsonText + "\n"
            state.header = header
        }
        text += line.jsonText + "\n"
        state.size = try Self.append(Data(text.utf8), to: url)
        known[key] = state
    }

    private func knownFile(key: String, url: URL) throws(ActivityError) -> KnownFile {
        let size = Self.size(of: url)
        if let state = known[key], state.size == size {
            return state
        }
        guard let size, size > 0 else {
            return KnownFile(size: size, header: nil)
        }
        return try KnownFile(size: size, header: BlockLogFile(contentsOf: url).lastHeader)
    }

    private static func size(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }

    /// Appends `data` and returns the new file size.
    private static func append(_ data: Data, to url: URL) throws(ActivityError) -> Int {
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !manager.fileExists(atPath: url.path) {
                manager.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            let end = try handle.seekToEnd()
            try handle.write(contentsOf: data)
            return Int(end) + data.count
        } catch {
            throw .fileSystem("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

/// What the writer knows about a file.
private struct KnownFile {
    var size: Int?
    var header: BlockLogHeader?
}
