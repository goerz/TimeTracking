// HomePaths: paths written with `~` for the home folder, as Items keep them
// (activity_tracking.md §2.3).

import Foundation
import TimeTrackingCore

/// Converts between absolute paths and `~` paths for one home folder.
nonisolated struct HomePaths: Hashable, Sendable {
    var home: String

    init(home: String) {
        self.home = home.count > 1 && home.hasSuffix("/") ? String(home.dropLast()) : home
    }

    /// `path` with the home folder written `~`; a `file://` URL becomes a path.
    func tilde(_ path: String) -> String {
        let plain = Self.plain(path)
        guard home.count > 1 else {
            return plain
        }
        if plain == home {
            return "~"
        }
        return plain.hasPrefix(home + "/") ? "~" + plain.dropFirst(home.count) : plain
    }

    /// `item` with the document at `path` (a path or `file://` URL): the
    /// document and, as its location, its folder (§2.3).
    func withDocument(_ path: String, in item: ActivityItem) -> ActivityItem {
        let plain = Self.plain(path)
        var result = item
        result.documents = [tilde(plain)]
        result.location = tilde(PathText.parent(plain))
        return result
    }

    /// `path` with `~` expanded.
    func expand(_ path: String) -> String {
        if path == "~" {
            return home
        }
        return path.hasPrefix("~/") ? home + path.dropFirst() : Self.plain(path)
    }

    /// A path from a `file://` URL or a plain path, without a trailing slash.
    static func plain(_ text: String) -> String {
        var path = text
        if text.lowercased().hasPrefix("file://"), let url = URL(string: text) {
            path = url.path(percentEncoded: false)
        }
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
