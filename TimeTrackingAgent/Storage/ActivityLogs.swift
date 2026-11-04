// ActivityLogs: where the agent writes the block log, the detail log, and
// current.json (spec_activity_tracking.md §4.1 to §4.4, §7.3).

import Foundation
import TimeTrackingCore

/// The agent's output files.
///
/// `blocks/` is the shared folder's (iCloud Drive), or the local folder's
/// when the container cannot be written. The agent writes only its own
/// subfolder `blocks/<mac>/`, a file per month, so two Macs never rewrite
/// the same file; `detail/` (a file per day) and `current.json` are
/// always local. Every file is replaced as a whole (a temporary file, then
/// a rename), so a reader sees a day either before or after a rewrite.
struct ActivityLogs {
    /// `blocks/`, holding one subfolder per Mac.
    var blocksRoot: URL
    /// This Mac's subfolder `blocks/<mac>/`.
    var blocksFolder: URL
    var detailFolder: URL
    var currentStateURL: URL
    let device: String

    init(blocksRoot: URL, macFolder: String, folders: ActivityFolders, device: String) {
        self.blocksRoot = blocksRoot
        self.blocksFolder = blocksRoot.appending(path: macFolder, directoryHint: .isDirectory)
        self.detailFolder = folders.detailFolder
        self.currentStateURL = folders.currentStateURL
        self.device = device
    }

    /// A block line of a day as written, with its detail and header contexts.
    struct DayEntry {
        var block: ActivityBlock
        var detail: ActivityBlockDetail?
        var contexts: [String: String]
    }

    /// This Mac's month file of `day`.
    func monthURL(_ day: String) -> URL {
        blocksFolder.appending(path: "\(day.prefix(7)).jsonl", directoryHint: .notDirectory)
    }

    /// The blocks of `day` in the block log, in file order.
    func blocks(on day: String) -> [ActivityBlock] {
        ((try? BlockLogFile(contentsOf: monthURL(day)))?.blocks ?? []).filter { $0.localDay == day }
    }

    /// The background stretches of `day` in the block log, in file order.
    func stretches(on day: String) -> [ActivityBackgroundStretch] {
        ((try? BlockLogFile(contentsOf: monthURL(day)))?.backgrounds ?? []).map(\.stretch).filter { $0.localDay == day }
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

    /// Replaces the blocks and background stretches of `day` in the block
    /// log by `closed` and `stretches`, in time order, and the detail file of
    /// `day` by the blocks' details. Each file is built in a staging folder
    /// and replaces the old one in a single rename; the detail file goes
    /// first, so an interruption between the two leaves the block log
    /// unchanged and the next rebuild writes both again.
    func replaceDay(
        _ day: String,
        with closed: [(block: ClosedBlock, detail: ActivityBlockDetail)],
        stretches: [BackgroundWork.Stretch] = []
    ) throws {
        let manager = FileManager.default
        let staging = manager.temporaryDirectory.appending(path: "day-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: staging) }

        let detail = detailURL(day)
        if closed.isEmpty {
            try? manager.removeItem(at: detail)
        } else {
            var writer = BlockLogWriter(
                folder: staging.appending(path: "detail", directoryHint: .isDirectory),
                device: device,
                period: .day
            )
            for entry in closed {
                try writer.append(entry.block.block, contexts: entry.block.contexts, detail: entry.detail)
            }
            try AtomicFile.write(Data(contentsOf: writer.fileURL(for: day)), to: detail)
        }

        let month = monthURL(day)
        let stagedFolder = staging.appending(path: "blocks", directoryHint: .isDirectory)
        var writer = BlockLogWriter(folder: stagedFolder, device: device)
        let staged = writer.fileURL(for: String(day.prefix(7)))
        if manager.fileExists(atPath: month.path) {
            let kept = try MonthFileRewriter.rewritten(
                Data(contentsOf: month),
                decideStretch: { stretch, _ in stretch.localDay == day ? .drop : .keep },
                decide: { block, _, _ in block.localDay == day ? .drop : .keep }
            )
            try manager.createDirectory(at: stagedFolder, withIntermediateDirectories: true)
            try kept.data.write(to: staged)
        }
        var blocks = closed.map(\.block)[...]
        var others = stretches.sorted { $0.stretch.start < $1.stretch.start }[...]
        while !blocks.isEmpty || !others.isEmpty {
            if let block = blocks.first, others.first.map({ block.block.start <= $0.stretch.start }) ?? true {
                try writer.append(block.block, contexts: block.contexts)
                blocks.removeFirst()
            } else if let stretch = others.popFirst() {
                try writer.append(stretch.stretch, contexts: stretch.contexts)
            }
        }
        if manager.fileExists(atPath: staged.path) {
            try AtomicFile.write(Data(contentsOf: staged), to: month)
        }
    }

    /// Moves this Mac's lines out of the month files directly in `blocks/`,
    /// written before each Mac had its own subfolder, into its subfolder:
    /// the blocks and stretches that follow a header whose `dev` is this
    /// Mac's name. Another Mac's lines stay for its own agent; a file left
    /// without blocks or stretches is removed. Returns the months moved.
    @discardableResult
    func moveOwnLinesFromSharedMonthFiles() throws -> [String] {
        var moved: [String] = []
        for shared in BlockLogFolder.monthFiles(directlyIn: blocksRoot) {
            let split = try Self.split(Data(contentsOf: shared), device: device)
            guard split.ownLines > 0 else {
                continue
            }
            let own = blocksFolder.appending(path: shared.lastPathComponent, directoryHint: .notDirectory)
            var content = (try? Data(contentsOf: own)) ?? Data()
            if let last = content.last, last != UInt8(ascii: "\n") {
                content.append(UInt8(ascii: "\n"))
            }
            try AtomicFile.write(content + split.own, to: own)
            if split.otherLines > 0 {
                try AtomicFile.write(split.others, to: shared)
            } else {
                try FileManager.default.removeItem(at: shared)
            }
            moved.append(BlockLogFolder.month(of: shared))
        }
        return moved
    }

    /// The lines of a shared month file split by writer: every header goes
    /// to both sides, so each line keeps the header it was read with.
    private static func split(_ data: Data, device: String) -> SplitMonth {
        var result = SplitMonth()
        var header: BlockLogHeader?
        for line in data.split(separator: UInt8(ascii: "\n")) {
            let text = Data(line) + Data("\n".utf8)
            switch try? BlockLogLine.parse(line, header: header) {
            case let .header(value):
                header = value
                result.own += text
                result.others += text
            case .block, .background:
                if header?.device == device {
                    result.own += text
                    result.ownLines += 1
                } else {
                    result.others += text
                    result.otherLines += 1
                }
            case .other, nil:
                result.others += text
                result.otherLines += 1
            }
        }
        return result
    }

    /// A shared month file split into this Mac's lines and the rest.
    private struct SplitMonth {
        var own = Data()
        var ownLines = 0
        var others = Data()
        var otherLines = 0
    }

    /// Applies `decide` to every block line of the month files of the block
    /// log and the day files of the detail log within `[fromDay, toDay]`
    /// (days `YYYY-MM-DD`), and `decideStretch` to the block log's
    /// background stretches; returns the blocks dropped or replaced, block
    /// log first.
    @discardableResult
    func rewrite(
        fromDay: String,
        toDay: String,
        decideStretch: (ActivityBackgroundStretch, [String: String]) -> StretchDecision = { _, _ in .keep },
        _ decide: (ActivityBlock, ActivityBlockDetail?, [String: String]) -> LineDecision
    ) throws -> [ActivityBlock] {
        var affected: [ActivityBlock] = []
        for url in MonthFileRewriter.monthFiles(in: blocksFolder, fromDay: fromDay, toDay: toDay) {
            affected += try MonthFileRewriter.rewrite(url, decideStretch: decideStretch, decide: decide)
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
