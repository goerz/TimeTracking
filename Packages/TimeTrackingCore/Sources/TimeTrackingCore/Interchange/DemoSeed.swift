// DemoSeed: `make demo` replaces a development store with a store fixture
// moved to today (spec_architecture.md §2.5, §7 item 23).

public import Foundation

/// Replaces the store of a Debug build or a simulator with a fixture moved
/// to today by `FixtureShift`, and writes the dataset's block log for it.
public enum DemoSeed {
    /// Whether `store` may be replaced: it lies in a Debug group container
    /// (a folder whose name ends in `.debug`) or in a simulator's data
    /// folder (`…/CoreSimulator/Devices/…`). A Release store never does.
    public static func isDevelopmentStore(_ store: URL) -> Bool {
        let components = store.standardizedFileURL.pathComponents
        if components.dropLast().contains(where: { $0.hasSuffix(".debug") }) {
            return true
        }
        return zip(components, components.dropFirst()).contains { $0 == "CoreSimulator" && $1 == "Devices" }
    }

    /// What `seed` wrote.
    public struct Report: Sendable {
        /// Whole days the fixture moved.
        public var days: Int
        public var entries: Int
        public var clipped: Int
        public var dropped: Int
        /// Block-log blocks written (0 without an activity folder).
        public var blocks: Int
    }

    /// Deletes the store at `store` (with its `-wal` and `-shm` files) and
    /// imports `document`, with settings, moved to `now` in `timeZone`.
    /// With `activity`, `activity/blocks/` is replaced by the block log of
    /// `dataset` for the moved entries. Throws `DemoSeedError` before
    /// touching anything when `store` is not a development store.
    public static func seed(
        document: Data,
        dataset: SyntheticDataset?,
        store: URL,
        activity: URL? = nil,
        now: Date,
        timeZone: TimeZone = .current
    ) async throws -> Report {
        guard isDevelopmentStore(store) else {
            throw DemoSeedError.notDevelopmentStore(store.path)
        }
        let shift = try FixtureShift(document: document, now: now, timeZone: timeZone)
        let moved = try shift.apply(to: document)
        let manager = FileManager.default
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let file = URL(filePath: store.path + suffix)
            if manager.fileExists(atPath: file.path) {
                try manager.removeItem(at: file)
            }
        }
        try manager.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        let opened = try await TimeStore.open(TimeStore.Configuration(
            location: .file(store),
            clock: ManualClock(now),
            deviceID: dataset?.deviceID ?? DeviceID(),
            timeZone: { timeZone }
        ))
        _ = try await opened.importDocument(moved.document, options: ImportOptions(includeSettings: true))
        let entries = try await opened.entries(in: DateInterval(start: .distantPast, end: now), includeDeleted: false)
        var blocks = 0
        if let activity {
            let folder = activity.appending(path: "blocks", directoryHint: .isDirectory)
            if manager.fileExists(atPath: folder.path) {
                try manager.removeItem(at: folder)
            }
            if let dataset {
                try dataset.activityLog(of: entries, timeZone: timeZone, to: activity)
                let files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                blocks = try files.reduce(0) { count, file in try count + BlockLogFile(contentsOf: file).blocks.count }
            }
        }
        return Report(days: shift.days, entries: entries.count, clipped: moved.clipped, dropped: moved.dropped, blocks: blocks)
    }
}
