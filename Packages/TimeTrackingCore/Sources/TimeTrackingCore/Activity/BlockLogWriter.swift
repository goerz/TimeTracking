// BlockLogWriter: appending blocks to the month files of the block log or
// the detail log (spec_activity_tracking.md §4.2, §4.3).

public import Foundation

/// Appends blocks to `<folder>/YYYY-MM.jsonl`, writing a header where the
/// format requires one.
///
/// A header goes at the start of a file, after a time zone change, and
/// before the first block using a context the current header's `contexts`
/// lacks; the new header carries the earlier contexts plus the new ones.
/// The writer keeps no global state: it caches each file's last header
/// with the file size it saw and rescans the file when the size differs.
public struct BlockLogWriter: Sendable {
    /// The folder of the month files, e.g. `Activity/blocks/`.
    public let folder: URL
    /// The device name for headers.
    public let device: String
    private var known: [String: KnownFile] = [:]

    public init(folder: URL, device: String) {
        self.folder = folder
        self.device = device
    }

    /// The month file `YYYY-MM.jsonl`.
    public func fileURL(forMonth month: String) -> URL {
        folder.appending(path: "\(month).jsonl", directoryHint: .notDirectory)
    }

    /// Appends `block` to the file of its local month. `contexts` maps the
    /// block's contexts to bundle identifiers or process names (a context
    /// missing from it is recorded with `""`). With `detail`, the line is a
    /// detail-log line: the uncut items plus URLs, files, and presence.
    public mutating func append(
        _ block: ActivityBlock,
        contexts: [String: String],
        detail: ActivityBlockDetail? = nil
    ) throws(ActivityError) {
        let month = block.month
        let url = fileURL(forMonth: month)
        var state = try knownFile(month: month, url: url)
        var text = ""
        let blockContexts = block.contexts + (detail?.items.map(\.context) ?? [])
        let missing = blockContexts.filter { state.header?.contexts[$0] == nil }
        if state.header?.utcOffset != block.utcOffset || !missing.isEmpty {
            var merged = state.header?.contexts ?? [:]
            for context in missing {
                merged[context] = contexts[context] ?? ""
            }
            let header = BlockLogHeader(utcOffset: block.utcOffset, device: device, contexts: merged)
            text += BlockLogLine.header(header).jsonText + "\n"
            state.header = header
        }
        text += BlockLogLine.block(block, detail: detail).jsonText + "\n"
        state.size = try Self.append(Data(text.utf8), to: url)
        known[month] = state
    }

    private func knownFile(month: String, url: URL) throws(ActivityError) -> KnownFile {
        let size = Self.size(of: url)
        if let state = known[month], state.size == size {
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

/// What the writer knows about a month file.
private struct KnownFile {
    var size: Int?
    var header: BlockLogHeader?
}
