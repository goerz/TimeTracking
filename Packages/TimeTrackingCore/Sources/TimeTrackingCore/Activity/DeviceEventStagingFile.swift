// DeviceEventStagingFile: the append-only events.jsonl of the iOS App Group
// (data_and_sync.md §6, activity_tracking.md §6.2, ios.md
// §9.1, §9.6).

public import Foundation

/// Stages device events in `events.jsonl` until the app flushes them.
///
/// The app and its extensions append from separate processes, so every
/// access holds an exclusive `flock` on the file. Each append gets the next
/// `sequence`; the sidecar `events.state` keeps the next sequence and
/// `lastFlushedSeq`, the highest sequence CloudKit acknowledged. A flush
/// uploads the lines above `lastFlushedSeq` through the injected uploader,
/// advances `lastFlushedSeq` only when the upload returns, and then
/// rewrites the file with the lines above the new `lastFlushedSeq`,
/// keeping events appended during the upload. Removal goes by sequence,
/// never by byte count, so two overlapping flushes (each read the file
/// before the other trimmed it) cannot remove a line the other appended
/// meanwhile. A flush interrupted after the acknowledgement skips the
/// acknowledged lines next time; one interrupted before it re-sends them
/// under the same record names. A malformed line is skipped and removed
/// with the flushed ones.
public struct DeviceEventStagingFile: DeviceEventSink {
    public typealias Uploader = @Sendable ([DeviceEvent]) async throws -> Void

    /// The staging file, `<folder>/events.jsonl`.
    public let fileURL: URL
    /// The sidecar with the sequence counters, `<folder>/events.state`.
    public let stateURL: URL
    private let uploader: Uploader

    public init(folder: URL, uploader: @escaping Uploader) {
        self.fileURL = folder.appending(path: "events.jsonl", directoryHint: .notDirectory)
        self.stateURL = folder.appending(path: "events.state", directoryHint: .notDirectory)
        self.uploader = uploader
    }

    /// A file the extensions append to; flushing it throws (only the app flushes).
    public init(folder: URL) {
        self.init(folder: folder) { _ in
            throw ActivityError.fileSystem("only the app flushes the collection file")
        }
    }

    /// Appends `event` as one JSON line with the next sequence number.
    public func append(_ event: DeviceEvent) throws(ActivityError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try withLockedFile { handle in
            var counters = readCounters()
            var numbered = event
            numbered.sequence = counters.next
            counters.next += 1
            // The counter first: a crash in between skips a number, never reuses one.
            try writeCounters(counters)
            let line = try encoder.encode(numbered) + Data("\n".utf8)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        }
    }

    /// Every staged event not yet acknowledged, oldest first.
    public func readAll() throws(ActivityError) -> [DeviceEvent] {
        try withLockedFile { handle in
            let flushed = readCounters().flushed
            return try Self.decode(handle.readToEnd() ?? Data()).events.filter { $0.sequence > flushed }
        }
    }

    /// The highest sequence the uploader acknowledged (0 before the first flush).
    public func lastFlushedSequence() throws(ActivityError) -> Int {
        try withLockedFile { _ in readCounters().flushed }
    }

    /// Uploads the staged events and removes them from the file. When the
    /// upload throws, the file and `lastFlushedSeq` are unchanged and the
    /// error propagates.
    public func flush() async throws {
        let staged = try withLockedFile { handle in
            let flushed = readCounters().flushed
            var read = try Self.decode(handle.readToEnd() ?? Data())
            read.events.removeAll { $0.sequence <= flushed }
            return read
        }
        if !staged.events.isEmpty {
            try await uploader(staged.events)
        }
        guard staged.consumedBytes > 0 || !staged.events.isEmpty else {
            return
        }
        try withLockedFile { handle in
            var counters = readCounters()
            counters.flushed = max(counters.flushed, staged.events.map(\.sequence).max() ?? 0)
            try writeCounters(counters)
            try handle.seek(toOffset: 0)
            let remainder = try Self.unflushedLines(of: handle.readToEnd() ?? Data(), above: counters.flushed)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: remainder)
        }
    }

    // MARK: Helpers

    /// The events of the complete lines of `data` and the bytes they span.
    private static func decode(_ data: Data) -> StagedEvents {
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else {
            return StagedEvents(events: [], consumedBytes: 0)
        }
        let complete = data[data.startIndex ... lastNewline]
        let decoder = JSONDecoder()
        let events = complete.split(separator: UInt8(ascii: "\n")).compactMap { line in
            try? decoder.decode(DeviceEvent.self, from: Data(line))
        }
        return StagedEvents(events: events, consumedBytes: complete.count)
    }

    /// The bytes of `data` to keep after a flush: every complete line whose
    /// event is above `flushed`, unchanged, and an incomplete last line.
    /// Malformed complete lines go.
    private static func unflushedLines(of data: Data, above flushed: Int) -> Data {
        let decoder = JSONDecoder()
        var kept = Data()
        var start = data.startIndex
        while let newline = data[start...].firstIndex(of: UInt8(ascii: "\n")) {
            let line = data[start ..< newline]
            if let event = try? decoder.decode(DeviceEvent.self, from: Data(line)), event.sequence > flushed {
                kept.append(data[start ... newline])
            }
            start = data.index(after: newline)
        }
        kept.append(data[start...])
        return kept
    }

    /// The counters of the sidecar; call with the lock held.
    private func readCounters() -> Counters {
        guard let data = try? Data(contentsOf: stateURL), let counters = try? JSONDecoder().decode(Counters.self, from: data) else {
            return Counters(next: 1, flushed: 0)
        }
        return counters
    }

    /// Replaces the sidecar atomically; call with the lock held.
    private func writeCounters(_ counters: Counters) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(counters).write(to: stateURL, options: .atomic)
    }

    /// Runs `body` with the file open for reading and writing under an
    /// exclusive lock, creating the folder and the file as needed.
    private func withLockedFile<Value>(_ body: (FileHandle) throws -> Value) throws(ActivityError) -> Value {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw .fileSystem("\(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
        let descriptor = open(fileURL.path, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else {
            throw .fileSystem("\(fileURL.lastPathComponent): cannot open (errno \(errno))")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw .fileSystem("\(fileURL.lastPathComponent): cannot lock (errno \(errno))")
        }
        defer { flock(descriptor, LOCK_UN) }
        do {
            return try body(handle)
        } catch let error as ActivityError {
            throw error
        } catch {
            throw .fileSystem("\(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

/// The result of reading the staging file.
private struct StagedEvents {
    var events: [DeviceEvent]
    var consumedBytes: Int
}

/// The sidecar `events.state`: the next sequence and `lastFlushedSeq`.
private struct Counters: Codable {
    enum CodingKeys: String, CodingKey {
        case next
        case flushed = "lastFlushedSeq"
    }

    var next: Int
    var flushed: Int
}
