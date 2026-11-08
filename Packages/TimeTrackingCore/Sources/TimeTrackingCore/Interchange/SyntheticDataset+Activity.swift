// SyntheticDataset.activityLog(to:): block-log date files that overlap the
// entries 70 percent of the time, with one time zone change
// (data_and_sync.md §9.1, activity_tracking.md §4.2).

public import Foundation

extension SyntheticDataset {
    /// Items a synthetic block draws from: work in a code project, a paper,
    /// and plain apps. Synthetic values, as in activity_tracking.md §2.3.
    private static let templates: [[ActivityItem]] = [
        [
            ActivityItem(
                app: "WezTerm",
                appID: "com.github.wez.wezterm",
                window: "Research",
                session: "refactor-parser",
                location: "~/Code/MyApp",
                command: "claude --resume",
                workspace: "~/Code/MyApp"
            ),
            ActivityItem(
                app: "Safari",
                appID: "com.apple.Safari",
                window: "Fix parser #123",
                location: "https://github.com/owner/MyApp/pull/123",
                workspace: "~/Code/MyApp"
            ),
        ],
        [
            ActivityItem(
                app: "WezTerm",
                appID: "com.github.wez.wezterm",
                window: "Research",
                session: "paper:draft.1",
                location: "~/Papers/2026_Noise",
                documents: ["~/Papers/2026_Noise/notes.tex"],
                command: "nvim notes.tex",
                workspace: "~/Papers/2026_Noise"
            ),
            ActivityItem(
                app: "Skim",
                appID: "net.sourceforge.skim-app.skim",
                window: "notes.pdf",
                location: "~/Papers/2026_Noise",
                documents: ["~/Papers/2026_Noise/notes.pdf"],
                workspace: "~/Papers/2026_Noise"
            ),
        ],
        [
            ActivityItem(app: "Mail", appID: "com.apple.mail", window: "Inbox"),
            ActivityItem(
                app: "Safari",
                appID: "com.apple.Safari",
                window: "Noise in qubits",
                location: "https://arxiv.org/abs/2401.1",
                workspace: "arxiv.org"
            ),
        ],
    ]

    private static let busyAgent = ActivityItem(
        app: "Claude Code",
        appID: "claude",
        session: "refactor-parser",
        location: "~/Code/MyApp",
        command: "claude --resume",
        workspace: "~/Code/MyApp"
    )

    private static let phoneSet = ActivityItem(app: "Social", appID: "screenTime", workspace: "Social")

    /// Writes `blocks/YYYY-MM-DD.jsonl` under `folder` for the Mac `device`.
    /// The second half of the range is written one hour east, as after travel.
    public func activityLog(to folder: URL, device: String = "MacBook") async throws {
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
        device: String = "MacBook"
    ) throws {
        let blocks = activityBlocks(of: entries, timeZone: timeZone, travelFrom: travelFrom, device: device)
        let log = BlockLogFolder(url: folder.appending(path: "blocks", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: log.url, withIntermediateDirectories: true)
        for (day, dayBlocks) in Dictionary(grouping: blocks, by: \.day) {
            try log.write(dayBlocks, for: day)
        }
    }

    /// The synthetic blocks of `entries`: one block for 70 percent of the
    /// finished entries, its items from one template, some with iPhone time
    /// and a busy coding agent.
    func activityBlocks(of entries: [TimeEntry], timeZone: TimeZone, travelFrom: TrackingDay?, device: String) -> [ActivityBlock] {
        var generator = SeededGenerator(seed: seed ^ 0xB10C)
        var blocks: [ActivityBlock] = []
        for entry in entries where entry.end != nil && generator.chance(0.7) {
            let end = entry.end ?? entry.start
            let seconds = Int(end.timeIntervalSince(entry.start))
            guard seconds >= 60 else {
                continue
            }
            let items = Self.templates[Int.random(in: 0 ..< Self.templates.count, using: &generator)]
            let phoneSeconds = generator.chance(0.15) ? seconds / 6 : 0
            let macSeconds = seconds - phoneSeconds
            let first = macSeconds * 2 / 3
            var foreground = [
                ActivityBlockItem(device: device, seconds: first, item: items[0]),
                ActivityBlockItem(device: device, seconds: macSeconds - first, item: items[1]),
            ].filter { $0.seconds > 0 }
            if phoneSeconds > 0 {
                foreground.append(ActivityBlockItem(device: "iPhone", seconds: phoneSeconds, item: Self.phoneSet))
            }
            let background = generator.chance(0.3) ? [ActivityBlockItem(device: device, seconds: seconds / 2, item: Self.busyAgent)] : []
            let shift = travelFrom.map { entry.day >= $0 ? 3600 : 0 } ?? 0
            blocks.append(ActivityBlock(
                start: entry.start,
                end: end,
                utcOffset: timeZone.secondsFromGMT(for: entry.start) + shift,
                endUTCOffset: timeZone.secondsFromGMT(for: end) + shift,
                endReason: .idle,
                foreground: foreground,
                background: background
            ))
        }
        return blocks
    }
}
