// BlockLogFolder: the date files of the block log, `blocks/YYYY-MM-DD.jsonl`
// (activity_tracking.md §4.1, §4.2).

public import Foundation

/// One `blocks/` folder: a file per local date, each replaced whole.
public struct BlockLogFolder: Sendable, Hashable {
    public var url: URL
    /// Whether the folder is in iCloud Drive, where writes are coordinated.
    public var isUbiquitous: Bool

    public init(url: URL, isUbiquitous: Bool = false) {
        self.url = url
        self.isUbiquitous = isUbiquitous
    }

    /// The content of a date file as far as this device has it.
    public enum Content: Sendable, Hashable {
        case missing
        /// iCloud Drive holds only a placeholder or a dataless file; its download was asked for.
        case pendingDownload
        case unreadable(String)
        case text(String)
    }

    /// What a write did.
    public enum WriteResult: Sendable, Hashable {
        case written
        /// The file already held this text, or there was none and no block to write.
        case unchanged
        /// iCloud Drive holds the file only as a placeholder; nothing was written.
        case pendingDownload
    }

    public func fileURL(for day: TrackingDay) -> URL {
        url.appending(path: "\(day).jsonl", directoryHint: .notDirectory)
    }

    /// The dates with a file here, placeholders included, in order.
    public func days() -> [TrackingDay] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.compactMap(Self.day(ofFileName:)).sorted()
    }

    /// The date a file name stands for: `2026-11-07.jsonl` or its
    /// placeholder `.2026-11-07.jsonl.icloud`.
    static func day(ofFileName name: String) -> TrackingDay? {
        var stem = name
        if stem.hasPrefix("."), stem.hasSuffix(".icloud") {
            stem = String(stem.dropFirst().dropLast(".icloud".count))
        }
        guard stem.hasSuffix(".jsonl") else {
            return nil
        }
        return TrackingDay(String(stem.dropLast(".jsonl".count)))
    }

    /// The content of the date's file.
    public func content(for day: TrackingDay) -> Content {
        let file = fileURL(for: day)
        if ActivityFile.isPendingDownload(file) {
            return .pendingDownload
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            return .missing
        }
        do {
            return try .text(String(contentsOf: file, encoding: .utf8))
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    /// The modification time of the date's file, for readers' caches.
    public func modificationDate(for day: TrackingDay) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL(for: day).path))?[.modificationDate] as? Date
    }

    /// Replaces the date's file with the blocks. A file already holding
    /// that text is left untouched, as is a missing file when there are no
    /// blocks; a placeholder is never written.
    @discardableResult
    public func write(_ blocks: [ActivityBlock], for day: TrackingDay) throws -> WriteResult {
        try write(text: BlockLogFile.text(of: blocks), for: day, isEmpty: blocks.isEmpty)
    }

    /// Replaces the date's file with `text` under the same rules.
    @discardableResult
    public func write(text: String, for day: TrackingDay, isEmpty: Bool = false) throws -> WriteResult {
        let file = fileURL(for: day)
        if ActivityFile.isPendingDownload(file) {
            return .pendingDownload
        }
        let existing = try? String(contentsOf: file, encoding: .utf8)
        if existing == text || (existing == nil && isEmpty) {
            return .unchanged
        }
        try ActivityFile.write(Data(text.utf8), to: file, coordinated: isUbiquitous)
        return .written
    }
}
