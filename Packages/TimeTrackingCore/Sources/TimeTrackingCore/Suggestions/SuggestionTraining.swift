// SuggestionTraining: examples from past entries and the activity during
// them (spec_planner_calendar.md §5.1).

public import Foundation

/// A calendar event's or time block's title and interval (the `k:` feature).
public struct SuggestionCalendarTitle: Sendable, Hashable, Codable {
    public var title: String
    public var interval: DateInterval

    public init(title: String, interval: DateInterval) {
        self.title = title
        self.interval = interval
    }

    /// The title covering at least half of `interval`, the largest overlap first.
    public static func covering(_ interval: DateInterval, in titles: [Self]) -> String? {
        titles.map { title in
            (title.title, min(title.interval.end, interval.end).timeIntervalSince(max(title.interval.start, interval.start)))
        }
        .filter { $0.1 > 0 && $0.1 * 2 >= interval.duration }
        .max { ($0.1, $1.0) < ($1.1, $0.0) }?.0
    }
}

/// Builds the model's examples.
public enum SuggestionTraining {
    /// The minimum example length.
    public static let minimumSeconds: TimeInterval = 120
    /// The minimum overlap of a block with an entry.
    public static let minimumOverlap: TimeInterval = 60

    /// One example per stopped entry of the last `trainDays` with a project
    /// or task and at least 2 minutes long; its activity is the blocks
    /// overlapping it by at least 60 seconds, weighted by the share of each
    /// block the entry overlaps. Examples of accepted suggestions weigh 2.
    public static func examples( // swiftlint:disable:this function_parameter_count
        entries: [TimeEntry],
        blocks: [ActivityBlock],
        titles: [SuggestionCalendarTitle],
        feedback: [SuggestionFeedback],
        now: Date,
        trainDays: Int,
        timeZone: TimeZone
    ) -> [SuggestionExample] {
        let cutoff = now - Double(trainDays) * 86_400
        let accepted = Set(feedback.filter { $0.outcome == .accepted && $0.deletedAt == nil }.compactMap(\.entryID))
        let sorted = entries.filter { !$0.isDeleted && $0.end != nil }.sorted { ($0.start, $0.id.rawValue) < ($1.start, $1.id.rawValue) }
        let sortedBlocks = blocks.filter { !$0.isOpen }.sorted { $0.start < $1.start }
        let longest = sortedBlocks.map { $0.end.timeIntervalSince($0.start) }.max() ?? 0
        var previousByDay: [TrackingDay: ProjectID?] = [:]
        var result: [SuggestionExample] = []
        for entry in sorted {
            let end = entry.end ?? now
            defer { previousByDay[entry.day] = .some(entry.projectID) }
            let interval = DateInterval(start: entry.start, end: max(entry.start, end))
            guard entry.start >= cutoff, interval.duration >= minimumSeconds, entry.projectID != nil || !entry.task.trimmed.isEmpty else {
                continue
            }
            let overlapping = Self.overlapping(interval, in: sortedBlocks, longest: longest)
            let (items, groupKeys) = SuggestionFeatures.activity(of: overlapping, during: interval)
            let previous = previousByDay[entry.day]
            let features = SuggestionFeatures(
                items: items,
                groupKeys: groupKeys,
                title: SuggestionCalendarTitle.covering(interval, in: titles),
                interval: interval,
                previousProject: previous.flatMap(\.self),
                previousKnown: previous != nil,
                timeZone: timeZone
            )
            result.append(SuggestionExample(
                entryID: entry.id,
                projectID: entry.projectID,
                task: entry.task.trimmed,
                features: features,
                weight: accepted.contains(entry.id) ? 2 : 1
            ))
        }
        return result
    }

    /// The blocks overlapping `interval` by at least a minute (binary search
    /// over blocks sorted by start).
    static func overlapping(_ interval: DateInterval, in sorted: [ActivityBlock], longest: TimeInterval) -> [ActivityBlock] {
        let earliest = interval.start - longest
        var low = 0
        var high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if sorted[middle].start < earliest {
                low = middle + 1
            } else {
                high = middle
            }
        }
        var result: [ActivityBlock] = []
        var index = low
        while index < sorted.count, sorted[index].start < interval.end {
            let block = sorted[index]
            if min(block.end, interval.end).timeIntervalSince(max(block.start, interval.start)) >= minimumOverlap {
                result.append(block)
            }
            index += 1
        }
        return result
    }
}
