// BlockLogOwner: the one Mac that writes the block log, named in
// `blocks/owner` (activity_tracking.md §4.1).

public import Foundation

/// `blocks/owner` holds the hardware UUID of the Mac that records. "Enable
/// Tracker" and "Record on This Mac" write it, so the Mac enabled last
/// takes over; without the file, the first agent to write claims it.
public enum BlockLogOwner {
    /// The owner file of `log`.
    public static func url(in log: BlockLogFolder) -> URL {
        log.url.appending(path: "owner", directoryHint: .notDirectory)
    }

    /// The recording Mac's id; `nil` without an owner file. Throws while
    /// the file can't be read, which is not the same as no owner.
    public static func owner(of log: BlockLogFolder) throws -> String? {
        let url = url(in: log)
        if ActivityFile.isPendingDownload(url) {
            throw ActivityError.fileSystem("blocks/owner is not downloaded from iCloud Drive yet")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let owner = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        return owner.isEmpty ? nil : owner
    }

    /// Makes `deviceID` the recording Mac.
    public static func claim(_ log: BlockLogFolder, for deviceID: String) throws {
        try ActivityFile.write(Data((deviceID + "\n").utf8), to: url(in: log), coordinated: log.isUbiquitous)
    }

    /// Whether `deviceID` may write the date files: it owns them, or no
    /// Mac does yet and it claims them now (only with `claiming`: an agent
    /// that can't write the shared folder reads the owner file but leaves
    /// claiming to the Mac app). Throws while the owner file can't be
    /// read: no write then, and no claim over another Mac's.
    public static func mayWrite(_ log: BlockLogFolder, deviceID: String, claiming: Bool = true) throws -> Bool {
        if let owner = try owner(of: log) {
            return owner == deviceID
        }
        if claiming {
            try claim(log, for: deviceID)
        }
        return true
    }

    /// The `shared_folder` reason of a Mac that doesn't record.
    public static let otherMacReason = "Another Mac records activity; choose Record on This Mac to record here"
}
