// HealthPeriod: a stretch of sleep or a workout from Apple Health, imported
// on the iPhone and synced (spec_data_and_sync.md §1.9).

public import Foundation

/// A period of sleep or a workout. Synced; written only by the import.
public struct HealthPeriod: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case sleep
        case workout
    }

    public var id: HealthPeriodID
    public var kind: Kind
    /// Whole seconds.
    public var start: Date
    public var end: Date
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(
        id: HealthPeriodID = HealthPeriodID(),
        kind: Kind,
        start: Date,
        end: Date,
        createdAt: Date,
        modifiedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }

    public var interval: DateInterval {
        DateInterval(start: start, end: max(start, end))
    }

    public var isDeleted: Bool {
        deletedAt != nil
    }
}

extension HealthPeriod.Kind {
    /// The project a report counts this kind as, inside the area the
    /// settings choose; no project record has this id.
    public var reportProjectID: ProjectID {
        switch self {
        case .sleep: ProjectID(UUID(uuid: (0x5E, 0xE9, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1)))
        case .workout: ProjectID(UUID(uuid: (0x5E, 0xE9, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 2)))
        }
    }

    /// That project's name: "Sleep", "Workouts".
    public var reportName: String {
        switch self {
        case .sleep: "Sleep"
        case .workout: "Workouts"
        }
    }
}

extension HealthPeriod {
    /// Sleep samples less than this apart belong to one period.
    public static let sleepJoin: TimeInterval = 30 * 60

    /// `intervals` merged where they overlap or lie at most `gap` apart, by start.
    public static func merge(_ intervals: [DateInterval], joining gap: TimeInterval = 0) -> [DateInterval] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start.timeIntervalSince(last.end) <= gap {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// The sleep periods: the asleep samples (any stage) joined across
    /// short wakes, plus each in-bed period without an asleep sample (a
    /// night recorded by the iPhone's sleep schedule alone).
    public static func sleep(asleep: [DateInterval], inBed: [DateInterval]) -> [DateInterval] {
        let nights = merge(asleep, joining: sleepJoin)
        let bedOnly = merge(inBed, joining: sleepJoin).filter { bed in
            !nights.contains { $0.intersects(bed) }
        }
        return merge(nights + bedOnly)
    }
}
