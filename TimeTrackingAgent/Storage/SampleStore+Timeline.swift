// SampleStore+Timeline: the inputs of the user's timeline besides the
// Mac's samples: samples reconstructed from the Knowledge store, synced
// Safari visits, and deleted time (spec_activity_tracking.md §2.8, §4.1,
// §7.3; kept 90 days, never leaves the Mac).

import Foundation
import GRDB
import TimeTrackingCore

/// The kinds of stored samples besides the live ones.
nonisolated enum ExtraSampleKind: String, Sendable {
    /// Reconstructed from the Knowledge store for time the agent was down.
    case knowledge
    /// A synced Safari visit, with its attributed device.
    case remote
}

/// A stored reconstructed or synced sample.
nonisolated struct ExtraSampleRow: Sendable {
    var id: Int64
    var sample: Sample
    var device: String
    var utcOffset: Int
}

extension SampleStore {
    /// Replaces the samples of `kind` in `[from, to)` by `samples`.
    func replaceExtraSamples(
        _ kind: ExtraSampleKind,
        from: Date,
        to: Date,
        with samples: [(sample: Sample, device: String)],
        utcOffset: (Date) -> Int
    ) throws {
        try database.write { database in
            try database.execute(
                sql: "DELETE FROM extra_sample WHERE kind = ? AND time >= ? AND time < ?",
                arguments: [kind.rawValue, from.timeIntervalSince1970, to.timeIntervalSince1970]
            )
            for (sample, device) in samples {
                let offset = utcOffset(sample.time)
                try database.execute(
                    sql: "INSERT INTO extra_sample (kind, device, time, utc_offset, line) VALUES (?, ?, ?, ?, ?)",
                    arguments: [
                        kind.rawValue,
                        device,
                        sample.time.timeIntervalSince1970,
                        offset,
                        SampleCodec.line(sample, utcOffset: offset),
                    ]
                )
            }
        }
    }

    /// The samples of `kind` in `[from, to)`, oldest first.
    func extraSamples(_ kind: ExtraSampleKind, from: Date, to: Date) throws -> [ExtraSampleRow] {
        try database.read { database in
            try GRDB.Row.fetchAll(
                database,
                sql: "SELECT id, device, utc_offset, line FROM extra_sample WHERE kind = ? AND time >= ? AND time < ? ORDER BY time, id",
                arguments: [kind.rawValue, from.timeIntervalSince1970, to.timeIntervalSince1970]
            ).compactMap { row in
                let offset: Int = row["utc_offset"]
                let line: String = row["line"]
                return SampleCodec.sample(line, utcOffset: offset).map { sample in
                    ExtraSampleRow(id: row["id"], sample: sample, device: row["device"], utcOffset: offset)
                }
            }
        }
    }

    /// Replaces the line of extra sample `id`.
    func updateExtraSample(_ id: Int64, with sample: Sample, utcOffset: Int) throws {
        try database.write { database in
            try database.execute(
                sql: "UPDATE extra_sample SET line = ? WHERE id = ?",
                arguments: [SampleCodec.line(sample, utcOffset: utcOffset), id]
            )
        }
    }

    /// Deletes what the timeline is formed from in `[from, to)`: samples,
    /// reconstructed and synced samples, and device events; and records the
    /// time as deleted, so late events cannot form a block there again.
    func deleteTimeline(from: Date, to: Date) throws {
        try delete(from: from, to: to)
        try database.write { database in
            let arguments: StatementArguments = [from.timeIntervalSince1970, to.timeIntervalSince1970]
            try database.execute(sql: "DELETE FROM extra_sample WHERE time >= ? AND time < ?", arguments: arguments)
            try database.execute(sql: "DELETE FROM device_event WHERE time >= ? AND time < ?", arguments: arguments)
            try database.execute(sql: "INSERT INTO suppressed (start, end) VALUES (?, ?)", arguments: arguments)
        }
    }

    /// The deleted time overlapping `[from, to)`.
    func suppressed(from: Date, to: Date) throws -> [DateInterval] {
        try database.read { database in
            try GRDB.Row.fetchAll(
                database,
                sql: "SELECT start, end FROM suppressed WHERE end > ? AND start < ? ORDER BY start",
                arguments: [from.timeIntervalSince1970, to.timeIntervalSince1970]
            ).map { row in
                let start = Date(timeIntervalSince1970: row["start"])
                return DateInterval(start: start, end: max(start, Date(timeIntervalSince1970: row["end"])))
            }
        }
    }
}
