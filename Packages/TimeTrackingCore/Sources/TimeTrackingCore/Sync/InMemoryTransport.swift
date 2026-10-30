// InMemoryTransport: a simulated CloudKit zone for tests and -UITesting
// (spec_data_and_sync.md §3.3), with change tags, delays, partitions, and
// serverRecordChanged.

public import Foundation

/// The simulated server: one zone shared by every device's transport.
public actor InMemorySyncServer {
    private struct Stored {
        var record: SyncRecord
        var tag: Int
    }

    private struct Change {
        var sequence: Int
        var ref: SyncRecordRef
        var visibleAt: Date
    }

    private let clock: any Clock
    private var records: [SyncRecordRef: Stored] = [:]
    private var log: [Change] = []
    private var sequence = 0
    private var nextTag = 0
    private var zoneExists = true
    private var partitioned: Set<String> = []
    /// Seconds before a saved change becomes visible to fetches.
    public var delay: TimeInterval = 0
    /// The number of `serverRecordChanged` rejections so far.
    public private(set) var conflictCount = 0

    public init(clock: any Clock = SystemClock()) {
        self.clock = clock
    }

    /// A transport for the device `name`.
    public nonisolated func transport(for name: String) -> InMemoryTransport {
        InMemoryTransport(server: self, device: name)
    }

    /// Cuts the device off (`true`) or reconnects it.
    public func setPartitioned(_ device: String, _ isPartitioned: Bool) {
        if isPartitioned {
            partitioned.insert(device)
        } else {
            partitioned.remove(device)
        }
    }

    public func setDelay(_ seconds: TimeInterval) {
        delay = seconds
    }

    /// Deletes the zone with every record, as a reset in the dashboard would.
    public func deleteZone() {
        zoneExists = false
        records = [:]
        log = []
    }

    /// The server's copy of a record.
    public func record(_ ref: SyncRecordRef) -> SyncRecord? {
        records[ref]?.record
    }

    /// Every record on the server.
    public var allRecords: [SyncRecord] {
        records.values.map(\.record).sorted { $0.ref.description < $1.ref.description }
    }

    func checkReachable(_ device: String) throws {
        if partitioned.contains(device) {
            throw SyncTransportError.networkUnavailable
        }
    }

    func send(from device: String, saving saves: [SyncRecord], deleting deletions: [SyncRecordRef]) throws -> [SyncSaveResult] {
        try checkReachable(device)
        guard zoneExists else {
            return saves.map { .zoneNotFound($0.ref) } + deletions.map { .zoneNotFound($0) }
        }
        var results: [SyncSaveResult] = []
        for record in saves {
            let stored = records[record.ref]
            let knownTag = record.systemFields.flatMap(Self.tag)
            switch (stored, knownTag) {
            case let (stored?, known) where known != stored.tag:
                conflictCount += 1
                results.append(.conflict(server: stored.record))
            case (nil, .some):
                results.append(.unknownItem(record.ref))
            default:
                nextTag += 1
                var saved = record
                saved.systemFields = Self.systemFields(nextTag)
                records[record.ref] = Stored(record: saved, tag: nextTag)
                appendChange(record.ref)
                results.append(.saved(saved))
            }
        }
        for ref in deletions {
            if records.removeValue(forKey: ref) != nil {
                appendChange(ref)
            }
            results.append(.deleted(ref))
        }
        return results
    }

    func fetch(for device: String, since token: Data?) throws -> SyncFetchResult {
        try checkReachable(device)
        guard zoneExists else {
            throw SyncTransportError.zoneNotFound
        }
        let start = token.flatMap(Self.tag) ?? 0
        let now = clock.now
        let visible = log.filter { $0.sequence > start }.prefix { $0.visibleAt <= now }
        var changed: [SyncRecordRef] = []
        for change in visible where !changed.contains(change.ref) {
            changed.append(change.ref)
        }
        let end = visible.last?.sequence ?? start
        return SyncFetchResult(
            records: changed.compactMap { records[$0]?.record },
            deletions: changed.filter { records[$0] == nil },
            token: Self.systemFields(end)
        )
    }

    func createZone() {
        zoneExists = true
    }

    private func appendChange(_ ref: SyncRecordRef) {
        sequence += 1
        log.append(Change(sequence: sequence, ref: ref, visibleAt: clock.now + delay))
    }

    private static func systemFields(_ tag: Int) -> Data {
        Data("tag:\(tag)".utf8)
    }

    private static func tag(_ data: Data) -> Int? {
        let text = String(decoding: data, as: UTF8.self)
        return text.hasPrefix("tag:") ? Int(text.dropFirst(4)) : nil
    }
}

/// One device's connection to an `InMemorySyncServer`.
public struct InMemoryTransport: SyncTransport {
    public let server: InMemorySyncServer
    public let device: String

    public init(server: InMemorySyncServer, device: String) {
        self.server = server
        self.device = device
    }

    public func send(saving records: [SyncRecord], deleting refs: [SyncRecordRef]) async throws -> [SyncSaveResult] {
        try await server.send(from: device, saving: records, deleting: refs)
    }

    public func fetchChanges(since token: Data?) async throws -> SyncFetchResult {
        try await server.fetch(for: device, since: token)
    }

    public func createZone() async throws {
        try await server.checkReachable(device)
        await server.createZone()
    }
}
