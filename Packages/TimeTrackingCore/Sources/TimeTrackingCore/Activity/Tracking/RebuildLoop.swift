// RebuildLoop: the passes over `changed_dates` that turn Samples into the
// date files of the block log (activity_tracking.md §2.7, §4.1).

public import Foundation
import GRDB

/// One pass at a time over the changed dates, the oldest first and today last.
public struct RebuildLoop: Sendable {
    public let store: SampleStore
    /// The `blocks/` folder; `nil` on a Mac that doesn't record (§4.1),
    /// which forms blocks but writes no date file.
    public let log: BlockLogFolder?

    public init(store: SampleStore, log: BlockLogFolder?) {
        self.store = store
        self.log = log
    }

    /// Whether a date waits for a pass.
    public func hasWork() throws -> Bool {
        try !(store.meta(.changedDays) ?? []).isEmpty
    }

    /// Runs one pass if a date waits; `nil` when none does.
    public func runOnePass(now: Date, context: RebuildContext) throws -> PassResult? {
        let boundaries = try store.boundaries(rules: context.rules)
        let changed = try store.meta(.changedDays) ?? []
        let today = boundaries.day(containing: now)
        guard let day = changed.filter({ $0 != today }).min() ?? changed.min() else {
            return nil
        }
        let cutoff = try store.meta(.cutoffDay)
        if let cutoff, day < cutoff {
            try store.database.write { try Self.unmark(day, in: $0) }
            return .frozen(day)
        }
        let previous = day.adding(days: -1)
        let ends = try store.meta(.dayEnds) ?? [:]
        // A frozen date before gets no pass, so D can't wait for it.
        if ends[previous] == .unsettled, cutoff.map({ previous >= $0 }) ?? true {
            try store.database.write { database in
                try Self.unmark(day, in: database)
                try database.setMeta(.changedDays, (database.meta(.changedDays) ?? []).union([previous]))
            }
            return .waiting(day)
        }
        let previousEnd: Date?
        switch self.previousEnd(previous, ends: ends) {
        case let .known(end):
            previousEnd = end
        case let .unknown(reason):
            // A block over midnight would land in both files; D waits.
            return .failed(day: day, reason: reason)
        }
        let readStart = max(boundaries.start(of: day), previousEnd ?? .distantPast)
        let former = try BlockFormer(settings: context.settings, macDeviceID: context.macDeviceID, deviceNames: deviceNames(context))
        let readEnd = former.readEnd(of: day, boundaries: boundaries) + Sample.maxCoverage
        let samples = try store.samples(SampleSelection(range: DateInterval(start: readStart, end: max(readStart, readEnd))))
            .map { $0.mapItems(context.redactor.redacted) }
        let pass = former.pass(day: day, samples: samples, boundaries: boundaries, readStart: readStart, now: now)

        // The file first: a crash before the meta transaction leaves the date marked.
        let written: BlockLogFolder.WriteResult
        do {
            written = try log?.write(pass.blocks, for: day) ?? .unchanged
        } catch {
            return .failed(day: day, reason: error.localizedDescription)
        }
        try store.database.write { database in
            try Self.unmark(day, in: database)
            if written == .pendingDownload {
                try database.setMeta(.placeholderDays, (database.meta(.placeholderDays) ?? []).union([day]))
            }
            var dayEnds = try database.meta(.dayEnds) ?? [:]
            let old = dayEnds[day]
            dayEnds[day] = pass.end
            try database.setMeta(.dayEnds, dayEnds)
            let next = day.adding(days: 1)
            if case .settled = pass.end, old != pass.end, next <= today {
                try database.setMeta(.changedDays, (database.meta(.changedDays) ?? []).union([next]))
            }
        }
        return .formed(day: day, written: written, current: pass.current)
    }

    /// Marks the dates whose file was a placeholder and has arrived since;
    /// returns them. A tick calls this, so a skipped date is written soon
    /// after its download (§4.1).
    @discardableResult
    public func recheckPlaceholders() throws -> Set<TrackingDay> {
        guard let log else {
            return []
        }
        let waiting = try store.meta(.placeholderDays) ?? []
        let arrived = waiting.filter { log.content(for: $0) != .pendingDownload }
        guard !arrived.isEmpty else {
            return []
        }
        try store.database.write { database in
            try database.setMeta(.placeholderDays, waiting.subtracting(arrived))
            try database.setMeta(.changedDays, (database.meta(.changedDays) ?? []).union(arrived))
        }
        return arrived
    }

    /// Where the date before ends: its stored end, else for a frozen date
    /// the last end in its file; `nil` when it has no block.
    private enum PreviousEnd {
        /// Where the date before ends, or `nil` when nothing does.
        case known(Date?)
        /// Its file holds the answer but can't be read yet.
        case unknown(String)
    }

    private func previousEnd(_ day: TrackingDay, ends: [TrackingDay: DateEnd]) -> PreviousEnd {
        if case let .settled(end) = ends[day] {
            return .known(end)
        }
        guard let log else {
            return .known(nil)
        }
        switch log.content(for: day) {
        case .missing:
            return .known(nil)
        case .pendingDownload:
            return .unknown("the file of \(day) is not downloaded from iCloud Drive yet")
        case let .unreadable(reason):
            return .unknown(reason)
        case let .text(text):
            return .known(BlockLogFile.parse(text).blocks.map(\.end).max())
        }
    }

    private func deviceNames(_ context: RebuildContext) throws -> [String: String] {
        var names = try store.meta(.deviceNames) ?? [:]
        names[context.macDeviceID] = context.macName
        return names
    }

    private static func unmark(_ day: TrackingDay, in database: GRDB.Database) throws {
        var changed = try database.meta(.changedDays) ?? []
        changed.remove(day)
        try database.setMeta(.changedDays, changed)
    }
}
