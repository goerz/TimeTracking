// CollectionFlush: when the iOS app flushes the collection file and what it
// adds before the upload (ios.md §6.1, §9.5, §9.6).

public import Foundation

/// The flush rules of the app process.
public enum CollectionFlush {
    /// The wrapper intents flush only when the last flush is older than this,
    /// and the app flushes this often while open.
    public static let interval: TimeInterval = 300

    /// Whether a flush is due: never flushed, more than 5 minutes ago, or
    /// the clock went back.
    public static func isDue(lastFlushAt: Date?, now: Date) -> Bool {
        guard let lastFlushAt else {
            return true
        }
        return now.timeIntervalSince(lastFlushAt) > interval || now < lastFlushAt
    }

    /// `events` with this device's name, which the extensions cannot know.
    public static func stamped(_ events: [DeviceEvent], deviceName: String) -> [DeviceEvent] {
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return events
        }
        return events.map { event in
            var stamped = event
            stamped.deviceName = stamped.deviceName ?? name
            return stamped
        }
    }

    /// Copies `settings.toml` from the shared (iCloud Drive) folder into the
    /// App Group folder the Safari extension reads, when it changed; returns
    /// whether it wrote. Starts the download of a file iCloud has not
    /// fetched yet (the next foreground copies it).
    @discardableResult
    public static func refreshSettingsCopy(from shared: URL, to local: URL) throws(ActivityError) -> Bool {
        let source = shared.appending(path: "settings.toml", directoryHint: .notDirectory)
        let target = local.appending(path: "settings.toml", directoryHint: .notDirectory)
        guard source.standardizedFileURL != target.standardizedFileURL else {
            return false
        }
        let manager = FileManager.default
        try? manager.startDownloadingUbiquitousItem(at: source)
        var coordinated: Data?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinatorError) { url in
            coordinated = try? Data(contentsOf: url)
        }
        guard let data = coordinated else {
            return false
        }
        if (try? Data(contentsOf: target)) == data {
            return false
        }
        do {
            try manager.createDirectory(at: local, withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            throw .fileSystem("settings.toml: \(error.localizedDescription)")
        }
        return true
    }
}
