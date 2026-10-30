// ActivityLogs: where the agent writes the block log, the detail log, and
// current.json (spec_activity_tracking.md §4.1 to §4.4).

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

    init(blocksFolder: URL, localFolder: URL, device: String) {
        self.blocksFolder = blocksFolder
        self.detailFolder = localFolder.appending(path: "detail", directoryHint: .isDirectory)
        self.currentStateURL = localFolder.appending(path: "current.json", directoryHint: .notDirectory)
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

    /// Rewrites `current.json` atomically.
    func writeCurrentState(_ state: TrackerState, timeZone: TimeZone) throws {
        try AtomicFile.write(Data((state.jsonText(timeZone: timeZone) + "\n").utf8), to: currentStateURL)
    }
}
