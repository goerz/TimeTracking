// ActivityAway: gaps between one device's blocks of a day and their causes
// (activity.md §1.8).

public import Foundation

/// The Away panel.
public struct ActivityAway: Sendable, Hashable {
    /// Why a gap happened.
    public enum Cause: String, Sendable, Hashable, CaseIterable {
        case idle
        case asleep
        case locked
        case otherUser
        case unknown

        public var title: String {
            switch self {
            case .idle: "idle"
            case .asleep: "asleep"
            case .locked: "locked"
            case .otherUser: "another user"
            case .unknown: "unknown"
            }
        }

        init?(_ state: TrackerPresenceState) {
            switch state {
            case .idle: self = .idle
            case .asleep: self = .asleep
            case .locked: self = .locked
            case .otherUser: self = .otherUser
            case .active, .passive: return nil
            }
        }
    }

    /// The time and number of gaps of one cause.
    public struct Part: Sendable, Hashable {
        public var cause: Cause
        public var seconds: Int
        public var count: Int

        public init(cause: Cause, seconds: Int, count: Int) {
            self.cause = cause
            self.seconds = seconds
            self.count = count
        }

        /// "idle 57m (3 times)".
        public var text: String {
            "\(cause.title) \(ActivityText.duration(seconds)) (\(count) \(count == 1 ? "time" : "times"))"
        }
    }

    public var seconds: Int
    /// Causes with gaps, in the order of `Cause.allCases`.
    public var parts: [Part]
    /// Some gaps had no detail record on this device.
    public var hasUnclassified: Bool
    /// The part of `seconds` that background stretches cover.
    public var backgroundSeconds = 0

    public init(seconds: Int, parts: [Part], hasUnclassified: Bool, backgroundSeconds: Int = 0) {
        self.seconds = seconds
        self.parts = parts
        self.hasUnclassified = hasUnclassified
        self.backgroundSeconds = backgroundSeconds
    }

    /// "4h 12m during the day".
    public var totalText: String {
        "\(ActivityText.duration(seconds)) during the day"
    }

    /// "Work went on in the background for 38m of it.", or `nil` without.
    public var backgroundText: String? {
        backgroundSeconds > 0 ? "Work went on in the background for \(ActivityText.duration(backgroundSeconds)) of it." : nil
    }

    /// "idle 57m (3 times) · asleep 7h 18m (3 times)", plus "(cause known
    /// only on the Mac that recorded it)".
    public var partsText: String {
        let text = parts.map(\.text).joined(separator: " · ")
        return hasUnclassified ? text + " (cause known only on the Mac that recorded it)" : text
    }
}

extension ActivitySummary {
    /// The Away panel: gaps over `idleClose` between consecutive blocks of
    /// one day, and how much of them background stretches cover; the
    /// context filter does not apply.
    public var away: ActivityAway {
        var seconds: [ActivityAway.Cause: Int] = [:]
        var counts: [ActivityAway.Cause: Int] = [:]
        var unclassified = false
        var background = 0
        let groups = Dictionary(grouping: blocks.filter { !$0.isOpen }) { $0.shownDay }
        for group in groups.values {
            let sorted = group.sorted { $0.start < $1.start }
            for (previous, next) in zip(sorted, sorted.dropFirst()) {
                let gap = next.start.timeIntervalSince(previous.end)
                guard gap > input.idleClose else {
                    continue
                }
                let details = [input.details[previous.id], input.details[next.id]].compactMap(\.self)
                if details.isEmpty {
                    unclassified = true
                }
                let interval = DateInterval(start: previous.end, end: next.start)
                background += stretches.reduce(0) { total, stretch in
                    let overlap = min(stretch.end, interval.end).timeIntervalSince(max(stretch.start, interval.start))
                    return total + max(0, Int(overlap))
                }
                let cause = Self.cause(of: interval, details: details, idleClose: input.idleClose)
                seconds[cause, default: 0] += Int(gap)
                counts[cause, default: 0] += 1
            }
        }
        let parts = ActivityAway.Cause.allCases.compactMap { cause in
            counts[cause].map { ActivityAway.Part(cause: cause, seconds: seconds[cause] ?? 0, count: $0) }
        }
        return ActivityAway(
            seconds: seconds.values.reduce(0, +),
            parts: parts,
            hasUnclassified: unclassified,
            backgroundSeconds: background
        )
    }

    /// The first absence transition near the gap's start, else unknown.
    public static func cause(of gap: DateInterval, details: [ActivityBlockDetail], idleClose: TimeInterval) -> ActivityAway.Cause {
        let transitions = details.flatMap(\.presence)
            .filter { $0.time >= gap.start - idleClose && $0.time < gap.end }
            .sorted { abs($0.time.timeIntervalSince(gap.start)) < abs($1.time.timeIntervalSince(gap.start)) }
        return transitions.lazy.compactMap { ActivityAway.Cause($0.state) }.first ?? .unknown
    }
}
