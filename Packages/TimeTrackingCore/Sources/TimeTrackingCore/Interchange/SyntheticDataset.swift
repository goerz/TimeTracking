// SyntheticDataset: deterministic synthetic data for fixtures, tests, and
// performance checks (data_and_sync.md §9.1, architecture.md §3.4).

public import Foundation

/// A deterministic generator of clients, areas, projects, and entries.
///
/// Workdays have 6 to 14 entries of 3 minutes to 3 hours (log-normal), 10
/// percent of them evening work, 2 percent running past midnight, 3 percent
/// tombstones (in `write(to:)`), 20 to 60 task phrases per
/// project, 15 percent archived projects, default-rule colors, and an
/// optional running entry. The same parameters always give the same data.
public struct SyntheticDataset: Sendable {
    public var clients: Int
    /// All areas, the general ones included (at least one per client).
    public var areas: Int
    public var projects: Int
    /// The days with entries; the last one ends before `now`.
    public var days: ClosedRange<TrackingDay>
    /// The local time the data is generated for (the test clock).
    public var now: DateComponents
    public var timeZone: String
    public var seed: UInt64
    /// Share of entries overlapping the previous one.
    public var overlapShare: Double
    public var tombstoneShare: Double
    /// Minutes the running entry has run at `now`; `nil` for none.
    public var runningMinutes: Int?

    public init(
        clients: Int,
        areas: Int,
        projects: Int,
        days: ClosedRange<TrackingDay>,
        now: DateComponents = DateComponents(year: 2024, month: 3, day: 14, hour: 10),
        timeZone: String = "America/New_York",
        seed: UInt64 = 1,
        overlapShare: Double = 0,
        tombstoneShare: Double = 0.03,
        runningMinutes: Int? = nil
    ) {
        self.clients = clients
        self.areas = areas
        self.projects = projects
        self.days = days
        self.now = now
        self.timeZone = timeZone
        self.seed = seed
        self.overlapShare = overlapShare
        self.tombstoneShare = tombstoneShare
        self.runningMinutes = runningMinutes
    }

    /// 3 clients, 6 areas, 15 projects, one month, about 250 entries.
    public static var small: Self {
        Self(clients: 3, areas: 6, projects: 15, days: ending(days: 30))
    }

    /// 8 clients, 25 areas, 90 projects, three years, about 7,000 entries.
    public static var medium: Self {
        Self(clients: 8, areas: 25, projects: 90, days: ending(days: 3 * 365))
    }

    /// 10 clients, 40 areas, 120 projects, ten years, about 24,000 entries.
    ///
    /// §9.1 also says 300,000 entries, which the day rules above cannot give
    /// (one person's decade is about 24,000); the day rules win, and the
    /// §7.5 import target applies as a rate (StorePerformanceTests).
    public static func large(seed: UInt64 = 1) -> Self {
        Self(clients: 10, areas: 40, projects: 120, days: ending(days: 10 * 365), seed: seed)
    }

    /// The store fixtures of architecture.md §3.4 by name: `empty`,
    /// `small` (3 clients, 5 areas, 12 projects, two weeks), `large` (two
    /// years), `running` (`small` with an entry running for 25 minutes).
    public static func fixture(named name: String) -> Self? {
        switch name {
        case "empty":
            Self(clients: 0, areas: 0, projects: 0, days: ending(days: 0), tombstoneShare: 0)
        case "small":
            Self(clients: 3, areas: 5, projects: 12, days: ending(days: 14), tombstoneShare: 0)
        case "large":
            Self(clients: 8, areas: 25, projects: 90, days: ending(days: 2 * 365), tombstoneShare: 0)
        case "running":
            Self(clients: 3, areas: 5, projects: 12, days: ending(days: 14), tombstoneShare: 0, runningMinutes: 25)
        default:
            nil
        }
    }

    /// The fixture names `fixture(named:)` knows.
    public static let fixtureNames = ["empty", "small", "large", "running"]

    /// `days` whole days ending the day before 2024-03-14 (an empty range
    /// starting that day for 0).
    static func ending(days: Int) -> ClosedRange<TrackingDay> {
        let today = TrackingDay(year: 2024, month: 3, day: 14)
        return today.adding(days: -max(days, 1)) ... today.adding(days: -1)
    }

    /// The instant `now` in `timeZone`.
    public var nowDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: now) ?? .distantPast
    }

    var zone: TimeZone {
        TimeZone(identifier: timeZone) ?? .gmt
    }

    /// The device that created the entries.
    public var deviceID: DeviceID {
        DeviceID(UUID.version5(namespace: Self.namespace, name: "device:\(seed)"))
    }

    static let namespace = UUID(uuid: (0x6B, 0x8E, 0x2A, 0x51, 0x0C, 0x3D, 0x4F, 0x7A, 0x9B, 0x10, 0x5E, 0x22, 0x71, 0x4C, 0x88, 0x03))

    /// The export-format document (spec §5.1),
    /// with a fixed `storeID` and `generatedAt`.
    public func exportDocument() async throws -> Data {
        let store = try await populatedStore(withTombstones: false)
        let data = try await store.exportDocument()
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }
        object["storeID"] = UUID.version5(namespace: Self.namespace, name: "store:\(seed)").uuidString.lowercased()
        object["generatedAt"] = TimeStore.rfc3339(nowDate)
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Fills `store` (normally empty) with the dataset, tombstones included.
    public func write(to store: TimeStore) async throws {
        _ = try await store.importDocument(rawDocument(), options: ImportOptions(includeSettings: true))
        let deleted = tombstoneIDs()
        if !deleted.isEmpty {
            try await store.delete(deleted)
        }
    }

    /// An in-memory store at `now` holding the dataset.
    public func populatedStore(withTombstones: Bool = true) async throws -> TimeStore {
        let store = try await TimeStore.inMemory(clock: ManualClock(nowDate), deviceID: deviceID, timeZone: zone)
        if withTombstones {
            try await write(to: store)
        } else {
            _ = try await store.importDocument(rawDocument(), options: ImportOptions(includeSettings: true))
        }
        return store
    }
}
