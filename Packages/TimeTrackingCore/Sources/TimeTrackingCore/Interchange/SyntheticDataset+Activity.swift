// SyntheticDataset.activityLog(to:): block-log files that overlap the
// entries 70 percent of the time, with one time zone change (spec_data_and_sync.md §9.1).

public import Foundation

extension SyntheticDataset {
    private static let contexts = ["tmux:paper": "com.example.terminal", "safari": "com.apple.Safari", "mail": "com.apple.mail"]

    /// Writes `blocks/YYYY-MM.jsonl` under `folder` for device `device`. The
    /// second half of the range is written one hour east, as after travel.
    public func activityLog(to folder: URL, device: String = "macbook") async throws {
        let store = try await populatedStore(withTombstones: false)
        let calendar = TrackingCalendar(timeZone: zone)
        let entries = try await store.entries(in: calendar.interval(of: days), includeDeleted: false)
        let switchDay = days.lowerBound.adding(days: days.lowerBound.distance(to: days.upperBound) / 2)
        try activityLog(of: entries, timeZone: zone, travelFrom: switchDay, to: folder, device: device)
    }

    /// Writes the block log of `entries` (the finished ones) with the
    /// offsets of `timeZone`, from day `travelFrom` on one hour east.
    /// `make demo` passes the entries of a store moved to today.
    public func activityLog(
        of entries: [TimeEntry],
        timeZone: TimeZone,
        travelFrom: TrackingDay? = nil,
        to folder: URL,
        device: String = "macbook"
    ) throws {
        var writer = BlockLogWriter(folder: folder.appending(path: "blocks", directoryHint: .isDirectory), device: device)
        try FileManager.default.createDirectory(at: writer.folder, withIntermediateDirectories: true)
        var generator = SeededGenerator(seed: seed ^ 0xB10C)
        let names = Self.contexts.keys.sorted()
        for entry in entries where entry.end != nil && generator.chance(0.7) {
            let end = entry.end ?? entry.start
            let seconds = Int(end.timeIntervalSince(entry.start))
            guard seconds >= 60 else {
                continue
            }
            let context = names[Int.random(in: 0 ..< names.count, using: &generator)]
            let shift = travelFrom.map { entry.day >= $0 ? 3600 : 0 } ?? 0
            let block = ActivityBlock(
                start: entry.start,
                end: end,
                activeSeconds: seconds,
                device: device,
                groupKey: context,
                groupShare: 1,
                items: [ActivityItem(context: context, subject: entry.task, detail: "", seconds: seconds)],
                utcOffset: timeZone.secondsFromGMT(for: entry.start) + shift
            )
            try writer.append(block, contexts: Self.contexts)
        }
    }
}
