// ActivityFile: whole-file replacement and iCloud Drive placeholders for the
// activity files (activity_tracking.md §4.1, §4.4).

public import Foundation

/// Writes whole files so a reader sees the old or the new content, never a
/// mix, and tells files iCloud Drive holds only as placeholders.
public enum ActivityFile {
    /// Writes `data` to a temporary file on `url`'s volume, outside its
    /// folder (so one a crash leaves behind never syncs), flushes it to
    /// disk, and renames it over `url`. In iCloud Drive (`coordinated`) the
    /// replacement goes through `NSFileCoordinator`, so the sync daemon
    /// sees one whole new version.
    public static func write(_ data: Data, to url: URL, coordinated: Bool = false) throws {
        guard coordinated else {
            try replace(url, with: data)
            return
        }
        var coordinationError: NSError?
        var writeError: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                try replace(target, with: data)
            } catch {
                writeError = error
            }
        }
        if let failure = coordinationError ?? writeError {
            throw failure
        }
    }

    private static func replace(_ url: URL, with data: Data) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let scratch = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? manager.removeItem(at: scratch) }
        let temporary = scratch.appending(path: url.lastPathComponent, directoryHint: .notDirectory)
        do {
            let handle = try FileHandle(forWritingTo: create(temporary))
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            guard rename(temporary.path, url.path) == 0 else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func create(_ url: URL) throws -> URL {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return url
    }

    /// Whether `url` stands for a file not on this device in full (an
    /// evicted or not yet downloaded iCloud Drive file); asks for its
    /// download when so. Reading such a file sees nothing, and writing it
    /// would replace content this device has not seen.
    public static func isPendingDownload(_ url: URL) -> Bool {
        let manager = FileManager.default
        var pending = manager.fileExists(atPath: placeholderURL(for: url).path)
        if !pending, manager.fileExists(atPath: url.path),
           let status = (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
        {
            pending = status != .current
        }
        if pending {
            try? manager.startDownloadingUbiquitousItem(at: url)
        }
        return pending
    }

    /// `.<name>.icloud` next to `url`, iCloud Drive's placeholder for it.
    public static func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).icloud", directoryHint: .notDirectory)
    }
}
