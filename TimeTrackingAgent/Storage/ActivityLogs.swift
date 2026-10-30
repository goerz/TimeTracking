// ActivityLogs: where the agent writes the block log, the detail log, and
// current.json (spec_activity_tracking.md §4.1 to §4.4, §7.3).

import Foundation
import TimeTrackingCore

/// The agent's output files.
///
/// `blocks` is the shared folder's `blocks/` (iCloud Drive), or the local
/// folder's when the container cannot be written; `detail/` and
/// `current.json` are always local.
struct ActivityLogs {
    var blocksFolder: URL
    var detailFolder: URL
    var currentStateURL: URL
    private var blockWriter: BlockLogWriter
    private var detailWriter: BlockLogWriter

    init(blocksFolder: URL, folders: ActivityFolders, device: String) {
        self.blocksFolder = blocksFolder
        self.detailFolder = folders.detailFolder
        self.currentStateURL = folders.currentStateURL
        self.blockWriter = BlockLogWriter(folder: blocksFolder, device: device)
        self.detailWriter = BlockLogWriter(folder: detailFolder, device: device)
    }

    /// Appends a closed block to the block log and its detail to the detail log.
    mutating func append(_ closed: ClosedBlock, detail: ActivityBlockDetail) throws {
        try blockWriter.append(closed.block, contexts: closed.contexts)
        var full = detail
        full.items = closed.detailItems
        try detailWriter.append(closed.block, contexts: closed.contexts, detail: full)
    }

    /// Appends a closed block whose detail holds only its items (blocks
    /// formed from the Knowledge store, synced history, or device events).
    mutating func appendSummary(_ closed: ClosedBlock) throws {
        try append(closed, detail: ActivityBlockDetail(blockID: closed.block.id, items: closed.detailItems))
    }

    /// Applies `decide` to every block line of the month files of both
    /// logs that overlap `[fromDay, toDay]` (days `YYYY-MM-DD`); returns the
    /// blocks dropped or replaced, block log first.
    @discardableResult
    func rewrite(
        fromDay: String,
        toDay: String,
        _ decide: (ActivityBlock, ActivityBlockDetail?, [String: String]) -> LineDecision
    ) throws -> [ActivityBlock] {
        var affected: [ActivityBlock] = []
        for folder in [blocksFolder, detailFolder] {
            for url in MonthFileRewriter.monthFiles(in: folder, fromDay: fromDay, toDay: toDay) {
                affected += try MonthFileRewriter.rewrite(url, decide: decide)
            }
        }
        return affected
    }

    /// Rewrites `current.json` atomically.
    func writeCurrentState(_ state: TrackerState, timeZone: TimeZone) throws {
        try AtomicFile.write(Data((state.jsonText(timeZone: timeZone) + "\n").utf8), to: currentStateURL)
    }
}
