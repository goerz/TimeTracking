// SettingsMonitor: loads settings.toml and reloads it when it changes
// (spec_activity_tracking.md §7: applied from the next tick).

import Foundation
import os
import TimeTrackingCore

/// Watches one `settings.toml` by modification date and size, checked at
/// every tick; a file that fails to parse keeps the previous settings.
struct SettingsMonitor {
    let url: URL
    private(set) var settings: TrackerSettings
    private var stamp: Stamp?

    private struct Stamp: Equatable {
        var date: Date?
        var size: Int?
    }

    init(url: URL) {
        self.url = url
        self.settings = TrackerSettings.defaults
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
            let loaded = try TrackerSettings(contentsOf: url)
            guard loaded != settings else {
                return false
            }
            settings = loaded
            return true
        } catch {
            Logging.logger(category: "Agent").error("settings.toml: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
