// Entry writes (spec_data_and_sync.md §1.4, §1.5, §7.1).

public import Foundation
import GRDB

extension StoreTransaction {
    /// Tombstones older than this are hard-deleted and cannot be restored.
    static let retention: TimeInterval = 180 * 86_400

    /// Starts an entry at `at`, stopping the running one there.
    public func start(projectID: ProjectID?, task: String, at: Date) throws -> TimeEntry {
        let at = Time.whole(at)
        guard at <= now else {
            throw StoreError.inFuture
        }
        if let projectID {
            guard let project = try project(projectID) else {
                throw StoreError.unknownID
            }
            guard !project.isArchived else {
                throw StoreError.projectArchived
            }
        }
        for running in try runningEntries() {
            guard at >= running.start else {
                throw StoreError.endBeforeStart
            }
            var stopped = running
            stopped.end = at
            try write(stopped)
            _ = try splitAcrossMidnights(stopped)
        }
        let entry = TimeEntry(
            projectID: projectID,
            task: task.trimmed,
            start: at,
            end: nil,
            timeZone: timeZone.identifier,
            deviceID: deviceID,
            createdAt: now,
            modifiedAt: modifiedAt
        )
        try write(entry)
        return entry
    }

    /// Stops the running entry at `at`; `nil` when nothing runs.
    @discardableResult
    public func stop(at: Date) throws -> TimeEntry? {
        let at = Time.whole(at)
        guard at <= now else {
            throw StoreError.inFuture
        }
        var stopped: TimeEntry?
        for running in try runningEntries() {
            guard at >= running.start else {
                throw StoreError.endBeforeStart
            }
            var entry = running
            entry.end = at
            try write(entry)
            stopped = try splitAcrossMidnights(entry).last
        }
        return stopped
    }

    /// Starts a new entry with the project and task of `id`.
    public func `continue`(_ id: EntryID, at: Date) throws -> TimeEntry {
        let entry = try liveEntry(id)
        return try start(projectID: entry.projectID, task: entry.task, at: at)
    }

    /// Creates an entry; returns its pieces, the given id first.
    public func create(_ draft: EntryDraft) throws -> [TimeEntry] {
        let start = Time.whole(draft.start)
        let end = draft.end.map { Time.whole($0) }
        try validate(start: start, end: end)
        if let projectID = draft.projectID, try project(projectID) == nil {
            throw StoreError.unknownID
        }
        let id = draft.id ?? EntryID()
        if try entry(id, includeDeleted: true) != nil {
            throw StoreError.referenced
        }
        let entry = TimeEntry(
            id: id,
            projectID: draft.projectID,
            task: draft.task.trimmed,
            start: start,
            end: end,
            timeZone: draft.timeZone ?? timeZone.identifier,
            deviceID: deviceID,
            createdAt: now,
            modifiedAt: modifiedAt
        )
        try write(entry)
        return try splitAcrossMidnights(entry)
    }

    /// Changes project, task, start, or end; returns the pieces, the given id first.
    public func update(_ id: EntryID, _ change: EntryChange) throws -> [TimeEntry] {
        var entry = try liveEntry(id)
        if let projectID = change.projectID {
            if let projectID, try project(projectID) == nil {
                throw StoreError.unknownID
            }
            entry.projectID = projectID
        }
        if let task = change.task {
            entry.task = task.trimmed
        }
        if let start = change.start {
            entry.start = Time.whole(start)
        }
        if let end = change.end {
            entry.end = Time.whole(end)
        }
        try validate(start: entry.start, end: entry.end)
        try write(entry)
        return try splitAcrossMidnights(entry)
    }

    /// Moves start and end by `offset`.
    public func move(_ id: EntryID, by offset: TimeInterval) throws -> [TimeEntry] {
        var entry = try liveEntry(id)
        entry.start = Time.whole(entry.start + offset)
        entry.end = entry.end.map { Time.whole($0 + offset) }
        try validate(start: entry.start, end: entry.end)
        try write(entry)
        return try splitAcrossMidnights(entry)
    }

    /// A user split at `at`: the entry ends there and a new entry with a
    /// random id continues to the original end (or keeps running).
    public func split(_ id: EntryID, at: Date) throws -> (TimeEntry, TimeEntry) {
        var first = try liveEntry(id)
        let at = Time.whole(at)
        guard at <= now else {
            throw StoreError.inFuture
        }
        guard at > first.start, first.end.map({ at < $0 }) ?? true else {
            throw StoreError.endBeforeStart
        }
        let second = TimeEntry(
            projectID: first.projectID,
            task: first.task,
            start: at,
            end: first.end,
            timeZone: first.timeZone,
            deviceID: first.deviceID,
            createdAt: now,
            modifiedAt: modifiedAt
        )
        first.end = at
        try write(first)
        try write(second)
        return (first, second)
    }

    /// Tombstones live entries; ids already deleted are skipped.
    public func delete(_ ids: [EntryID]) throws {
        for id in ids {
            guard var entry = try entry(id, includeDeleted: true) else {
                throw StoreError.unknownID
            }
            guard entry.deletedAt == nil else {
                continue
            }
            entry.deletedAt = now
            try write(entry)
        }
    }

    /// Brings back tombstoned entries within the retention period.
    public func restore(_ ids: [EntryID]) throws {
        for id in ids {
            guard var entry = try entry(id, includeDeleted: true) else {
                throw try isPurged(id.rawValue) ? StoreError.retentionExpired : StoreError.unknownID
            }
            guard let deletedAt = entry.deletedAt else {
                continue
            }
            guard now.timeIntervalSince(deletedAt) <= Self.retention else {
                throw StoreError.retentionExpired
            }
            entry.deletedAt = nil
            try write(entry)
            _ = try splitAcrossMidnights(entry)
        }
    }

    func isPurged(_ name: String) throws -> Bool {
        try Bool.fetchOne(database, sql: "SELECT 1 FROM purged_record WHERE record_id = ?", arguments: [name]) ?? false
    }

    private func validate(start: Date, end: Date?) throws {
        if let end, end < start {
            throw StoreError.endBeforeStart
        }
        guard start <= now, (end ?? start) <= now else {
            throw StoreError.inFuture
        }
    }

    // MARK: Midnight split

    /// Splits a live entry at every midnight of its zone after its start
    /// and before its end (or `now` while running) (spec §1.5). Returns the
    /// entry and its pieces in order, the entry first.
    @discardableResult
    func splitAcrossMidnights(_ entry: TimeEntry) throws -> [TimeEntry] {
        let midnights = TrackingCalendar.midnights(after: entry.start, before: entry.end ?? now, in: entry.zone)
        guard let first = midnights.first else {
            return [entry]
        }
        let calendar = TrackingCalendar(timeZone: entry.zone)
        let root = entry.rootID
        var original = entry
        original.end = first
        try write(original)
        record(.splitAtMidnight, before: entry, after: original)
        var result = [original]
        for (index, midnight) in midnights.enumerated() {
            let end = index + 1 < midnights.count ? midnights[index + 1] : entry.end
            let name = "split:\(calendar.day(containing: midnight))"
            var id = EntryID(UUID.version5(namespace: root.uuid, name: name))
            if id == entry.id {
                id = EntryID()
            }
            let piece = TimeEntry(
                id: id,
                projectID: entry.projectID,
                task: entry.task,
                start: midnight,
                end: end,
                timeZone: entry.timeZone,
                deviceID: entry.deviceID,
                splitRootID: root,
                createdAt: midnight,
                modifiedAt: modifiedAt
            )
            if let existing = try self.entry(id, includeDeleted: true) {
                // A tombstoned derived id stays deleted and that part is dropped.
                guard existing.deletedAt == nil else {
                    continue
                }
                if !existing.sameContent(as: piece) {
                    try write(piece)
                }
            } else {
                try write(piece)
                splitPieceCount += 1
            }
            record(.splitAtMidnight, before: nil, after: piece)
            result.append(piece)
        }
        return result
    }

    func record(
        _ reason: EntryAdjustment.Reason,
        before: TimeEntry?,
        after: TimeEntry?,
        causingEntry: EntryID? = nil,
        causingDevice: DeviceID? = nil
    ) {
        guard let id = after?.id ?? before?.id else {
            return
        }
        adjustments.append(EntryAdjustment(
            entryID: id,
            reason: reason,
            before: before,
            after: after,
            causingEntryID: causingEntry,
            causingDeviceID: causingDevice,
            time: now
        ))
    }
}

extension TimeEntry {
    /// Equal in every field except the bookkeeping times.
    func sameContent(as other: Self) -> Bool {
        id == other.id && projectID == other.projectID && task == other.task && start == other.start
            && end == other.end && timeZone == other.timeZone && deviceID == other.deviceID
            && splitRootID == other.splitRootID && deletedAt == other.deletedAt
    }
}
