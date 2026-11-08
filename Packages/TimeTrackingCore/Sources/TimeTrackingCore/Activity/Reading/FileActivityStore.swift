// FileActivityStore: the file-backed ActivityReading (data_and_sync.md §6,
// activity_tracking.md §4).

public import Foundation
import os
import Synchronization

/// Reads the date files of the block log, `current.json`, and `settings.toml`.
///
/// Date files are read lazily, parsed once, and parsed again when their
/// modification date or size changes. In the copy fallback a date may have
/// a file in both `blocks/` folders; the newer one counts. Exclusions of the
/// current `settings.toml` apply to every read, and a device filter keeps
/// each block's part on those devices. `refresh()` compares the files with
/// the previous refresh and reports changes on `changes`; `startWatching`
/// calls it periodically. On iOS the dates in view must already be
/// downloaded; asking iCloud Drive for them is not part of this type.
public actor FileActivityStore: ActivityReading {
    public let folders: ActivityFolders
    private let homeDirectory: String
    private var dateFiles: [String: CachedDateFile] = [:]
    private var stamps: FolderStamps
    private var cachedState: CachedState?
    private var watchTask: Task<Void, Never>?
    private let shared: Mutex<SharedSettings>
    private let broadcaster = Broadcaster<ActivityChange>()
    private static let logger = Logging.logger(category: "Activity")

    /// The longest a block can run past the end of its start date (§4.1),
    /// plus the widest UTC offset, so every date that can hold a block
    /// overlapping an interval is read.
    private static let dateSlack: TimeInterval = 3 * 3600 + 14 * 3600

    /// A store over `folders`; `homeDirectory` is what `~` means in the exclusions.
    public init(folders: ActivityFolders, homeDirectory: String = NSHomeDirectory()) {
        self.folders = folders
        self.homeDirectory = homeDirectory
        self.shared = Mutex(SharedSettings(settings: Self.loadSettings(folders: folders), homeDirectory: homeDirectory))
        self.stamps = FolderStamps(folders: folders)
    }

    deinit {
        watchTask?.cancel()
        broadcaster.finish()
    }

    // MARK: ActivityReading

    // `nil` means every device, unlike an empty set.
    // swiftlint:disable discouraged_optional_collection
    public func blocks(in interval: DateInterval, devices: Set<String>?) -> [ActivityBlock] {
        var result = storedBlocks(in: interval, devices: devices).filter { !$0.isBackgroundBlock }
        let rules = exclusions
        if let open = currentState()?.block, !result.contains(where: { $0.start < open.end && $0.end > open.start }),
           open.overlaps(interval),
           let block = open.part(on: devices).flatMap(rules.applied(to:))
        {
            result.append(block)
        }
        return result.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    public func backgroundBlocks(in interval: DateInterval, devices: Set<String>?) -> [ActivityBlock] {
        storedBlocks(in: interval, devices: devices).filter(\.isBackgroundBlock)
    }

    // swiftlint:enable discouraged_optional_collection

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
            state = try TrackerState.parse(Data(contentsOf: url))
        } catch {
            Self.logger.error("current.json: \(error.localizedDescription, privacy: .public)")
        }
        cachedState = CachedState(stamp: stamp, state: state)
        return state
    }

    public nonisolated var settings: TrackerSettings {
        shared.withLock(\.settings)
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

    /// The malformed lines of every date file read so far.
    public var malformedLineCount: Int {
        dateFiles.values.reduce(0) { $0 + $1.malformedLines }
    }

    /// Whether the date file of `day` can be read: present, missing, or
    /// held by iCloud Drive only as a placeholder (its download is asked for).
    public func dateFileStatus(of day: TrackingDay) -> ActivityDateFileStatus {
        var status = ActivityDateFileStatus.missing
        for folder in folders.blockFolders {
            let url = folder.fileURL(for: day)
            if ActivityFile.isPendingDownload(url) {
                status = .notDownloaded
            } else if FileManager.default.fileExists(atPath: url.path) {
                return .present
            }
        }
        return status
    }

    /// The latest date that has a date file (present or a placeholder),
    /// with that file's modification time.
    public func newestDateFile() -> (day: TrackingDay, modified: Date?)? {
        var newest: (day: TrackingDay, modified: Date?)?
        for folder in folders.blockFolders {
            guard let day = folder.days().last, newest.map({ day > $0.day }) ?? true else {
                continue
            }
            newest = (day, FileStamp(url: folder.fileURL(for: day))?.modified)
        }
        return newest
    }

    // MARK: Change detection

    /// Compares `current.json`, `settings.toml`, and the date files with the
    /// previous refresh (or creation), drops changed files from the cache,
    /// reloads the settings, and yields one change per changed artifact.
    public func refresh() {
        let current = FolderStamps(folders: folders)
        var found: [ActivityChange] = []
        if current.state != stamps.state {
            cachedState = nil
            found.append(.currentState)
        }
        if current.settings != stamps.settings {
            // A file that cannot be read now (a placeholder, a parse error)
            // keeps the settings in force.
            if let settings = try? TrackerSettings(contentsOf: folders.settingsURL) {
                let home = homeDirectory
                shared.withLock { $0 = SharedSettings(settings: settings, homeDirectory: home) }
            }
            found.append(.settings)
        }
        var changedDays = Set<TrackingDay>()
        for path in Set(current.dateFiles.keys).union(stamps.dateFiles.keys) where current.dateFiles[path] != stamps.dateFiles[path] {
            dateFiles[path] = nil
            if let day = BlockLogFolder.day(ofFileName: URL(filePath: path).lastPathComponent) {
                changedDays.insert(day)
            }
        }
        found += changedDays.sorted().map { ActivityChange.blocks(day: $0) }
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

    // MARK: Reading date files

    /// The stored blocks, foreground and background, overlapping
    /// `interval`, with the exclusions and the device filter applied
    /// (`nil` devices: every device).
    private func storedBlocks(
        in interval: DateInterval,
        // swiftlint:disable:next discouraged_optional_collection
        devices: Set<String>?
    ) -> [ActivityBlock] {
        let rules = exclusions
        let first = TrackingDay(ActivityTimestamp.day(interval.start - Self.dateSlack, utcOffset: 0))
        let last = TrackingDay(ActivityTimestamp.day(interval.end + 14 * 3600, utcOffset: 0))
        guard let first, let last, first <= last else {
            return []
        }
        var result: [ActivityBlock] = []
        var day = first
        while day <= last {
            for block in blocks(of: day) where block.overlaps(interval) {
                if let kept = block.part(on: devices).flatMap(rules.applied(to:)) {
                    result.append(kept)
                }
            }
            day = day.adding(days: 1)
        }
        return result.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    /// The blocks of the date's file, from the newer folder that has one.
    private func blocks(of day: TrackingDay) -> [ActivityBlock] {
        let candidates = folders.blockFolders.compactMap { folder -> (URL, FileStamp)? in
            let url = folder.fileURL(for: day)
            return FileStamp(url: url).map { (url, $0) }
        }
        guard let (url, stamp) = candidates.max(by: { ($0.1.modified ?? .distantPast) < ($1.1.modified ?? .distantPast) }) else {
            return []
        }
        if let cached = dateFiles[url.path], cached.stamp == stamp {
            return cached.blocks
        }
        guard !ActivityFile.isPendingDownload(url), let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        let parsed = BlockLogFile.parse(text)
        if parsed.malformedLines > 0 {
            Self.logger.notice("\(url.lastPathComponent, privacy: .public): \(parsed.malformedLines) malformed lines")
        }
        dateFiles[url.path] = CachedDateFile(stamp: stamp, blocks: parsed.blocks, malformedLines: parsed.malformedLines)
        return parsed.blocks
    }

    private static func loadSettings(folders: ActivityFolders) -> TrackerSettings {
        do {
            return try TrackerSettings(contentsOf: folders.settingsURL)
        } catch {
            logger.error("settings.toml: \(error.localizedDescription, privacy: .public)")
            return .defaults
        }
    }
}

// MARK: - State

/// The settings the nonisolated requirements read.
private struct SharedSettings {
    var settings: TrackerSettings
    var exclusions: ExclusionRules

    init(settings: TrackerSettings, homeDirectory: String) {
        self.settings = settings
        self.exclusions = settings.exclusions(homeDirectory: homeDirectory)
    }
}

private struct CachedDateFile {
    var stamp: FileStamp
    var blocks: [ActivityBlock]
    var malformedLines: Int
}

private struct CachedState {
    var stamp: FileStamp
    var state: TrackerState?
}
