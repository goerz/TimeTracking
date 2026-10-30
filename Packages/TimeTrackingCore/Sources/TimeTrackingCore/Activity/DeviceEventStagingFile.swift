// DeviceEventStagingFile: the append-only events.jsonl of the iOS App Group
// (spec_data_and_sync.md §6, spec_activity_tracking.md §6.2).

public import Foundation

/// Stages device events in `events.jsonl` until the app flushes them.
///
/// The app and its extensions append from separate processes, so every
/// access holds an exclusive `flock` on the file. A flush uploads what it
/// read through the injected uploader and then removes only those bytes,
/// keeping events appended during the upload. A malformed line is skipped
/// and removed with the flushed ones.
public struct DeviceEventStagingFile: DeviceEventSink {
    public typealias Uploader = @Sendable ([DeviceEvent]) async throws -> Void

    /// The staging file, `<folder>/events.jsonl`.
    public let fileURL: URL
    private let uploader: Uploader

    public init(folder: URL, uploader: @escaping Uploader) {
        self.fileURL = folder.appending(path: "events.jsonl", directoryHint: .notDirectory)
        self.uploader = uploader
    }

    /// Appends `event` as one JSON line.
    public func append(_ event: DeviceEvent) throws(ActivityError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let line: Data
        do {
            line = try encoder.encode(event) + Data("\n".utf8)
        } catch {
            throw .fileSystem("cannot encode an event: \(error.localizedDescription)")
        }
        try withLockedFile { handle in
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        }
    }

    /// Every staged event, oldest first.
    public func readAll() throws(ActivityError) -> [DeviceEvent] {
        try withLockedFile { handle in
            try Self.decode(handle.readToEnd() ?? Data()).events
        }
    }

    /// Uploads the staged events and removes them from the file. When the
    /// upload throws, the file is unchanged and the error propagates.
    public func flush() async throws {
        let staged = try withLockedFile { handle in
            try Self.decode(handle.readToEnd() ?? Data())
        }
        if !staged.events.isEmpty {
            try await uploader(staged.events)
        }
        guard staged.consumedBytes > 0 else {
            return
        }
        try withLockedFile { handle in
            try handle.seek(toOffset: 0)
            let remainder = try handle.readToEnd()?.dropFirst(staged.consumedBytes) ?? Data()
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
