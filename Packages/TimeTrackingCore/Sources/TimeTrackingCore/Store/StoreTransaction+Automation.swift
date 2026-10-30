// The checked entry writes of the scripting surfaces: the refusals of the
// tool's start, stop, continue, entry create, and entry edit
// (spec_automation.md §3.5, §3.6).

public import Foundation
import GRDB

extension StoreTransaction {
    /// How far `start --at` may backdate.
    public static let maximumBackdate: TimeInterval = 24 * 3600

    /// Starts an entry at `at` (default now), stopping the running one
    /// there. Refuses a time in the future, before the running entry's
    /// start, more than 24 hours back, or overlapping a stopped entry
    /// (unless `force`), and an archived project.
    public func checkedStart(projectID: ProjectID?, task: String, at: Date?, force: Bool) throws -> StartOutcome {
        let at = at.map { Time.whole($0) } ?? now
        guard at <= now else {
            throw AutomationError.refused("The start \(Self.clockTime(at, timeZone)) lies in the future.")
        }
        guard now.timeIntervalSince(at) <= Self.maximumBackdate else {
            throw AutomationError.refused("A start may lie at most 24 hours back.")
        }
        let running = try runningEntries()
        if let first = running.first, at < first.start {
            throw AutomationError.refused("The start lies before the running entry's start at \(Self.clockTime(first.start, timeZone)).")
        }
        if let projectID, let project = try project(projectID), project.isArchived {
            throw AutomationError.refused("Project \"\(project.name)\" is archived; unarchive it first.")
        }
        if !force {
            try refuseOverlap(start: at, end: now, excluding: [])
        }
        let entry = try start(projectID: projectID, task: task, at: at)
        let stopped = try running.compactMap { try self.entry($0.id) }
        return StartOutcome(entry: entry, stopped: stopped.last)
    }

    /// Stops the running entry at `at` (default now); refuses when nothing
    /// runs, and a time before its start or in the future. Returns the last
    /// midnight piece.
    public func checkedStop(at: Date?) throws -> TimeEntry {
        let at = at.map { Time.whole($0) } ?? now
        guard let running = try runningEntries().first else {
            throw AutomationError.refused("No entry running.")
        }
        guard at <= now else {
            throw AutomationError.refused("The end \(Self.clockTime(at, timeZone)) lies in the future.")
        }
        guard at >= running.start else {
            throw AutomationError.refused("The end lies before the start at \(Self.clockTime(running.start, timeZone)).")
        }
        guard let stopped = try stop(at: at) else {
            throw AutomationError.refused("No entry running.")
        }
        return stopped
    }

    /// Creates a stopped entry; refuses an overlap (unless `force`), an end
    /// in the future, and an end before the start. Returns every piece.
    public func checkedCreate(_ draft: EntryDraft, force: Bool) throws -> [TimeEntry] {
        guard let end = draft.end else {
            throw AutomationError.usage("An entry needs --end.")
        }
        try refuseTimes(start: draft.start, end: end)
        if !force {
            try refuseOverlap(start: draft.start, end: end, excluding: [])
        }
        return try create(draft)
    }

    /// Changes one entry with the refusals of `checkedCreate` when its times
    /// change; the entry's own chain does not count as an overlap.
    public func checkedUpdate(_ id: EntryID, _ change: EntryChange, force: Bool) throws -> [TimeEntry] {
        guard let entry = try entry(id) else {
            throw AutomationError.notFound("No entry with id \(id.rawValue).")
        }
        let start = change.start ?? entry.start
        let end = change.end ?? entry.end
        let timesChange = change.start != nil || change.end != nil
        if timesChange {
            try refuseTimes(start: start, end: end ?? now)
        }
        if timesChange, !force {
            let chain = try chainEntries(root: entry.rootID).map(\.id)
            try refuseOverlap(start: start, end: end ?? now, excluding: Set(chain + [id]))
        }
        return try update(id, change)
    }

    private func refuseTimes(start: Date, end: Date) throws {
        guard end >= start else {
            throw AutomationError.refused("The end lies before the start.")
        }
        guard Time.whole(end) <= now, Time.whole(start) <= now else {
            throw AutomationError.refused("The entry would end in the future.")
        }
    }

    /// Refuses when a live entry other than `excluding` overlaps `start ..< end`.
    func refuseOverlap(start: Date, end: Date, excluding: Set<EntryID>) throws {
        let rows = try Row.fetchAll(
            database,
            sql: """
            SELECT * FROM time_entry
            WHERE deleted_at IS NULL AND "end" IS NOT NULL AND start < ? AND "end" > ?
            ORDER BY start
            """,
            arguments: [Time.seconds(end), Time.seconds(start)]
        )
        let overlapping = rows.map(TimeEntry.init(row:)).filter { !excluding.contains($0.id) }
        if let first = overlapping.first {
            let zone = timeZone
            throw AutomationError.refused(
                "The time overlaps the entry from \(Self.clockTime(first.start, zone)) to "
                    + "\(first.end.map { Self.clockTime($0, zone) } ?? "now") (\(first.id.rawValue)); add --force to allow it."
            )
        }
    }

    /// `HH:mm` in `zone`.
    static func clockTime(_ date: Date, _ zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// The result of a checked start: the new entry and the entry it stopped.
public struct StartOutcome: Hashable, Sendable {
    public var entry: TimeEntry
    /// The last piece of the entry that was running, now stopped.
    public var stopped: TimeEntry?

    public init(entry: TimeEntry, stopped: TimeEntry?) {
        self.entry = entry
        self.stopped = stopped
    }
}
