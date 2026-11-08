// ActivityFolderMirror: the Mac app's copy of the agent's fallback block log
// into the iCloud Drive container (activity_tracking.md §4.1).

public import Foundation

/// Copies the local `Activity/blocks/` date files into the container's
/// `Activity/blocks/` and keeps the two `settings.toml` identical.
///
/// Used when the agent cannot write the container: the agent writes its
/// local folder, and the Mac app runs `sync()` every couple of seconds. A
/// changed date file replaces the container copy as a whole, through
/// `NSFileCoordinator`; of two different `settings.toml`, the one modified
/// later wins.
public struct ActivityFolderMirror: Sendable {
    /// The agent's local `Activity/` folder.
    public let local: URL
    /// `Activity/` in the ubiquity container.
    public let container: URL

    public init(local: URL, container: URL) {
        self.local = local
        self.container = container
    }

    /// The `shared_folder` reason of an agent that cannot write the container.
    public static let fallbackReason = "Copied to iCloud Drive while the app is open"

    /// Whether `state` says the agent writes the local folder and relies on
    /// the Mac app's copy: `shared_folder` reports `fallback`, which it does
    /// only then (without iCloud Drive it reports `off`). The reason is
    /// display text and is not compared.
    public static func isNeeded(for state: TrackerState?) -> Bool {
        state?.health.sources.first { $0.id == "shared_folder" }?.status == .fallback
    }

    /// What one `sync()` copied.
    public struct Report: Sendable, Hashable {
        /// The dates whose files were copied into the container.
        public var days: [TrackingDay] = []
        /// `local` or `container`: the `settings.toml` that was copied over the other one.
        public var settingsFrom: String?
    }

    /// Copies what changed since the last call.
    @discardableResult
    public func sync() throws(ActivityError) -> Report {
        var report = Report()
        let localBlocks = BlockLogFolder(url: local.appending(path: "blocks", directoryHint: .isDirectory))
        let containerBlocks = BlockLogFolder(url: container.appending(path: "blocks", directoryHint: .isDirectory))
        for day in localBlocks.days() {
            let source = localBlocks.fileURL(for: day)
            let target = containerBlocks.fileURL(for: day)
            // Only a newer local file goes forward, so files left from an
            // earlier fallback period never replace newer container files;
            // a container file not downloaded yet waits until it is.
            if !ActivityFile.isPendingDownload(target), !Self.sameContents(source, target),
               Self.modificationDate(target).map({ target in Self.modificationDate(source).map { $0 > target } ?? false }) ?? true
            {
                try Self.replace(target, with: source)
                report.days.append(day)
            }
        }
        let localSettings = local.appending(path: "settings.toml", directoryHint: .notDirectory)
        let containerSettings = container.appending(path: "settings.toml", directoryHint: .notDirectory)
        // A pending download or an unresolved conflict waits: either side
        // may hold the newer edit.
        if !ActivityFile.isPendingDownload(containerSettings), !Self.hasConflicts(localSettings), !Self.hasConflicts(containerSettings),
           !Self.sameContents(localSettings, containerSettings)
        {
            let localDate = Self.modificationDate(localSettings)
            let containerDate = Self.modificationDate(containerSettings)
            if let localDate, containerDate.map({ localDate > $0 }) ?? true {
                try Self.replace(containerSettings, with: localSettings)
                report.settingsFrom = "local"
            } else if containerDate != nil {
                try Self.replace(localSettings, with: containerSettings)
                report.settingsFrom = "container"
            }
        }
        return report
    }

    private static func sameContents(_ first: URL, _ second: URL) -> Bool {
        let manager = FileManager.default
        let firstExists = manager.fileExists(atPath: first.path)
        let secondExists = manager.fileExists(atPath: second.path)
        guard firstExists, secondExists else {
            return firstExists == secondExists
        }
        return manager.contentsEqual(atPath: first.path, andPath: second.path)
    }

    private static func hasConflicts(_ url: URL) -> Bool {
        !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Replaces `target` with a copy of `source` (whole file), coordinated,
    /// keeping the source's modification date.
    private static func replace(_ target: URL, with source: URL) throws(ActivityError) {
        // The date before the data: a file replaced in between is copied
        // again next time instead of stamped as current.
        let date = modificationDate(source)
        let data: Data
        do {
            data = try Data(contentsOf: source)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw .fileSystem("\(source.lastPathComponent): \(error.localizedDescription)")
        }
        var coordinationError: NSError?
        var writeError: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { url in
            do {
                try data.write(to: url, options: .atomic)
                if let date {
                    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
                }
            } catch {
                writeError = error
            }
        }
        if let failure = coordinationError ?? writeError {
            throw .fileSystem("\(target.lastPathComponent): \(failure.localizedDescription)")
        }
    }
}
