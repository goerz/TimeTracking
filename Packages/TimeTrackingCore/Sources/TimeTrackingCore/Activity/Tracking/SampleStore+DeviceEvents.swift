// SampleStore+DeviceEvents: the iPhones' and iPads' events as fetched, and
// the redo of one device-date (activity_tracking.md §2.5, §6.2).

import Foundation
import GRDB

extension SampleStore {
    /// The table of fetched DeviceEvents, created with the store: each
    /// event's device, local date, source, and label, for the queries of a
    /// redo, and the event itself as JSON.
    static let deviceEventTable = """
    CREATE TABLE IF NOT EXISTS device_events (
        name TEXT PRIMARY KEY,
        device TEXT NOT NULL,
        day TEXT NOT NULL,
        time INTEGER NOT NULL,
        source TEXT NOT NULL,
        label TEXT NOT NULL,
        json TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS device_events_day ON device_events(device, day);
    CREATE INDEX IF NOT EXISTS device_events_series ON device_events(device, source, label, time);
    """

    /// Stores newly fetched events with the change token after them, in one
    /// transaction with the device-dates to redo: each event's date and the
    /// date before it, which a late close can lengthen. A device's new name
    /// is kept and marks every date holding its Samples.
    public func storeDeviceEvents(_ events: [DeviceEvent], token: Data, rules: SampleRules) throws {
        try database.write { database in
            var pending = try Set(database.meta(.pendingRemoteDays) ?? [])
            var names = try database.meta(.deviceNames) ?? [:]
            var renamed: Set<String> = []
            for event in events.sorted(by: { ($0.time, $0.sequence) < ($1.time, $1.sequence) }) {
                guard let day = event.localDay else {
                    continue
                }
                try Self.insert(event, day: day, in: database)
                pending.insert(DeviceDay(deviceID: event.deviceID, day: day))
                pending.insert(DeviceDay(deviceID: event.deviceID, day: day.adding(days: -1)))
                if let name = event.deviceName, !name.isEmpty, names[event.deviceID] != name {
                    if names[event.deviceID] != nil {
                        renamed.insert(event.deviceID)
                    }
                    names[event.deviceID] = name
                }
            }
            try database.setMeta(.deviceNames, names)
            try database.setMeta(.pendingRemoteDays, pending.sorted())
            try database.setMeta(.cloudKitToken, token)
            let boundaries = try Self.boundaries(rules, in: database)
            for deviceID in renamed {
                let times = try Int.fetchAll(database, sql: "SELECT time FROM samples WHERE device = ?", arguments: [deviceID])
                _ = try Self.mark(
                    Set(times.map { boundaries.day(containing: Date(timeIntervalSince1970: TimeInterval($0))) }),
                    rules: rules,
                    in: database
                )
            }
        }
    }

    private static func insert(_ event: DeviceEvent, day: TrackingDay, in database: Database) throws {
        try database.execute(
            sql: "INSERT OR REPLACE INTO device_events (name, device, day, time, source, label, json) VALUES (?, ?, ?, ?, ?, ?, ?)",
            arguments: [
                event.recordName, event.deviceID, day.description, seconds(event.time), event.source.rawValue, event.label,
                String(decoding: JSONEncoder().encode(event), as: UTF8.self),
            ]
        )
    }

    /// Redoes one device-date: converts its stored events, with the
    /// device's last events before it and its first after it, into Samples
    /// and replaces the device's iOS Samples of that date. Returns whether
    /// what is on at the date's end changed; then the next date needs a
    /// redo too, which is queued unless it lies after `today`. Removes the
    /// device-date from the pending ones.
    @discardableResult
    public func redo(_ deviceDay: DeviceDay, converter: DeviceEventConverter, today: TrackingDay, rules: SampleRules) throws -> Bool {
        let (events, before, after, name, range) = try database.read { database in
            try (
                Self.events(
                    sql: "WHERE device = ? AND day = ? ORDER BY time",
                    [deviceDay.deviceID, deviceDay.day.description],
                    in: database
                ),
                Self.neighbors(of: deviceDay, before: true, in: database),
                Self.neighbors(of: deviceDay, before: false, in: database),
                database.meta(.deviceNames)?[deviceDay.deviceID],
                Self.range(of: deviceDay, zone: rules.zone, in: database)
            )
        }
        let samples = converter.samples(
            deviceID: deviceDay.deviceID,
            deviceName: name ?? deviceDay.deviceID,
            date: range,
            events: events,
            before: before,
            after: after
        )
        let selection = SampleSelection(range: range, deviceID: deviceDay.deviceID, sources: SampleSource.iOS)
        // One transaction, so a crash can't leave the date done but the next one not queued.
        return try database.write { database in
            let replaced = try Self.replace(selection, with: samples, rules: rules, in: database)
            let endChanged = replaced.map { Self.endState($0.old, before: range.end) != Self.endState($0.new, before: range.end) } ?? false
            var pending = try Set(database.meta(.pendingRemoteDays) ?? [])
            pending.remove(deviceDay)
            let next = DeviceDay(deviceID: deviceDay.deviceID, day: deviceDay.day.adding(days: 1))
            if endChanged, next.day <= today {
                pending.insert(next)
            }
            try database.setMeta(.pendingRemoteDays, pending.sorted())
            return endChanged
        }
    }

    /// Deletes the stored events before `date`, except the last one of each
    /// device and source (and label, for automations), which still tells
    /// what was on.
    public func deleteDeviceEvents(before date: Date) throws {
        try database.write { database in
            try database.execute(
                sql: """
                DELETE FROM device_events WHERE time < ? AND name NOT IN (
                    SELECT name FROM device_events AS kept WHERE kept.time = (
                        SELECT MAX(time) FROM device_events AS other
                        WHERE other.device = kept.device AND other.source = kept.source
                            AND (other.source != 'intent' OR other.label = kept.label) AND other.time < ?
                    )
                )
                """,
                arguments: [Self.seconds(date), Self.seconds(date)]
            )
        }
    }

    // MARK: Helpers

    /// The device-date from its 00:00 to the next date's, so adjacent
    /// dates share their boundary across a time-zone or DST change.
    private static func range(of deviceDay: DeviceDay, zone: TimeZone, in database: Database) throws -> DateInterval {
        let start = try Self.start(of: deviceDay.day, device: deviceDay.deviceID, zone: zone, in: database)
        let end = try Self.start(of: deviceDay.day.adding(days: 1), device: deviceDay.deviceID, zone: zone, in: database)
        return DateInterval(start: start, end: max(start, end))
    }

    /// 00:00 of `day` on the device: at the UTC offset of its last event
    /// before the date, which is the offset in effect then, else of its
    /// first event from the date on, else of `zone`.
    private static func start(of day: TrackingDay, device: String, zone: TimeZone, in database: Database) throws -> Date {
        let neighbor = try events(
            sql: "WHERE device = ? AND day < ? ORDER BY time DESC LIMIT 1",
            [device, day.description],
            in: database
        ).first ?? events(
            sql: "WHERE device = ? AND day >= ? ORDER BY time ASC LIMIT 1",
            [device, day.description],
            in: database
        ).first
        let midnight = LocalTimestamp(year: day.year, month: day.month, day: day.day, hour: 0, minute: 0, second: 0)
        return midnight.date(utcOffset: neighbor?.utcOffset ?? zone.secondsFromGMT())
    }

    /// The device's last event of each source before the date (or first
    /// after it), and of each label for automations, which can overlap.
    private static func neighbors(of deviceDay: DeviceDay, before: Bool, in database: Database) throws -> [DeviceEvent] {
        let comparison = before ? "<" : ">"
        let order = before ? "DESC" : "ASC"
        let day = deviceDay.day.description
        var result: [DeviceEvent] = []
        for source in DeviceEvent.Source.allCases {
            let labels: [String?] = source == .intent
                ? try String.fetchAll(
                    database,
                    sql: "SELECT DISTINCT label FROM device_events WHERE device = ? AND source = ? AND day \(comparison) ?",
                    arguments: [deviceDay.deviceID, source.rawValue, day]
                ).map(Optional.some)
                : [nil]
            for label in labels {
                let labelCondition = label == nil ? "" : " AND label = ?"
                let arguments: [any DatabaseValueConvertible] = [deviceDay.deviceID, source.rawValue, day] + (label.map { [$0] } ?? [])
                result += try events(
                    sql: "WHERE device = ? AND source = ? AND day \(comparison) ?\(labelCondition) ORDER BY time \(order) LIMIT 1",
                    StatementArguments(arguments),
                    in: database
                )
            }
        }
        return result.sorted { ($0.time, $0.sequence) < ($1.time, $1.sequence) }
    }

    private static func events(sql condition: String, _ arguments: StatementArguments, in database: Database) throws -> [DeviceEvent] {
        try String.fetchAll(database, sql: "SELECT json FROM device_events \(condition)", arguments: arguments).compactMap { json in
            try? JSONDecoder().decode(DeviceEvent.self, from: Data(json.utf8))
        }
    }

    /// What is on in the last minute before `end`: the series and states of the Samples there.
    private static func endState(_ samples: [Sample], before end: Date) -> Set<String> {
        Set(samples.filter { $0.time >= end - 60 && $0.time < end }.map { "\($0.series)\u{1F}\($0.state.rawValue)" })
    }
}

extension DeviceEvent {
    /// The device's local date of the event, by its UTC offset.
    var localDay: TrackingDay? {
        utcOffset.flatMap { TrackingDay(ActivityTimestamp.day(time, utcOffset: $0)) }
    }
}
