// MetaKey: the typed keys of the `meta` table of samples.sqlite
// (activity_tracking.md §4.1).

public import Foundation
public import GRDB

/// A typed key of `meta`; values are stored as JSON.
public struct MetaKey<Value: Codable & Sendable>: Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }
}

extension MetaKey {
    public static var cloudKitToken: MetaKey<Data> {
        MetaKey<Data>("cloudKitToken")
    }

    /// The device-dates with new DeviceEvents not yet converted, kept with the token.
    public static var pendingRemoteDays: MetaKey<[DeviceDay]> {
        MetaKey<[DeviceDay]>("pendingRemoteDays")
    }

    /// How far macOS app usage was read (§2.4).
    public static var appUsageReadUntil: MetaKey<Date> {
        MetaKey<Date>("appUsageReadUntil")
    }

    /// The earliest time gaps are filled from app usage (§2.4).
    public static var fillAfter: MetaKey<Date> {
        MetaKey<Date>("fillAfter")
    }

    /// The date of the agent's first start; no date before it is formed.
    public static var firstStartDay: MetaKey<TrackingDay> {
        MetaKey<TrackingDay>("firstStartDay")
    }

    /// Dates before it are frozen (§4.1).
    public static var cutoffDay: MetaKey<TrackingDay> {
        MetaKey<TrackingDay>("cutoffDay")
    }

    public static var deletedRanges: MetaKey<[DeletedRange]> {
        MetaKey<[DeletedRange]>("deletedRanges")
    }

    public static var changedDays: MetaKey<Set<TrackingDay>> {
        MetaKey<Set<TrackingDay>>("changedDays")
    }

    public static var dayEnds: MetaKey<[TrackingDay: DateEnd]> {
        MetaKey<[TrackingDay: DateEnd]>("dayEnds")
    }

    /// The UTC offset of each date's 00:00, fixed when a Sample first marks the date.
    public static var dayOffsets: MetaKey<[TrackingDay: Int]> {
        MetaKey<[TrackingDay: Int]>("dayOffsets")
    }

    /// The latest name of each iOS device by its `deviceID`.
    public static var deviceNames: MetaKey<[String: String]> {
        MetaKey<[String: String]>("deviceNames")
    }

    /// Whether this Mac wrote the date files at its last check (§4.1).
    public static var recording: MetaKey<Bool> {
        MetaKey<Bool>("recording")
    }

    /// What was read of `CloudTabs.db` (§6.1).
    public static var cloudTabs: MetaKey<CloudTabMemory> {
        MetaKey<CloudTabMemory>("cloudTabs")
    }

    /// The text of the last `settings.toml` read, in force while the file
    /// can't be read.
    public static var settingsText: MetaKey<String> {
        MetaKey<String>("settingsText")
    }

    /// Dates whose file iCloud Drive holds only as a placeholder.
    public static var placeholderDays: MetaKey<Set<TrackingDay>> {
        MetaKey<Set<TrackingDay>>("placeholderDays")
    }
}

extension Database {
    /// The value of `key`, `nil` when unset. A stored value that doesn't
    /// decode throws: read as absent, a lost cutoff date or deleted range
    /// would let a rebuild empty frozen files or bring deleted time back.
    public func meta<Value>(_ key: MetaKey<Value>) throws -> Value? {
        guard let text = try String.fetchOne(self, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key.name]) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(Value.self, from: Data(text.utf8))
        } catch {
            throw ActivityError.invalidMeta(key.name)
        }
    }

    /// Sets `key` to `value`; `nil` removes it.
    public func setMeta<Value>(_ key: MetaKey<Value>, _ value: Value?) throws {
        guard let value else {
            try execute(sql: "DELETE FROM meta WHERE key = ?", arguments: [key.name])
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let text = try String(decoding: encoder.encode(value), as: UTF8.self)
        try execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", arguments: [key.name, text])
    }
}
