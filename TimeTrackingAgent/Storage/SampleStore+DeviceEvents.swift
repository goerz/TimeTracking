// SampleStore+DeviceEvents: the fetched DeviceEvents, kept with the
// samples so a device-day can be merged again when late events arrive
// (spec_activity_tracking.md §6.2; kept 90 days, never leaves the Mac).

import Foundation
import GRDB
import TimeTrackingCore

/// A device's local day, the unit the merge recomputes.
nonisolated struct DeviceDay: Hashable, Comparable, Sendable {
    var device: String
    /// `YYYY-MM-DD`.
    var day: String
    /// Seconds east of UTC of the day's events.
    var utcOffset: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.device, lhs.day, lhs.utcOffset) < (rhs.device, rhs.day, rhs.utcOffset)
    }
}

extension SampleStore {
    /// The name a device's blocks carry: the name the iOS flush stamped,
    /// else a short form of its id.
    static func deviceName(of event: DeviceEvent) -> String {
        let name = event.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "device-\(event.deviceID.prefix(8))" : name
    }

    /// Stores `events` (replacing any of the same record name) and returns
    /// the device-days they touch. `fallbackOffset` serves events without an offset.
    func insertDeviceEvents(_ events: [DeviceEvent], fallbackOffset: (Date) -> Int) throws -> Set<DeviceDay> {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var touched: Set<DeviceDay> = []
        try database.write { database in
            for event in events {
                let offset = event.utcOffset ?? fallbackOffset(event.time)
                let day = DeviceDay(
                    device: Self.deviceName(of: event),
                    day: ActivityTimestamp.day(event.time, utcOffset: offset),
                    utcOffset: offset
                )
                let line = try String(decoding: encoder.encode(event), as: UTF8.self)
                try database.execute(
                    sql: "INSERT OR REPLACE INTO device_event (name, device, day, time, utc_offset, line) VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: [event.recordName, day.device, day.day, event.time.timeIntervalSince1970, offset, line]
                )
                touched.insert(day)
            }
        }
        return touched
    }

    /// The device-days with stored events on `day`.
    func deviceDays(on day: String) throws -> [DeviceDay] {
        try database.read { database in
            try GRDB.Row.fetchAll(
                database,
                sql: "SELECT DISTINCT device, utc_offset FROM device_event WHERE day = ? ORDER BY device, utc_offset",
                arguments: [day]
            )
        }.map { row in DeviceDay(device: row["device"], day: day, utcOffset: row["utc_offset"]) }
    }

    /// The stored events of `device` on `day`, oldest first.
    func deviceEvents(device: String, day: String) throws -> [DeviceEvent] {
        let decoder = JSONDecoder()
        return try database.read { database in
            try String.fetchAll(
                database,
                sql: "SELECT line FROM device_event WHERE device = ? AND day = ? ORDER BY time, name",
                arguments: [device, day]
            )
        }.compactMap { try? decoder.decode(DeviceEvent.self, from: Data($0.utf8)) }
    }

    /// The number of stored events (tests).
    func deviceEventCount() throws -> Int {
        try database.read { database in try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM device_event") ?? 0 }
    }

    /// Deletes the events older than `date`.
    func purgeDeviceEvents(before date: Date) throws {
        try database.write { database in
            try database.execute(sql: "DELETE FROM device_event WHERE time < ?", arguments: [date.timeIntervalSince1970])
        }
    }
}
