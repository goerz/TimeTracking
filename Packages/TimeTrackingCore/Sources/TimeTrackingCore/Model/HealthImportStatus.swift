// HealthImportStatus: the iPhone's last import from Apple Health, a synced
// setting the Calendar settings report on (spec_data_and_sync.md §1.9,
// spec_calendar.md §6).

public import Foundation

/// Which device last imported which kinds, and when.
public struct HealthImportStatus: Codable, Sendable, Equatable {
    /// What the Calendar settings say about the kinds they show.
    public enum Summary: Equatable, Sendable {
        /// No device has imported yet.
        case never
        /// The last import did not read these shown kinds (turned on since).
        case waiting(device: String, kinds: [HealthPeriod.Kind])
        /// The last import read these shown kinds, but the store holds none.
        case empty(device: String, date: Date, kinds: [HealthPeriod.Kind])
        /// Every shown kind was read and has periods.
        case imported(device: String, date: Date)
    }

    /// A rewrite within this many seconds of the last one is skipped unless
    /// the device or kinds differ, so frequent wakes don't each sync.
    public static let refreshInterval: TimeInterval = 3600

    /// The importing device's name.
    public var device: String
    /// Whole seconds.
    public var date: Date
    /// The kinds this import read, in `HealthPeriod.Kind.allCases` order.
    public var kinds: [HealthPeriod.Kind]

    public init(device: String, date: Date, kinds: some Sequence<HealthPeriod.Kind>) {
        self.device = device
        self.date = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        let set = Set(kinds)
        self.kinds = HealthPeriod.Kind.allCases.filter(set.contains)
    }

    /// Whether this status should overwrite `previous`.
    public func replaces(_ previous: Self?) -> Bool {
        guard let previous else {
            return true
        }
        return previous.device != device || previous.kinds != kinds
            || date.timeIntervalSince(previous.date) >= Self.refreshInterval
    }

    /// The summary for the `shown` kinds, given the kinds the store holds
    /// periods of; nil when nothing is shown.
    public static func summary(_ status: Self?, shown: Set<HealthPeriod.Kind>, found: Set<HealthPeriod.Kind>) -> Summary? {
        let shownKinds = HealthPeriod.Kind.allCases.filter(shown.contains)
        guard !shownKinds.isEmpty else {
            return nil
        }
        guard let status else {
            return .never
        }
        let unread = shownKinds.filter { !status.kinds.contains($0) }
        if !unread.isEmpty {
            return .waiting(device: status.device, kinds: unread)
        }
        let missing = shownKinds.filter { !found.contains($0) }
        if !missing.isEmpty {
            return .empty(device: status.device, date: status.date, kinds: missing)
        }
        return .imported(device: status.device, date: status.date)
    }
}

extension SyncedSettingKey<HealthImportStatus?> {
    /// The iPhone's last import (§1.9); the Calendar settings show it.
    public static var calendarHealthImport: Self {
        Self("calendar.healthImport", default: nil)
    }
}
