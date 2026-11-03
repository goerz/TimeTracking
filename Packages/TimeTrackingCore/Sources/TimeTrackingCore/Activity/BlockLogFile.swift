// BlockLogFile: a parsed month file of the block log or the detail log
// (spec_activity_tracking.md §4.2, §4.3, spec_data_and_sync.md §6).

public import Foundation

/// The content of one `YYYY-MM.jsonl`: its blocks and background stretches in file order, the
/// headers' context maps, and the number of malformed lines.
public struct BlockLogFile: Sendable {
    /// A block with the header context map in effect where it was written.
    public struct Entry: Sendable, Hashable {
        public var block: ActivityBlock
        /// The detail-log fields, for a line of the detail log.
        public var detail: ActivityBlockDetail?
        public var contexts: [String: String]
    }

    /// A background stretch with the header context map in effect where it was written.
    public struct BackgroundEntry: Sendable, Hashable {
        public var stretch: ActivityBackgroundStretch
        public var contexts: [String: String]
    }

    public var entries: [Entry]
    /// The background stretches in file order.
    public var backgrounds: [BackgroundEntry]
    /// The last header of the file.
    public var lastHeader: BlockLogHeader?
    /// Every header's contexts merged, later headers winning.
    public var contexts: [String: String]
    /// Lines that are neither valid objects nor blank.
    public var malformedLines: Int

    /// Parses JSON Lines: headers set the `tz` for the lines that follow,
    /// objects with a `type` other than `header` and `background` are skipped, blank lines are ignored,
    /// and everything else unreadable counts as malformed.
    public init(data: Data) {
        let decoder = JSONDecoder()
        var parsed: [Entry] = []
        var stretches: [BackgroundEntry] = []
        var header: BlockLogHeader?
        var merged: [String: String] = [:]
        var malformed = 0
        for line in data.split(separator: UInt8(ascii: "\n")) where !Self.isBlank(line) {
            do {
                switch try BlockLogLine.parse(Data(line), header: header, decoder: decoder) {
                case let .header(value):
                    header = value
                    merged.merge(value.contexts) { _, new in new }
                case let .block(block, detail):
                    parsed.append(Entry(block: block, detail: detail, contexts: header?.contexts ?? [:]))
                case let .background(stretch):
                    stretches.append(BackgroundEntry(stretch: stretch, contexts: header?.contexts ?? [:]))
                case .other:
                    break
                }
            } catch {
                malformed += 1
            }
        }
        self.entries = parsed
        self.backgrounds = stretches
        self.lastHeader = header
        self.contexts = merged
        self.malformedLines = malformed
    }

    /// Reads and parses `url`; a missing file is empty.
    public init(contentsOf url: URL) throws(ActivityError) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            self.init(data: Data())
            return
        }
        do {
            try self.init(data: Data(contentsOf: url))
        } catch {
            throw .fileSystem("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// The blocks in file order.
    public var blocks: [ActivityBlock] {
        entries.map(\.block)
    }

    private static func isBlank(_ line: Data.SubSequence) -> Bool {
        line.allSatisfy { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") || $0 == UInt8(ascii: "\r") }
    }
}
