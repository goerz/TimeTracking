// SampleStore: the Samples and `meta` of samples.sqlite, written only
// through `insert` and `replace` (activity_tracking.md §4.1).

public import Foundation
public import GRDB

/// The Samples of `samples.sqlite` and its `meta` table.
///
/// Every write is one transaction that also marks the dates it changed, so
/// no write skips the deleted ranges, the frozen dates, or the exclusions,
/// and none forgets to mark a date.
public final class SampleStore: Sendable {
    public let database: any DatabaseWriter

    /// Opens `url`, or an in-memory database for `nil`.
    public init(url: URL?) throws {
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.database = try DatabasePool(path: url.path)
        } else {
            self.database = try DatabaseQueue()
        }
        var migrator = DatabaseMigrator()
        migrator.registerMigration("samples") { database in
            try database.execute(sql: """
            CREATE TABLE samples (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                time INTEGER NOT NULL,
                device TEXT NOT NULL,
                source TEXT NOT NULL,
                state TEXT NOT NULL,
                items TEXT NOT NULL
            );
            CREATE INDEX samples_time ON samples(time);
            CREATE INDEX samples_device_time ON samples(device, time);
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)
            try database.execute(sql: Self.deviceEventTable)
        }
        try migrator.migrate(database)
    }

    // MARK: Writes

    /// Stores the Samples outside every deleted range and on no frozen
    /// date, with the exclusions applied, and marks their dates. Returns
    /// the dates it marked.
    @discardableResult
    public func insert(_ samples: [Sample], rules: SampleRules) throws -> Set<TrackingDay> {
        try database.write { database in
            let kept = try Self.admissible(samples, rules: rules, in: database)
            try Self.store(kept, in: database)
            return try Self.markDays(of: kept, rules: rules, in: database)
        }
    }

    /// Replaces the selected Samples with `samples` when they differ;
    /// returns the Samples it replaced and those it stored, or `nil` when
    /// nothing changed.
    ///
    /// The new Samples are filtered as `insert` filters them before the
    /// comparison, and only those inside the selection are kept, so a
    /// repeated replace with the same input changes nothing.
    @discardableResult
    public func replace(
        _ selection: SampleSelection,
        with samples: [Sample],
        rules: SampleRules
    ) throws -> (old: [Sample], new: [Sample])? {
        try database.write { database in
            try Self.replace(selection, with: samples, rules: rules, in: database)
        }
    }

    /// Deletes the Samples of `range`, adds it to the deleted ranges, and
    /// marks its unfrozen dates; the range ends at `now` at the latest
    /// (§2.6), and one that is empty then changes nothing. Returns the
    /// marked dates.
    @discardableResult
    public func deleteRange(_ range: DateInterval, now: Date, rules: SampleRules) throws -> Set<TrackingDay> {
        guard range.start < now else {
            return []
        }
        let clipped = DateInterval(start: range.start, end: min(range.end, now))
        guard clipped.duration > 0 else {
            return []
        }
        return try database.write { database in
            let selection = SampleSelection(range: clipped)
            let old = try Self.samples(selection, in: database)
            try Self.delete(selection, in: database)
            try database.setMeta(
                .deletedRanges,
                (database.meta(.deletedRanges) ?? []) + [DeletedRange(start: clipped.start, end: clipped.end)]
            )
            let boundaries = try Self.boundaries(rules, in: database)
            var days = Set([boundaries.day(containing: clipped.start)])
            var day = boundaries.day(containing: clipped.start)
            while day < boundaries.day(containing: clipped.end - 1) {
                day = day.adding(days: 1)
                days.insert(day)
            }
            return try Self.markDays(of: old, rules: rules, in: database).union(Self.mark(days, rules: rules, in: database))
        }
    }

    /// Applies `rules`' exclusions to the Samples of `days`, updating the
    /// Items of each that changes, and marks the dates that changed as
    /// `insert` would. A Sample left without Items keeps its state, which
    /// may end a block or show the Mac took a Sample.
    @discardableResult
    public func reapplyExclusions(on days: ClosedRange<TrackingDay>, rules: SampleRules) throws -> Set<TrackingDay> {
        try database.write { database in
            let boundaries = try Self.boundaries(rules, in: database)
            let start = boundaries.start(of: days.lowerBound)
            let end = boundaries.start(of: days.upperBound.adding(days: 1))
            let rows = try Row.fetchAll(
                database,
                sql: "SELECT id, time, device, source, state, items FROM samples WHERE time >= ? AND time < ?",
                arguments: [Self.seconds(start), Self.seconds(end)]
            )
            var changed: [Sample] = []
            for row in rows {
                guard let sample = Self.sample(row) else {
                    continue
                }
                let filtered = sample.mapItems(rules.exclusions.applied(to:))
                if filtered != sample {
                    let id: Int64 = row["id"]
                    try database.execute(sql: "UPDATE samples SET items = ? WHERE id = ?", arguments: [filtered.itemsJSON, id])
                    changed.append(sample)
                }
            }
            return try Self.markDays(of: changed, rules: rules, in: database)
        }
    }

    /// Marks `days` (the unfrozen ones) for the rebuild loop.
    public func mark(_ days: Set<TrackingDay>, rules: SampleRules) throws {
        try database.write { database in
            _ = try Self.mark(days, rules: rules, in: database)
        }
    }

    // MARK: Reads

    /// The Samples of `selection`, by time.
    public func samples(_ selection: SampleSelection) throws -> [Sample] {
        try database.read { try Self.samples(selection, in: $0) }
    }

    /// The times of the live Samples in `range`, for finding the gaps.
    public func liveTimes(in range: DateInterval) throws -> [Date] {
        try database.read { database in
            try Int.fetchAll(
                database,
                sql: "SELECT time FROM samples WHERE source = ? AND time >= ? AND time < ? ORDER BY time",
                arguments: [SampleSource.live.rawValue, Self.seconds(range.start), Self.seconds(range.end)]
            ).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }
    }

    /// The dates holding Samples, of `deviceID` when given.
    public func days(withDevice deviceID: String? = nil, rules: SampleRules) throws -> Set<TrackingDay> {
        try database.read { database in
            let boundaries = try Self.boundaries(rules, in: database)
            let times = try deviceID.map { try Int.fetchAll(database, sql: "SELECT time FROM samples WHERE device = ?", arguments: [$0]) }
                ?? Int.fetchAll(database, sql: "SELECT time FROM samples")
            return Set(times.map { boundaries.day(containing: Date(timeIntervalSince1970: TimeInterval($0))) })
        }
    }

    /// The distinct workspaces of the stored Samples' Items, for learning
    /// the repositories among them (§2.3 rule 4).
    public func workspaces() throws -> Set<String> {
        try database.read { database in
            let rows = try String.fetchAll(
                database,
                sql: """
                SELECT DISTINCT json_extract(items, '$.f.ws') FROM samples WHERE json_extract(items, '$.f.ws') IS NOT NULL
                UNION SELECT DISTINCT json_extract(value, '$.ws') FROM samples, json_each(samples.items, '$.b')
                """
            )
            return Set(rows)
        }
    }

    /// The value of a `meta` key.
    public func meta<Value>(_ key: MetaKey<Value>) throws -> Value? {
        try database.read { try $0.meta(key) }
    }

    /// Sets a `meta` key.
    public func setMeta<Value>(_ key: MetaKey<Value>, _ value: Value?) throws {
        try database.write { try $0.setMeta(key, value) }
    }

    /// The day boundaries of the stored offsets in `rules`' zone.
    public func boundaries(rules: SampleRules) throws -> DayBoundaries {
        try database.read { try Self.boundaries(rules, in: $0) }
    }

    // MARK: Helpers

    static func boundaries(_ rules: SampleRules, in database: Database) throws -> DayBoundaries {
        try DayBoundaries(zone: rules.zone, offsets: database.meta(.dayOffsets) ?? [:])
    }

    /// The Samples `insert` stores: outside every deleted range, on no
    /// frozen date, with the exclusions applied.
    private static func admissible(_ samples: [Sample], rules: SampleRules, in database: Database) throws -> [Sample] {
        let ranges = try database.meta(.deletedRanges) ?? []
        let boundaries = try boundaries(rules, in: database)
        let cutoff = try database.meta(.cutoffDay)
        return samples.compactMap { sample in
            guard !ranges.contains(where: { $0.contains(sample.time) }) else {
                return nil
            }
            if let cutoff, boundaries.day(containing: sample.time) < cutoff {
                return nil
            }
            return sample.mapItems(rules.exclusions.applied(to:))
        }
    }

    /// Marks the date of every Sample, and the date before for a Sample
    /// within `max_passive_block` of its date's 00:00, since that date's
    /// pass reads it too.
    @discardableResult
    private static func markDays(of samples: [Sample], rules: SampleRules, in database: Database) throws -> Set<TrackingDay> {
        let boundaries = try boundaries(rules, in: database)
        var days: Set<TrackingDay> = []
        for sample in samples {
            let day = boundaries.day(containing: sample.time)
            days.insert(day)
            if sample.time < boundaries.start(of: day) + rules.maxPassiveBlock {
                days.insert(day.adding(days: -1))
            }
        }
        return try mark(days, rules: rules, in: database)
    }

    /// Adds the unfrozen `days` to `changed_dates`, fixing the offset of
    /// each date's 00:00 the first time; returns the dates marked.
    static func mark(_ days: Set<TrackingDay>, rules: SampleRules, in database: Database) throws -> Set<TrackingDay> {
        let cutoff = try database.meta(.cutoffDay)
        let unfrozen = days.filter { day in cutoff.map { day >= $0 } ?? true }
        guard !unfrozen.isEmpty else {
            return []
        }
        var boundaries = try boundaries(rules, in: database)
        // Fixes every date's offset; `contains` alone would stop at the first.
        if unfrozen.map({ boundaries.fix($0) }).contains(true) {
            try database.setMeta(.dayOffsets, boundaries.offsets)
        }
        try database.setMeta(.changedDays, (database.meta(.changedDays) ?? []).union(unfrozen))
        return unfrozen
    }

    private static func store(_ samples: [Sample], in database: Database) throws {
        for sample in samples {
            try database.execute(
                sql: "INSERT INTO samples (time, device, source, state, items) VALUES (?, ?, ?, ?, ?)",
                arguments: [seconds(sample.time), sample.deviceID, sample.source.rawValue, sample.state.rawValue, sample.itemsJSON]
            )
        }
    }

    private static func samples(_ selection: SampleSelection, in database: Database) throws -> [Sample] {
        let (condition, arguments) = whereClause(selection)
        return try Row.fetchAll(
            database,
            sql: "SELECT time, device, source, state, items FROM samples WHERE \(condition) ORDER BY time, id",
            arguments: arguments
        ).compactMap(sample)
    }

    static func delete(_ selection: SampleSelection, in database: Database) throws {
        let (condition, arguments) = whereClause(selection)
        try database.execute(sql: "DELETE FROM samples WHERE \(condition)", arguments: arguments)
    }

    private static func whereClause(_ selection: SampleSelection) -> (String, StatementArguments) {
        var condition = "time >= ? AND time < ?"
        var values: [any DatabaseValueConvertible] = [seconds(selection.range.start), seconds(selection.range.end)]
        if let deviceID = selection.deviceID {
            condition += " AND device = ?"
            values.append(deviceID)
        }
        if let sources = selection.sources {
            condition += " AND source IN (\(sources.map { _ in "?" }.joined(separator: ",")))"
            values += sources.map(\.rawValue).sorted()
        }
        return (condition, StatementArguments(values))
    }

    private static func sample(_ row: Row) -> Sample? {
        guard let source = SampleSource(rawValue: row["source"]), let state = TrackerPresenceState(rawValue: row["state"]) else {
            return nil
        }
        let items = Sample.items(fromJSON: row["items"])
        let time: Int = row["time"]
        return Sample(
            time: Date(timeIntervalSince1970: TimeInterval(time)),
            deviceID: row["device"],
            source: source,
            state: state,
            foreground: items.foreground,
            background: items.background
        )
    }

    /// A text per Sample, sorted, to compare two lists of Samples as sets.
    private static func sortedKeys(_ samples: [Sample]) -> [String] {
        samples.map { "\(seconds($0.time))|\($0.deviceID)|\($0.source.rawValue)|\($0.state.rawValue)|\($0.itemsJSON)" }.sorted()
    }

    /// Whole seconds since 1970, as stored.
    static func seconds(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }
}

extension SampleStore {
    /// `replace` inside a transaction the caller holds.
    static func replace(
        _ selection: SampleSelection,
        with samples: [Sample],
        rules: SampleRules,
        in database: Database
    ) throws -> (old: [Sample], new: [Sample])? {
        let new = try admissible(samples.filter(selection.contains), rules: rules, in: database)
        let old = try Self.samples(selection, in: database)
        guard sortedKeys(old) != sortedKeys(new) else {
            return nil
        }
        try delete(selection, in: database)
        try store(new, in: database)
        try markDays(of: old + new, rules: rules, in: database)
        return (old, new)
    }
}
