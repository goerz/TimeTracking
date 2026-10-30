// BlockSummary: the summary of a closed or open block
// (spec_activity_tracking.md §2.7).

import Foundation
import TimeTrackingCore

/// The summary of a block's segments:
///
/// 1. Seconds summed per primary item.
/// 2. Items sharing context and subject merged when they have more than
///    three details (`nvim (5 files)`).
/// 3. Items under `summary_min_share` or under 60 s dropped, except the top
///    item of every group key present for at least 3 minutes.
/// 4. Ordered by first appearance, capped at `summary_lines`.
/// 5. Secondaries that ran at least 5 minutes appended as `bg`.
/// 6. The dominant group key and its share.
nonisolated struct BlockSummary {
    static let mergeAbove = 3
    static let minimumSeconds = 60
    static let groupKeepSeconds = 180
    static let backgroundSeconds = 300

    /// The cut items of the block log.
    var items: [ActivityItem]
    /// Every item, for the detail log.
    var detailItems: [ActivityItem]
    var background: [ActivityItem]
    var activeSeconds: Int
    var groupKey: String
    var groupShare: Double

    init(segments: [Blocker.Segment], background: [Blocker.Segment], settings: TrackerBlockSettings) {
        let summed = Self.sum(segments)
        let total = summed.reduce(0) { $0 + $1.seconds }
        self.detailItems = summed.map(\.activityItem)
        self.activeSeconds = total
        var groups: [String: Int] = [:]
        var groupOrder: [String] = []
        for entry in summed {
            if groups[entry.groupKey] == nil {
                groupOrder.append(entry.groupKey)
            }
            groups[entry.groupKey, default: 0] += entry.seconds
        }
        let dominant = groupOrder.max { groups[$0, default: 0] < groups[$1, default: 0] } ?? ""
        self.groupKey = dominant
        self.groupShare = total > 0 ? (Double(groups[dominant, default: 0]) / Double(total) * 100).rounded() / 100 : 0
        let merged = Self.merge(summed)
        var kept = merged.filter { entry in
            entry.seconds >= Self.minimumSeconds && (total == 0 || Double(entry.seconds) / Double(total) >= settings.summaryMinShare)
        }
        for key in groupOrder where groups[key, default: 0] >= Self.groupKeepSeconds {
            let members = merged.filter { $0.groupKey == key }
            if let top = members.max(by: { $0.seconds < $1.seconds }), !kept.contains(top) {
                kept.append(top)
            }
        }
        kept.sort { $0.first < $1.first }
        self.items = Array(kept.prefix(max(0, settings.summaryLines))).map(\.activityItem)
        self.background = Self.sum(background).filter { $0.seconds >= Self.backgroundSeconds }.map(\.activityItem)
    }

    /// Seconds per item, in order of first appearance.
    private static func sum(_ segments: [Blocker.Segment]) -> [Entry] {
        var entries: [Entry] = []
        var index: [ItemKey: Int] = [:]
        for segment in segments {
            if let position = index[segment.item.key] {
                entries[position].seconds += segment.seconds
            } else {
                index[segment.item.key] = entries.count
                entries.append(Entry(
                    key: segment.item.key,
                    groupKey: segment.item.groupKey,
                    seconds: segment.seconds,
                    first: segment.start
                ))
            }
        }
        return entries
    }

    /// Merges the items of a context and subject with more than three details.
    private static func merge(_ entries: [Entry]) -> [Entry] {
        var result: [Entry] = []
        var handled = Set<String>()
        for entry in entries {
            let group = "\(entry.key.context)\u{1F}\(entry.key.subject)"
            guard !handled.contains(group) else {
                continue
            }
            let members = entries.filter { $0.key.context == entry.key.context && $0.key.subject == entry.key.subject }
            guard members.count > Self.mergeAbove else {
                result.append(entry)
                continue
            }
            handled.insert(group)
            var combined = entry
            combined.key.detail = mergedDetail(members.map(\.key.detail))
            combined.seconds = members.reduce(0) { $0 + $1.seconds }
            combined.first = members.map(\.first).min() ?? entry.first
            result.append(combined)
        }
        return result
    }

    /// `nvim (5 files)` when the details share their program, else `(5 items)`.
    static func mergedDetail(_ details: [String]) -> String {
        let programs = Set(details.map { $0.split(separator: " ", maxSplits: 1).first.map(String.init) ?? "" })
        if programs.count == 1, let program = programs.first, !program.isEmpty, details.allSatisfy({ $0.contains(" ") }) {
            return "\(program) (\(details.count) files)"
        }
        return "(\(details.count) items)"
    }

    private struct Entry: Hashable {
        var key: ItemKey
        var groupKey: String
        var seconds: Int
        var first: Date

        var activityItem: ActivityItem {
            ActivityItem(context: key.context, subject: key.subject, detail: key.detail, seconds: seconds)
        }
    }
}
