// Schema+Chains: the merge of schema version 4, which turns the midnight
// chains of earlier versions into whole entries (spec_data_and_sync.md §2.1).

import Foundation
import GRDB

/// A live piece of a chain.
struct ChainPiece {
    var id: String
    var root: String
    var start: Int64
    var end: Int64?
}

/// Contiguous pieces of one chain: the earliest, `head`, takes `end`, and
/// the `later` ones go.
struct ChainRun {
    var head: String
    var end: Int64?
    var later: [String] = []

    /// The runs of two or more pieces, by root and start. A piece joins the
    /// one before it when it starts where that one ends, so a chain the user
    /// broke by editing stays separate entries.
    static func runs(of pieces: [ChainPiece]) -> [Self] {
        var runs: [Self] = []
        for (_, chain) in Dictionary(grouping: pieces, by: \.root).sorted(by: { $0.key < $1.key }) {
            var run: Self?
            for piece in chain.sorted(by: { ($0.start, $0.id) < ($1.start, $1.id) }) {
                if var current = run, current.end == piece.start {
                    current.later.append(piece.id)
                    current.end = piece.end
                    run = current
                } else {
                    runs += run.map { [$0] } ?? []
                    run = Self(head: piece.id, end: piece.end)
                }
            }
            runs += run.map { [$0] } ?? []
        }
        return runs.filter { !$0.later.isEmpty }
    }
}

extension Schema {
    /// Merges each chain of live pieces. Every device runs this on what it
    /// holds, so nothing here depends on the clock or the device: a run's
    /// `modified_at` is one past its pieces' latest. Two devices holding the
    /// same pieces produce equal rows, and a device that missed an edit
    /// produces an earlier stamp and loses to the one that didn't. Merging
    /// again changes nothing.
    static func mergeChains(in database: Database) throws {
        let rows = try Row.fetchAll(
            database,
            sql: """
            SELECT e.id, COALESCE(e.split_root_id, e.id) AS root, e.start, e."end", e.modified_at
            FROM time_entry e
            WHERE e.deleted_at IS NULL
              AND (e.split_root_id IS NOT NULL OR EXISTS (SELECT 1 FROM time_entry p WHERE p.split_root_id = e.id))
            """
        )
        var stamps: [String: Int64] = [:]
        for row in rows {
            stamps[row["id"]] = row["modified_at"]
        }
        let pieces = rows.map { ChainPiece(id: $0["id"], root: $0["root"], start: $0["start"], end: $0["end"]) }
        var heads: [String: String] = [:]
        for run in ChainRun.runs(of: pieces) {
            let stamp = ([run.head] + run.later).compactMap { stamps[$0] }.reduce(0, max) + 1
            try database.execute(
                sql: "UPDATE time_entry SET \"end\" = ?, modified_at = ? WHERE id = ?",
                arguments: [run.end, stamp, run.head]
            )
            for id in run.later {
                try database.execute(
                    sql: "UPDATE time_entry SET deleted_at = ?, modified_at = ? WHERE id = ?",
                    arguments: [stamp / 1000, stamp, id]
                )
                heads[id] = run.head
            }
            for id in [run.head] + run.later {
                try queue(.timeEntry, id, at: stamp, in: database)
            }
        }
        try namesHeads(heads, in: database)
    }

    /// A `live_state` row naming a merged piece names its entry instead.
    private static func namesHeads(_ heads: [String: String], in database: Database) throws {
        guard let row = try Row.fetchOne(database, sql: "SELECT running, changed_at FROM live_state WHERE id = 1"),
              var running = LiveState.running(json: row["running"]),
              let head = heads[running.entryID.rawValue],
              let id = EntryID(head),
              let start = try Int64.fetchOne(database, sql: "SELECT start FROM time_entry WHERE id = ?", arguments: [head])
        else {
            return
        }
        running.entryID = id
        running.start = Time.date(start)
        let stamp = ((row["changed_at"] as Int64?) ?? 0) + 1
        try database.execute(
            sql: "UPDATE live_state SET running = ?, changed_at = ? WHERE id = 1",
            arguments: [LiveState.runningJSON(running), stamp]
        )
        try queue(.liveState, StoreTransaction.liveStateRef.name, at: stamp, in: database)
    }

    private static func queue(_ type: SyncRecordType, _ id: String, at stamp: Int64, in database: Database) throws {
        try database.execute(
            sql: "INSERT INTO outbox (record_type, record_id, queued_at) VALUES (?, ?, ?)",
            arguments: [type.rawValue, id, stamp / 1000]
        )
    }
}
