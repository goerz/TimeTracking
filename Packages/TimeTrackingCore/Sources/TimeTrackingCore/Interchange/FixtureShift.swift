// FixtureShift: a fixture document moved to the current date for `make demo`
// (architecture.md §2.5, §3.4).

public import Foundation

/// Moves an export-format document by whole calendar days so that the day
/// of its `generatedAt` (the fixture's "today", 2024-03-14) becomes today.
///
/// Times keep their wall-clock values, also across a DST change, and move
/// into `timeZone`. A running entry keeps its age: it started as long
/// before `now` as it did before `generatedAt`. A finished entry that would
/// end after `now` (or after the running entry's start) ends there, and one
/// that would start at or after that moment is dropped.
public struct FixtureShift: Sendable {
    /// The document's "now", its `generatedAt`.
    public var fixtureNow: Date
    /// The zone the fixture's days are counted in (its entries' zone).
    public var fixtureZone: TimeZone
    public var now: Date
    public var timeZone: TimeZone

    public init(fixtureNow: Date, fixtureZone: TimeZone, now: Date, timeZone: TimeZone) {
        self.fixtureNow = fixtureNow
        self.fixtureZone = fixtureZone
        self.now = now
        self.timeZone = timeZone
    }

    /// The shift of `document`: its `generatedAt` and the zone of its first
    /// entry (`timeZone` without entries).
    public init(document: Data, now: Date, timeZone: TimeZone) throws {
        let object = try Self.object(document)
        guard let text = object["generatedAt"] as? String, let generatedAt = Self.date(text) else {
            throw StoreError.invalidDocument(path: "generatedAt", reason: "missing or not an RFC 3339 time")
        }
        let zone = ((object["entries"] as? [[String: Any]])?.first?["timeZone"] as? String).flatMap(TimeZone.init(identifier:))
        self.init(fixtureNow: generatedAt, fixtureZone: zone ?? timeZone, now: now, timeZone: timeZone)
    }

    /// Whole calendar days from the fixture's today to today.
    public var days: Int {
        TrackingCalendar(timeZone: fixtureZone).day(containing: fixtureNow)
            .distance(to: TrackingCalendar(timeZone: timeZone).day(containing: now))
    }

    /// `date`, read as wall-clock time in `zone`, moved by `days` and
    /// placed at the same wall-clock time in `timeZone`.
    public func shifted(_ date: Date, from zone: TimeZone) -> Date {
        if let moved = Self.wallClock(date, from: zone, to: timeZone, addingDays: days) {
            return moved
        }
        let day = TrackingCalendar(timeZone: zone).day(containing: date).adding(days: days)
        return TrackingCalendar(timeZone: timeZone).startOfDay(day)
    }

    /// `date`, read as wall-clock time in `zone`, moved by `days` calendar
    /// days and placed at the same wall-clock time in `target`; `nil` when
    /// the calendar cannot build that time.
    static func wallClock(_ date: Date, from zone: TimeZone, to target: TimeZone, addingDays days: Int) -> Date? {
        let day = TrackingCalendar(timeZone: zone).day(containing: date).adding(days: days)
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = zone
        var parts = sourceCalendar.dateComponents([.hour, .minute, .second], from: date)
        parts.year = day.year
        parts.month = day.month
        parts.day = day.day
        var targetCalendar = Calendar(identifier: .gregorian)
        targetCalendar.timeZone = target
        return targetCalendar.date(from: parts)
    }

    /// The result of `apply(to:)`.
    public struct Result: Sendable {
        public var document: Data
        /// Finished entries cut at now (or at the running entry's start).
        public var clipped: Int
        /// Entries that would have started at or after that moment.
        public var dropped: Int
    }

    /// `document` moved to today, with `generatedAt` set to `now`.
    public func apply(to document: Data) throws -> Result {
        var object = try Self.object(document)
        let entries = object["entries"] as? [[String: Any]] ?? []
        let runningStarts = entries.compactMap { entry in
            entry["end"] is String ? nil : (entry["start"] as? String).flatMap(Self.date).map { now - fixtureNow.timeIntervalSince($0) }
        }
        let limit = min(runningStarts.min() ?? now, now)
        var result = Result(document: Data(), clipped: 0, dropped: 0)
        var moved: [[String: Any]] = []
        for var entry in entries {
            let zone = (entry["timeZone"] as? String).flatMap(TimeZone.init(identifier:)) ?? fixtureZone
            guard let start = (entry["start"] as? String).flatMap(Self.date) else {
                moved.append(entry)
                continue
            }
            if let end = (entry["end"] as? String).flatMap(Self.date) {
                let newStart = shifted(start, from: zone)
                guard newStart < limit else {
                    result.dropped += 1
                    continue
                }
                var newEnd = shifted(end, from: zone)
                if newEnd > limit {
                    newEnd = limit
                    result.clipped += 1
                }
                entry["start"] = TimeStore.rfc3339(newStart)
                entry["end"] = TimeStore.rfc3339(newEnd)
            } else {
                let newStart = now - fixtureNow.timeIntervalSince(start)
                guard newStart <= now else {
                    result.dropped += 1
                    continue
                }
                entry["start"] = TimeStore.rfc3339(newStart)
            }
            moveTimestamps(of: &entry, from: zone, except: ["start", "end"])
            entry["timeZone"] = timeZone.identifier
            moved.append(entry)
        }
        object["entries"] = moved
        for key in ["clients", "areas", "projects", "devices"] {
            guard var records = object[key] as? [[String: Any]] else {
                continue
            }
            for index in records.indices {
                moveTimestamps(of: &records[index], from: fixtureZone, except: [])
            }
            object[key] = records
        }
        object["generatedAt"] = TimeStore.rfc3339(now)
        result.document = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return result
    }

    /// Moves every `…At` time of `record` (`createdAt`, `archivedAt`, …),
    /// never past `now`.
    private func moveTimestamps(of record: inout [String: Any], from zone: TimeZone, except: Set<String>) {
        for (key, value) in record where key.hasSuffix("At") && !except.contains(key) {
            if let text = value as? String, let date = Self.date(text) {
                record[key] = TimeStore.rfc3339(min(shifted(date, from: zone), now))
            }
        }
    }

    private static func object(_ document: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: document) as? [String: Any] else {
            throw StoreError.invalidDocument(path: "$", reason: "not a JSON object")
        }
        return object
    }

    /// The instant of an RFC 3339 text, or `nil`.
    static func date(_ text: String) -> Date? {
        try? Date.ISO8601FormatStyle().parse(text)
    }
}
