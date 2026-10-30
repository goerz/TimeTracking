// BrowserHistory: Safari's and Chromium's history databases, read from
// copies (spec_activity_tracking.md §2.3 `history`, §3.3, §6.1).

// The seams answer nil for "cannot read", which differs from an empty answer.
// swiftlint:disable discouraged_optional_collection discouraged_optional_boolean

import Foundation

/// A visit from a browser history.
nonisolated struct HistoryVisit: Hashable, Sendable {
    var time: Date
    /// The browser context, e.g. `safari` or `chrome`.
    var browser: String
    var url: String
    var title: String
}

/// The tabs one device shows in Safari's `CloudTabs.db`.
nonisolated struct CloudTabDevice: Hashable, Sendable {
    var name: String
    var urls: Set<String>
}

/// Reads browser histories. Every method works on copies, never the live files.
protocol BrowserHistory {
    /// Whether Safari's `History.db` can be read (Full Disk Access).
    var canReadSafari: Bool { get }
    /// Safari visits in `[from, to]` with `origin` (0 this Mac, 1 synced);
    /// `nil` when the database cannot be read.
    func safariVisits(from: Date, to: Date, origin: Int) -> [HistoryVisit]?
    /// Whether Safari has a visit of `url` at or after `since`; `nil` when unreadable.
    func hasSafariVisit(url: String, since: Date) -> Bool?
    /// Visits of every Chromium profile in `[from, to]`.
    func chromiumVisits(from: Date, to: Date) -> [HistoryVisit]
    /// The devices of `CloudTabs.db` and their tab URLs; `nil` when unreadable.
    func cloudTabs() -> [CloudTabDevice]?
}

// swiftlint:enable discouraged_optional_collection discouraged_optional_boolean
