// ActivityAway: gaps between the blocks of a day and their causes
// (activity.md §1.8).

import Foundation

/// The Away panel.
public struct ActivityAway: Sendable, Hashable {
    /// Why a gap happened: the end reason of the block before it.
    public enum Cause: String, Sendable, Hashable, CaseIterable {
        case idle
        case locked
        case asleep
        case otherUser
        case paused
        case stopped
        case unknown

        public var title: String {
            switch self {
            case .idle: "idle"
            case .locked: "locked"
            case .asleep: "asleep"
            case .otherUser: "another user"
            case .paused: "Focus"
            case .stopped: "tracker stopped"
            case .unknown: "unknown"
            }
        }

        /// The cause of a gap after a block that ended for `reason`.
        public init(endReason reason: ActivityEndReason?) {
            switch reason {
            case .idle: self = .idle
            case .locked: self = .locked
            case .asleep: self = .asleep
            case .otherUser: self = .otherUser
            case .paused: self = .paused
            case .stopped: self = .stopped
            case .split, .maxLength, nil: self = .unknown
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
    /// The part of `seconds` that background blocks cover.
    public var backgroundSeconds: Int

    public init(seconds: Int, parts: [Part], backgroundSeconds: Int = 0) {
        self.seconds = seconds
        self.parts = parts
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

    /// "idle 57m (3 times) · asleep 7h 18m (3 times)".
    public var partsText: String {
        parts.map(\.text).joined(separator: " · ")
    }
}

extension ActivitySummary {
    /// The Away panel: gaps over `idle_close` between consecutive blocks of
    /// one shown day, all devices forming one timeline, and how much of them
    /// background blocks cover; the app filter does not apply.
    public var away: ActivityAway {
        var seconds: [ActivityAway.Cause: Int] = [:]
        var counts: [ActivityAway.Cause: Int] = [:]
        var background = 0
        let idleClose = input.settings.blocks.idleClose
        for group in Dictionary(grouping: blocks.filter { !$0.isOpen }, by: shownDay).values {
            // All devices form one timeline: a gap starts at the latest end so far.
            let sorted = group.sorted { $0.start < $1.start }
            guard var previous = sorted.first else {
                continue
            }
            for next in sorted.dropFirst() {
                defer {
                    if next.end > previous.end {
                        previous = next
                    }
                }
                let gap = next.start.timeIntervalSince(previous.end)
                guard gap > idleClose else {
                    continue
                }
                let interval = DateInterval(start: previous.end, end: next.start)
                background += backgroundBlocks.reduce(0) { total, block in
                    total + max(0, Int(interval.overlapDuration(with: block.interval)))
                }
                let cause = ActivityAway.Cause(endReason: previous.endReason)
                seconds[cause, default: 0] += Int(gap)
                counts[cause, default: 0] += 1
            }
        }
        let parts = ActivityAway.Cause.allCases.compactMap { cause in
            counts[cause].map { ActivityAway.Part(cause: cause, seconds: seconds[cause] ?? 0, count: $0) }
        }
        return ActivityAway(seconds: seconds.values.reduce(0, +), parts: parts, backgroundSeconds: background)
    }
}
