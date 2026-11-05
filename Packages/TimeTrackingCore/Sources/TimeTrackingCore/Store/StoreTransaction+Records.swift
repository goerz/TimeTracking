// Settings, devices, and tombstone retention
// (data_and_sync.md §1.6 to §1.8, §3.2).

import Foundation
import GRDB

extension StoreTransaction {
    /// Writes a synced setting.
    public func set<T>(_ key: SyncedSettingKey<T>, _ value: T) throws {
        let data = try JSONEncoder.sorted.encode(value)
        try setSettingJSON(key.name, String(decoding: data, as: UTF8.self))
    }

    /// The value of a synced setting, or its default.
    public func value<T>(_ key: SyncedSettingKey<T>) throws -> T {
        try StoreQueries.settingValue(key, in: database)
    }

    func setSettingJSON(_ key: String, _ json: String) throws {
        try database.execute(
            sql: """
            INSERT INTO setting (key, value, modified_at, deleted_at) VALUES (?, ?, ?, NULL)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, modified_at = excluded.modified_at, deleted_at = NULL
            """,
            arguments: [key, json, Time.millis(modifiedAt)]
        )
        markChanged(SyncRecordRef(.setting, key))
    }

    /// Creates or updates this device's record; `lastSeenAt` moves at most hourly.
    @discardableResult
    public func registerDevice(name: String, platform: DevicePlatform) throws -> Device {
        let existing = try Row.fetchOne(database, sql: "SELECT * FROM device WHERE id = ?", arguments: [deviceID.rawValue])
            .map(Device.init(row:))
        var device = existing ?? Device(
            id: deviceID,
            name: name,
            platform: platform,
            lastSeenAt: now,
            createdAt: now,
            modifiedAt: modifiedAt
        )
        let stale = existing.map { now.timeIntervalSince($0.lastSeenAt) >= 3600 } ?? true
        guard existing == nil || stale || device.name != name || device.platform != platform else {
            return device
        }
        device.name = name
        device.platform = platform
        device.lastSeenAt = now
        try write(device)
        return device
    }

    /// Stores the widget push token on this device's record.
    public func setWidgetPushToken(_ token: String?) throws {
        guard var device = try Row.fetchOne(database, sql: "SELECT * FROM device WHERE id = ?", arguments: [deviceID.rawValue])
            .map(Device.init(row:))
        else {
            throw StoreError.unknownID
        }
        guard device.widgetPushToken != token else {
            return
        }
        device.widgetPushToken = token
        try write(device)
    }

    func write(_ device: Device) throws {
        var device = device
        device.modifiedAt = modifiedAt
        try device.save(database)
        markChanged(SyncRecordRef(.device, device.id.rawValue))
    }

    /// Daily maintenance: hard-deletes tombstones older than 180 days and
    /// queues their deletion. Returns the number of records removed.
    @discardableResult
    public func purgeExpiredTombstones() throws -> Int {
        let cutoff = Time.seconds(now) - Int64(Self.retention)
        var count = 0
        let types: [SyncRecordType] = [.client, .area, .project, .timeEntry, .setting, .healthPeriod]
        for type in types {
            guard let (table, key) = Self.table(of: type) else {
                continue
            }
            let names = try String.fetchAll(
                database,
                sql: "SELECT \(key) FROM \(table) WHERE deleted_at IS NOT NULL AND deleted_at < ?",
                arguments: [cutoff]
            )
            for name in names {
                try hardDelete(SyncRecordRef(type, name), queue: true)
                count += 1
            }
        }
        return count
    }

    /// Removes a row and remembers its id, for local purges and remote deletions.
    func hardDelete(_ ref: SyncRecordRef, queue: Bool) throws {
        guard let (table, key) = Self.table(of: ref.type) else {
            return
        }
        try database.execute(sql: "DELETE FROM \(table) WHERE \(key) = ?", arguments: [ref.name])
        try database.execute(
            sql: "INSERT OR REPLACE INTO purged_record (record_id, record_type, purged_at) VALUES (?, ?, ?)",
            arguments: [ref.name, ref.type.rawValue, Time.seconds(now)]
        )
        markChanged(ref, queue: queue)
    }

    static func table(of type: SyncRecordType) -> (table: String, key: String)? {
        switch type {
        case .client: ("client", "id")
        case .area: ("area", "id")
        case .project: ("project", "id")
        case .timeEntry: ("time_entry", "id")
        case .setting: ("setting", "key")
        case .device: ("device", "id")
        case .healthPeriod: ("health_period", "id")
        case .liveState: nil
        }
    }
}

extension JSONEncoder {
    /// Sorted keys, so equal values encode identically.
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
