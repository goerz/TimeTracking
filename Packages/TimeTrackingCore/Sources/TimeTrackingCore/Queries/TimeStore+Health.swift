// Reading and importing sleep and workout periods (data_and_sync.md §1.9, §7).

public import Foundation
import GRDB

extension TimeStore {
    /// Live periods intersecting `interval`, by start.
    public func healthPeriods(in interval: DateInterval) throws -> [HealthPeriod] {
        try read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT * FROM health_period WHERE deleted_at IS NULL AND start < ? AND "end" > ?
                ORDER BY start, id
                """,
                arguments: [Time.seconds(interval.end), Time.seconds(interval.start)]
            ).map(HealthPeriod.init(row:))
        }
    }

    /// The kinds with at least one live period.
    public func healthKinds() throws -> Set<HealthPeriod.Kind> {
        try read { database in
            let names = try String.fetchAll(database, sql: "SELECT DISTINCT kind FROM health_period WHERE deleted_at IS NULL")
            return Set(names.compactMap(HealthPeriod.Kind.init(rawValue:)))
        }
    }

    /// See `StoreTransaction.replaceHealthPeriods(_:from:with:)`.
    @discardableResult
    public func replaceHealthPeriods(_ kind: HealthPeriod.Kind, from start: Date, with intervals: [DateInterval]) throws -> Int {
        try write { try $0.replaceHealthPeriods(kind, from: start, with: intervals) }
    }

    /// See `StoreTransaction.replaceHealthPeriods(_:from:with:)`.
    @discardableResult
    public func replaceHealthPeriods(_ kind: HealthPeriod.Kind, from start: Date, with drafts: [HealthPeriodDraft]) throws -> Int {
        try write { try $0.replaceHealthPeriods(kind, from: start, with: drafts) }
    }

    /// Live periods whose start lies in `interval` (all when `nil`), of
    /// `kind` when given, by start.
    public func healthPeriods(starting interval: DateInterval?, kind: HealthPeriod.Kind?) throws -> [HealthPeriod] {
        let lower = interval.map { Time.seconds($0.start) } ?? Int64.min
        let upper = interval.map { Time.seconds($0.end) } ?? Int64.max
        return try read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT * FROM health_period WHERE deleted_at IS NULL AND start >= ? AND start < ? AND (? IS NULL OR kind = ?)
                ORDER BY start, id
                """,
                arguments: [lower, upper, kind?.rawValue, kind?.rawValue]
            ).map(HealthPeriod.init(row:))
        }
    }
}
