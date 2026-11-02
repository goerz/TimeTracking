// ActivityLogs: where the agent writes the block log, the detail log, and
// current.json (spec_activity_tracking.md §4.1 to §4.4, §7.3).

import Foundation
import TimeTrackingCore

/// The agent's output files.
///
/// `blocks` is the shared folder's `blocks/` (iCloud Drive), or the local
/// folder's when the container cannot be written, with a file per month;
/// `detail/` (a file per day) and `current.json` are always local.
struct ActivityLogs {
    var blocksFolder: URL
    var detailFolder: URL
    var currentStateURL: URL
    let device: String
    private var blockWriter: BlockLogWriter

    init(blocksFolder: URL, folders: ActivityFolders, device: String) {
        self.blocksFolder = blocksFolder
        self.detailFolder = folders.detailFolder
        self.currentStateURL = folders.currentStateURL
        self.device = device
        self.blockWriter = BlockLogWriter(folder: blocksFolder, device: device)
    }

    /// A block line of a day as written, with its detail and header contexts.
    struct DayEntry {
        var block: ActivityBlock
        var detail: ActivityBlockDetail?
        var contexts: [String: String]
    }

    /// The blocks of `day` in the block log, in file order.
    func blocks(on day: String) -> [ActivityBlock] {
        let url = blocksFolder.appending(path: "\(day.prefix(7)).jsonl", directoryHint: .notDirectory)
        return ((try? BlockLogFile(contentsOf: url))?.blocks ?? []).filter { $0.localDay == day }
    }

    /// The lines of the detail file of `day`.
    func detailEntries(on day: String) -> [DayEntry] {
        let url = detailURL(day)
        return ((try? BlockLogFile(contentsOf: url))?.entries ?? []).map { entry in
            DayEntry(block: entry.block, detail: entry.detail, contexts: entry.contexts)
        }
    }

    func detailURL(_ day: String) -> URL {
        detailFolder.appending(path: "\(day).jsonl", directoryHint: .notDirectory)
    }

    /// Replaces the blocks of `day` in the block log by `closed`, in order,
    /// and the detail file of `day` by their details.
    mutating func replaceDay(_ day: String, with closed: [(block: ClosedBlock, detail: ActivityBlockDetail)]) throws {
        let month = blocksFolder.appending(path: "\(day.prefix(7)).jsonl", directoryHint: .notDirectory)
        try MonthFileRewriter.rewrite(month) { block, _, _ in block.localDay == day ? .drop : .keep }
        for entry in closed {
            try blockWriter.append(entry.block.block, contexts: entry.block.contexts)
        }
        let url = detailURL(day)
        guard !closed.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let staging = FileManager.default.temporaryDirectory.appending(path: "detail-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: staging) }
        var writer = BlockLogWriter(folder: staging, device: device, period: .day)
        for entry in closed {
            try writer.append(entry.block.block, contexts: entry.block.contexts, detail: entry.detail)
        }
        try AtomicFile.write(Data(contentsOf: writer.fileURL(for: day)), to: url)
    }

    /// Applies `decide` to every block line of the month files of the block
    /// log and the day files of the detail log within `[fromDay, toDay]`
    /// (days `YYYY-MM-DD`); returns the blocks dropped or replaced, block
    /// log first.
    @discardableResult
    func rewrite(
        fromDay: String,
        toDay: String,
        _ decide: (ActivityBlock, ActivityBlockDetail?, [String: String]) -> LineDecision
    ) throws -> [ActivityBlock] {
        var affected: [ActivityBlock] = []
        for url in MonthFileRewriter.monthFiles(in: blocksFolder, fromDay: fromDay, toDay: toDay) {
            affected += try MonthFileRewriter.rewrite(url, decide: decide)
        }
        for url in MonthFileRewriter.dayFiles(in: detailFolder, fromDay: fromDay, toDay: toDay) {
            affected += try MonthFileRewriter.rewrite(url, decide: decide)
        }
        return affected
    }

    /// Rewrites `current.json` atomically.
    func writeCurrentState(_ state: TrackerState, timeZone: TimeZone) throws {
        try AtomicFile.write(Data((state.jsonText(timeZone: timeZone) + "\n").utf8), to: currentStateURL)
    }
}
