// BlockLogHeader+Keys: the legend of the line keys in a month file's first
// header (spec_activity_tracking.md §4.2, §4.3).

import Foundation

extension BlockLogHeader {
    /// The keys of a block line in line order, with their labels.
    static let blockKeyLabels: KeyValuePairs = [
        "s": "start (local time)",
        "e": "end (local time)",
        "a": "active seconds",
        "dev": "device",
        "g": "dominant group",
        "gs": "share of the dominant group",
        "items": "items [context, subject, detail, seconds]",
        "bg": "background items [context, subject, detail, seconds]",
        "src": "source (live, knowledge, or device)",
    ]

    /// The keys a detail-log line adds, in line order, with their labels.
    static let detailKeyLabels: KeyValuePairs = [
        "urls": "URL visits [time, browser, URL, title]",
        "files": "modified files [time, path]",
        "presence": "presence transitions [time, state]",
        "dwell": "Safari dwell times [time, URL, seconds]",
    ]

    /// The legend of the block log's first header.
    public static let blockLogKeys = Dictionary(uniqueKeysWithValues: blockKeyLabels.map { ($0.key, $0.value) })

    /// The legend of the detail log's first header: the block keys and the detail keys.
    public static let detailLogKeys = blockLogKeys.merging(detailKeyLabels.map { ($0.key, $0.value) }) { first, _ in first }

    /// The order the legend is written in: line order, then any other key by name.
    static func keyOrder(_ keys: [String: String]) -> [String] {
        let known = (blockKeyLabels.map(\.key) + detailKeyLabels.map(\.key)).filter { keys[$0] != nil }
        return known + keys.keys.filter { !known.contains($0) }.sorted()
    }
}
