// TimeStore: the store actor (data_and_sync.md §2, §7).

public import Foundation
import GRDB
import os

/// The time-entry store: one SQLite database in WAL mode (or in memory),
/// behind a serial actor. It implements every reading and writing protocol
/// of the query layer.
///
/// Open it with `TimeStore.open(_:)`, which migrates the schema, runs the
/// invariant pass, and starts listening for other processes' changes.
public actor TimeStore {
    /// Where the database lives.
    public enum Location: Sendable, Equatable {
        /// A private in-memory database (tests, `-UITesting`, previews).
        case inMemory
        /// A file; created with the schema when missing.
        case file(URL)
    }

    public struct Configuration: Sendable {
        public var location: Location
        public var clock: any Clock
        /// The `deviceID` of this device (`DeviceSettings.deviceID`).
        public var deviceID: DeviceID
        /// The writing device's current zone, read at every write.
        public var timeZone: @Sendable () -> TimeZone
        /// Posts and receives the cross-process change signal; `nil` for none.
        public var notifier: (any ChangeNotifier)?
        /// Opens the file read-only (`?mode=ro` semantics); writes fail.
        public var readOnly: Bool
        /// How long a write waits for another process's write lock before
        /// failing with `StoreError.busy` (data_and_sync.md §2.2).
        public var busyTimeout: TimeInterval
        /// Called once when a write starts waiting for another process's
        /// lock (the tool's test seam); `nil` for none.
        public var onBusy: (@Sendable () -> Void)?

        @preconcurrency
        public init(
            location: Location,
            clock: any Clock = SystemClock(),
            deviceID: DeviceID,
            timeZone: @escaping @Sendable () -> TimeZone = { .current },
            notifier: (any ChangeNotifier)? = nil,
            readOnly: Bool = false,
            busyTimeout: TimeInterval = TimeStore.defaultBusyTimeout
        ) {
            self.busyTimeout = busyTimeout
            self.location = location
            self.clock = clock
            self.deviceID = deviceID
            self.timeZone = timeZone
            self.notifier = notifier
            self.readOnly = readOnly
        }
    }

    public nonisolated let clock: any Clock
    public nonisolated let deviceID: DeviceID
    public nonisolated let location: Location
    nonisolated let reader: any DatabaseReader
    let writer: (any DatabaseWriter)?
    let timeZone: @Sendable () -> TimeZone
    nonisolated let notifier: (any ChangeNotifier)?
    nonisolated let broadcaster = ChangeBroadcaster()
    var adjustmentRing: [EntryAdjustment] = []
    var lastRunning: TimeEntry?
    var externalChanges: Task<Void, Never>?
    /// `PRAGMA data_version` of the writer connection at the last
    /// notification: it changes only when another connection commits.
    var dataVersion: Int?
    /// Each setting row's value and deletion as last seen, to report the
    /// keys another process changed.
    var knownSettings: [String: String] = [:]
    static let logger = Logging.logger(category: "Store")
    /// The busy timeout of §2.2: a write outlasts another writer's 2-second
    /// transaction but not a 10-second one.
    public static let defaultBusyTimeout: TimeInterval = 5
    /// The wait between retries of a busy write with `onBusy`.
    static let busyRetryInterval: TimeInterval = 0.01

    /// Opens the database and migrates it; prefer `open(_:)`.
    public init(_ configuration: Configuration) throws {
        var options = GRDB.Configuration()
        if let onBusy = configuration.onBusy {
            // The timeout of `.timeout`, with a report at the first wait.
            let timeout = configuration.busyTimeout
            options.busyMode = .callback { tries in
                if tries == 0 {
                    onBusy()
                }
                guard Double(tries) * Self.busyRetryInterval < timeout else {
                    return false
                }
                usleep(useconds_t(Self.busyRetryInterval * 1_000_000))
                return true
            }
        } else {
            options.busyMode = .timeout(configuration.busyTimeout)
        }
        options.readonly = configuration.readOnly
        options.foreignKeysEnabled = false
        switch configuration.location {
        case .inMemory:
            let queue = try DatabaseQueue(configuration: options)
            self.reader = queue
            self.writer = queue
        case let .file(url):
            if configuration.readOnly {
                let reader: any DatabaseReader = if Self.isImmutable(url) {
                    try DatabaseQueue(path: url.absoluteString + "?immutable=1", configuration: options)
                } else {
                    try DatabasePool(path: url.path, configuration: options)
                }
                try Schema.check(reader)
                self.reader = reader
                self.writer = nil
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let pool = try DatabasePool(path: url.path, configuration: options)
                self.reader = pool
                self.writer = pool
            }
        }
        if let writer {
            try Schema.prepare(writer)
        }
        self.clock = configuration.clock
        self.deviceID = configuration.deviceID
        self.location = configuration.location
        self.timeZone = configuration.timeZone
        self.notifier = configuration.notifier
    }

    /// Opens the store, runs the invariant pass, and listens for other
    /// processes.
    public static func open(_ configuration: Configuration) async throws -> TimeStore {
        let store: TimeStore
        do {
            store = try TimeStore(configuration)
        } catch let error as DatabaseError {
            throw StoreError(error)
        }
        if !configuration.readOnly {
            try await store.checkInvariants()
        }
        await store.listenForExternalChanges()
        return store
    }

    /// Whether a file can only be read: its folder is not writable and it
    /// has no `-wal` file, so no writer can exist and SQLite (which cannot
    /// create the `-shm` file there) must open it as immutable.
    static func isImmutable(_ url: URL) -> Bool {
        let folder = url.deletingLastPathComponent().path
        return !FileManager.default.isWritableFile(atPath: folder) && !FileManager.default.fileExists(atPath: url.path + "-wal")
    }

    /// The schema version this library reads and writes.
    public static var schemaVersion: Int {
        Schema.version
    }

    /// An empty in-memory store.
    public static func inMemory(
        clock: any Clock = SystemClock(),
        deviceID: DeviceID = DeviceID(),
        timeZone: TimeZone = .current,
        notifier: (any ChangeNotifier)? = nil
    ) async throws -> TimeStore {
        try await open(Configuration(location: .inMemory, clock: clock, deviceID: deviceID, timeZone: { timeZone }, notifier: notifier))
    }

    /// Stops listening for other processes' changes and ends every stream.
    public func close() {
        externalChanges?.cancel()
        externalChanges = nil
        broadcaster.finish()
    }

    /// The store's id from `meta`.
    public func storeID() throws -> String {
        try read { database in
            try String.fetchOne(database, sql: "SELECT value FROM meta WHERE key = 'store_id'") ?? ""
        }
    }

    // MARK: Transactions

    /// Runs one write transaction: the operation, the invariant pass, the
    /// rename of a legacy setting key, the outbox rows, commit, then the
    /// notification and observer events.
    func write<R>(_ body: (StoreTransaction) throws -> R) throws -> R {
        let (result, outcome) = try perform { transaction in
            let result = try body(transaction)
            try transaction.runInvariantPass()
            try transaction.renameLegacySettings()
            try transaction.updateLiveStateSnapshot()
            return result
        }
        try didCommit(outcome)
        return result
    }

    /// Opens a transaction, runs `body`, appends the outbox rows, commits.
    func perform<R>(_ body: (StoreTransaction) throws -> R) throws -> (R, TransactionOutcome) {
        guard let writer else {
            throw StoreError.readOnly
        }
        let now = clock.now
        let zone = timeZone()
        do {
            return try writer.write { database in
                let transaction = StoreTransaction(database: database, now: now, deviceID: deviceID, timeZone: zone)
                let result = try body(transaction)
                try transaction.appendOutboxRows()
                return (result, TransactionOutcome(transaction))
            }
        } catch let error as DatabaseError {
            throw StoreError(error)
        }
    }

    func read<R>(_ body: (Database) throws -> R) throws -> R {
        do {
            return try reader.read(body)
        } catch let error as DatabaseError {
            throw StoreError(error)
        }
    }

    /// Runs the invariant pass alone.
    public func checkInvariants() throws {
        try write { _ in }
    }

    // MARK: Notification

    func didCommit(_ outcome: TransactionOutcome) throws {
        record(outcome.adjustments)
        guard outcome.hasChanges else {
            return
        }
        notifier?.post()
        if !outcome.changedEntryIDs.isEmpty {
            let running = try runningEntry()
            if outcome.isFromElsewhere, running?.id != lastRunning?.id {
                broadcaster.yield(.runningChangedElsewhere(running?.id))
            }
            broadcaster.yield(.entries(outcome.changedEntryIDs))
            if running != lastRunning {
                lastRunning = running
                broadcaster.yield(.runningEntry(running))
            }
        }
        if outcome.liveStateChanged {
            broadcaster.yield(.liveState)
        }
        if outcome.structureChanged {
            broadcaster.yield(.structure)
        }
        if outcome.healthChanged {
            broadcaster.yield(.health)
        }
        if !outcome.changedSettings.isEmpty {
            // This process's own changes are not another's to report later.
            let rows = settingRows()
            for key in outcome.changedSettings {
                knownSettings[key] = rows[key]
            }
            broadcaster.yield(.settings(outcome.changedSettings))
        }
        let own = outcome.adjustments.filter { ($0.before ?? $0.after)?.deviceID == deviceID }
        if !own.isEmpty {
            broadcaster.yield(.adjusted(own))
        }
    }

    private func record(_ adjustments: [EntryAdjustment]) {
        for adjustment in adjustments {
            Self.logger.info(
                "Adjusted entry \(adjustment.entryID.rawValue, privacy: .public): \(adjustment.reason.rawValue, privacy: .public)"
            )
        }
        adjustmentRing.append(contentsOf: adjustments)
        if adjustmentRing.count > 100 {
            adjustmentRing.removeFirst(adjustmentRing.count - 100)
        }
    }
}
