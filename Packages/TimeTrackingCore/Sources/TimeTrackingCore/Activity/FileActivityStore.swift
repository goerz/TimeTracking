// FileActivityStore: the file-backed ActivityReading (spec_data_and_sync.md §6,
// spec_activity_tracking.md §4).

public import Foundation
import os
import Synchronization

/// Reads the block log of the shared and the local folder (every Mac's
/// subfolder and the month files from before them), the detail log
/// and `current.json` of the local folder, and `settings.toml`. A device
/// filter keeps each block's part on those devices.
///
/// Month files are read lazily, parsed once, and parsed again when their
/// modification date or size changes. Blocks with the same id in both
/// folders count once (the shared copy wins). Exclusions of the current
/// `settings.toml` apply to every read. `refresh()` compares the files with
/// the previous refresh and reports changes on `changes`; `startWatching`
/// calls it periodically. On iOS the months in view must already be
/// downloaded; the `NSMetadataQuery` download and watch is not part of
/// this type. Blocks with the same id in two Macs' files also count once.
public actor FileActivityStore: ActivityReading {
    public let folders: ActivityFolders
    private let timeZone: TimeZone
    private let clock: any Clock
    private let homeDirectory: String
    private var months: [String: CachedMonth] = [:]
    private var stamps: FolderStamps
    private var cachedState: CachedState?
    private var watchTask: Task<Void, Never>?
    private let shared: Mutex<SharedState>
    private let broadcaster = Broadcaster<ActivityChange>()
    private static let logger = Logging.logger(category: "Activity")

    /// A store over `folders`. `timeZone` is the zone of `current.json`'s
    /// local times and of "today"; `homeDirectory` is what `~` means in the
    /// exclusions.
    public init(
        folders: ActivityFolders,
        timeZone: TimeZone = .current,
        clock: any Clock = SystemClock(),
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.folders = folders
        self.timeZone = timeZone
        self.clock = clock
        self.homeDirectory = homeDirectory
        let rules = Self.loadExclusions(folders: folders, homeDirectory: homeDirectory)
        self.shared = Mutex(SharedState(exclusions: rules))
        self.stamps = FolderStamps(folders: folders)
    }

    deinit {
        watchTask?.cancel()
        broadcaster.finish()
    }

    // MARK: ActivityReading

    // The protocol's signature: `nil` means every device, unlike an empty set.
    // swiftlint:disable:next discouraged_optional_collection
    public func blocks(in interval: DateInterval, devices: Set<String>?) throws(ActivityError) -> [ActivityBlock] {
        let rules = exclusions
        let fallback = shared.withLock(\.contexts)
        var seen = Set<String>()
        var result: [ActivityBlock] = []
        for folder in folders.blockFolders {
            for url in Self.monthFiles(in: folder, covering: interval) {
                let file = try monthFile(url)
                for entry in file.entries where Self.overlaps(entry.block, interval) && seen.insert(entry.block.id).inserted {
                    guard let part = Self.part(of: entry.block, on: devices) else {
                        continue
                    }
                    if let block = Self.applying(rules, to: part, contexts: entry.contexts, fallback: fallback) {
                        result.append(block)
                    }
                }
            }
        }
        if let open = todaysOpenBlock(), !seen.contains(open.id), Self.overlaps(open, interval),
           let part = Self.part(of: open, on: devices),
           let block = Self.applying(rules, to: part, contexts: [:], fallback: shared.withLock(\.contexts))
        {
            result.append(block)
        }
        return result.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    // swiftlint:disable:next discouraged_optional_collection
    public func backgroundStretches(in interval: DateInterval, devices: Set<String>?) throws(ActivityError) -> [ActivityBackgroundStretch] {
        let rules = exclusions
        let fallback = shared.withLock(\.contexts)
        var seen = Set<String>()
        var result: [ActivityBackgroundStretch] = []
        for folder in folders.blockFolders {
            for url in Self.monthFiles(in: folder, covering: interval) {
                let file = try monthFile(url)
                for entry in file.backgrounds where entry.stretch.start < interval.end && entry.stretch.end > interval.start
                    && seen.insert(entry.stretch.id).inserted
                {
                    if let part = entry.stretch.part(on: devices),
                       let stretch = Self.applying(rules, to: part, contexts: entry.contexts, fallback: fallback)
                    {
                        result.append(stretch)
                    }
                }
            }
        }
        return result.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    public func detail(for id: ActivityBlock.ID) throws(ActivityError) -> ActivityBlockDetail? {
        try details(for: [id])[id]
    }

    public func details(for ids: [ActivityBlock.ID]) throws(ActivityError) -> [ActivityBlock.ID: ActivityBlockDetail] {
        let wanted = Set(ids)
        // An id starts with the block's local date, the detail file's name.
        let days = Set(ids.map { String($0.prefix(10)) }.filter { $0.count == 10 })
        var result: [ActivityBlock.ID: ActivityBlockDetail] = [:]
        let rules = exclusions
        for day in days.sorted() {
            let url = folders.detailFolder.appending(path: "\(day).jsonl", directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            let file = try BlockLogFile(contentsOf: url)
            for entry in file.entries where wanted.contains(entry.block.id) && result[entry.block.id] == nil {
                let detail = entry.detail ?? ActivityBlockDetail(blockID: entry.block.id, items: entry.block.items)
                result[entry.block.id] = Self.applying(rules, to: detail, contexts: entry.contexts.merging(file.contexts) { own, _ in own })
            }
        }
        return result
    }

    public func currentState() -> TrackerState? {
        let url = folders.currentStateURL
        guard let stamp = FileStamp(url: url) else {
            cachedState = nil
            return nil
        }
        if let cachedState, cachedState.stamp == stamp {
            return cachedState.state
        }
        var state: TrackerState?
        do {
            state = try TrackerState.parse(Data(contentsOf: url), timeZone: timeZone)
        } catch {
            Self.logger.error("current.json: \(error.localizedDescription, privacy: .public)")
        }
        cachedState = CachedState(stamp: stamp, state: state)
        return state
    }

    public func aggregate(
        in interval: DateInterval,
        by key: ActivityGroupKey,
        device: String?
    ) throws(ActivityError) -> [ActivityAggregate] {
        try ActivityAggregation.aggregate(blocks(in: interval, devices: device.map { [$0] }), by: key)
    }

    public nonisolated func bundleIdentifier(forContext context: String) -> String? {
        shared.withLock { $0.contexts[context] }
    }

    public nonisolated var exclusions: ExclusionRules {
        shared.withLock(\.exclusions)
    }

    /// A new stream of changes; every stream receives every change found by
    /// `refresh()` after it was created.
    public nonisolated var changes: AsyncStream<ActivityChange> {
        broadcaster.stream()
    }

    // MARK: Health

    /// The malformed lines of every month file read so far.
    public var malformedLineCount: Int {
        months.values.reduce(0) { $0 + $1.file.malformedLines }
    }

    // MARK: Change detection

    /// Compares `current.json`, `settings.toml`, and the month files with the
    /// previous refresh (or creation), drops changed files from the cache,
    /// reloads the exclusions, and yields one change per changed artifact.
    public func refresh() {
        let current = FolderStamps(folders: folders)
        var found: [ActivityChange] = []
        if current.state != stamps.state {
            cachedState = nil
            found.append(.currentState)
        }
        if current.settings != stamps.settings {
            // A file that cannot be read now (a placeholder, a parse error)
            // keeps the exclusions in force.
            if let settings = try? TrackerSettings(contentsOf: folders.settingsURL) {
                let rules = settings.exclusions(homeDirectory: homeDirectory)
                shared.withLock { $0.exclusions = rules }
            }
            found.append(.settings)
        }
        var changedMonths = Set<String>()
        for path in Set(current.months.keys).union(stamps.months.keys) where current.months[path] != stamps.months[path] {
            months[path] = nil
            changedMonths.insert(URL(filePath: path).deletingPathExtension().lastPathComponent)
        }
        found += changedMonths.sorted().map { ActivityChange.blocks(month: $0) }
        stamps = current
        for change in found {
            broadcaster.yield(change)
        }
    }

    /// Calls `refresh()` every `interval` until `stopWatching()` (production;
    /// tests call `refresh()` directly).
    public func startWatching(every interval: Duration = .seconds(2)) {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard let self else {
                    return
                }
                await refresh()
            }
        }
    }

    /// Stops the polling of `startWatching(every:)`.
    public func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    // MARK: Helpers

    /// The parsed month file at `url`, from the cache while unchanged.
    private func monthFile(_ url: URL) throws(ActivityError) -> BlockLogFile {
        let path = url.path
        guard let stamp = FileStamp(url: url) else {
            months[path] = nil
            return BlockLogFile(data: Data())
        }
        if let cached = months[path], cached.stamp == stamp {
            return cached.file
        }
        let file = try BlockLogFile(contentsOf: url)
        if file.malformedLines > 0 {
            Self.logger.notice("\(url.lastPathComponent, privacy: .public): \(file.malformedLines) malformed lines")
        }
        months[path] = CachedMonth(stamp: stamp, file: file)
        shared.withLock { $0.contexts.merge(file.contexts) { _, new in new } }
        return file
    }

    /// The open block of `current.json` if it started today.
    private func todaysOpenBlock() -> ActivityBlock? {
        guard let block = currentState()?.activityBlock(timeZone: timeZone) else {
            return nil
        }
        let now = clock.now
        let today = LocalTimestamp(date: now, utcOffset: timeZone.secondsFromGMT(for: now)).dayKey
        return block.localDay == today ? block : nil
    }

    private static func loadExclusions(folders: ActivityFolders, homeDirectory: String) -> ExclusionRules {
        do {
            return try TrackerSettings(contentsOf: folders.settingsURL).exclusions(homeDirectory: homeDirectory)
        } catch {
            logger.error("settings.toml: \(error.localizedDescription, privacy: .public)")
            return TrackerSettings.defaults.exclusions(homeDirectory: homeDirectory)
        }
    }

    /// The month files of `folder` and its per-Mac subfolders whose month
    /// can hold blocks overlapping `interval` (a day of slack on each side
    /// covers every UTC offset).
    private static func monthFiles(in folder: URL, covering interval: DateInterval) -> [URL] {
        let first = LocalTimestamp(date: interval.start - 24 * 3600, utcOffset: 0).monthKey
        let last = LocalTimestamp(date: interval.end + 24 * 3600, utcOffset: 0).monthKey
        return BlockLogFolder.monthFiles(in: folder).filter { url in
            let month = BlockLogFolder.month(of: url)
            return month >= first && month <= last
        }
    }

    // swiftlint:disable discouraged_optional_collection
    /// `block`, or its part on `devices` when given (`nil` means every device).
    static func part(of block: ActivityBlock, on devices: Set<String>?) -> ActivityBlock? {
        guard let devices else {
            return block
        }
        return block.restricted(to: devices)
    }

    // swiftlint:enable discouraged_optional_collection

    /// Whether `block` overlaps `interval`; an empty block counts when it lies inside.
    private static func overlaps(_ block: ActivityBlock, _ interval: DateInterval) -> Bool {
        if block.end > block.start {
            return block.start < interval.end && block.end > interval.start
        }
        return interval.contains(block.start)
    }
}

// MARK: - State

/// The state the nonisolated requirements read.
private struct SharedState {
    var exclusions: ExclusionRules
    var contexts: [String: String] = [:]
}

private struct CachedMonth {
    var stamp: FileStamp
    var file: BlockLogFile
}

private struct CachedState {
    var stamp: FileStamp
    var state: TrackerState?
}
