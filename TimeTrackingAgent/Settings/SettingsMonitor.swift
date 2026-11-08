// SettingsMonitor: loads settings.toml and reloads it when it changes
// (activity_tracking.md §7: applied from the next tick).

import Foundation
import os
import TimeTrackingCore

/// Watches one `settings.toml` by modification date and size, checked at
/// every tick. A file that can't be read or fails to parse keeps the
/// previous settings, and so does a missing file once one was read: a file
/// that was there is most likely not listed or downloaded yet, and
/// defaults would record what the user excluded.
struct SettingsMonitor {
    let url: URL
    private(set) var settings: TrackerSettings
    /// The text of the file the settings come from; `nil` for the defaults.
    private(set) var text: String?
    /// Why the file as it is now can't be used; `nil` when it was read.
    private(set) var problem: String?
    private var stamp: Stamp?

    private struct Stamp: Equatable {
        var date: Date?
        var size: Int?
    }

    /// Starts from `lastText`, the file's text when it was last read, and reads the file.
    init(url: URL, lastText: String? = nil) {
        self.url = url
        let last = lastText.flatMap { try? TrackerSettings(tomlText: $0) }
        self.settings = last ?? TrackerSettings.defaults
        self.text = last == nil ? nil : lastText
        _ = reload()
    }

    /// Reloads if the file changed; returns whether the settings changed.
    @discardableResult
    mutating func reload() -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let current = Stamp(date: attributes?[.modificationDate] as? Date, size: attributes?[.size] as? Int)
        guard current != stamp else {
            return false
        }
        stamp = current
        do {
            let (loaded, loadedText) = try read()
            problem = nil
            text = loadedText
            guard loaded != settings else {
                return false
            }
            settings = loaded
            return true
        } catch {
            problem = error.localizedDescription
            Logging.logger(category: "Agent").error("settings.toml: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func read() throws(ActivityError) -> (TrackerSettings, String?) {
        if FileManager.default.fileExists(atPath: url.path) {
            let text: String
            do {
                text = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw .fileSystem("\(url.lastPathComponent): \(error.localizedDescription)")
            }
            return try (TrackerSettings(tomlText: text), text)
        }
        // Asks for the download of a file iCloud Drive holds as a placeholder.
        if ActivityFile.isPendingDownload(url) {
            throw .fileSystem("\(url.lastPathComponent) is not downloaded from iCloud Drive yet")
        }
        if text != nil {
            throw .fileSystem("\(url.lastPathComponent) is missing; the settings read last stay in force")
        }
        return (TrackerSettings.defaults, nil)
    }
}
