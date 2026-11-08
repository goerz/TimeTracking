// ActivityBlock: a foreground or background block of the block log
// (activity_tracking.md §2.2, §4.2; data_and_sync.md §6).

public import Foundation

/// A stretch of attention with the items it credits, or, without foreground
/// items, a background block between foreground blocks.
///
/// Times keep the UTC offsets they were written with, so a block's local
/// date and hours don't depend on the reader's zone. Totals are computed
/// from the items, never stored.
public struct ActivityBlock: Sendable, Hashable, Identifiable {
    public var start: Date
    public var end: Date
    /// Seconds east of UTC of `start` as written (`s`).
    public var utcOffset: Int
    /// Seconds east of UTC of `end` as written (`e`).
    public var endUTCOffset: Int
    /// Why the block ended; `nil` while open, or when converted data doesn't say.
    public var endReason: ActivityEndReason?
    /// The part of the credited time rebuilt from macOS app usage history.
    public var reconstructedSeconds: Int
    public var foreground: [ActivityBlockItem]
    public var background: [ActivityBlockItem]
    /// The open block of `current.json`, not yet in a date file.
    public var isOpen: Bool

    public init(
        start: Date,
        end: Date,
        utcOffset: Int,
        endUTCOffset: Int? = nil,
        endReason: ActivityEndReason? = nil,
        reconstructedSeconds: Int = 0,
        foreground: [ActivityBlockItem] = [],
        background: [ActivityBlockItem] = [],
        isOpen: Bool = false
    ) {
        self.start = start
        self.end = end
        self.utcOffset = utcOffset
        self.endUTCOffset = endUTCOffset ?? utcOffset
        self.endReason = endReason
        self.reconstructedSeconds = reconstructedSeconds
        self.foreground = foreground
        self.background = background
        self.isOpen = isOpen
    }

    /// The start as written, `2026-11-07T09:52:00-05:00`; it identifies the block.
    public var id: String {
        ActivityTimestamp.textWithOffset(start, utcOffset: utcOffset)
    }

    /// The local date the block starts on, which names its date file.
    public var day: TrackingDay {
        TrackingDay(ActivityTimestamp.day(start, utcOffset: utcOffset)) ?? TrackingDay(year: 1970, month: 1, day: 1)
    }

    /// The day the app shows and counts the block on, with days starting at
    /// `startOfDayHour`: the shown day of its start, whole.
    public func shownDay(startOfDayHour: Int) -> TrackingDay {
        guard startOfDayHour != 0, let zone = TimeZone(secondsFromGMT: utcOffset) else {
            return day
        }
        return TrackingCalendar(timeZone: zone, startOfDayHour: startOfDayHour).day(containing: start)
    }

    public var interval: DateInterval {
        DateInterval(start: start, end: max(start, end))
    }

    /// Whether the block has only background items.
    public var isBackgroundBlock: Bool {
        foreground.isEmpty
    }

    /// The active time: the sum of the foreground seconds.
    public var activeSeconds: Int {
        foreground.reduce(0) { $0 + $1.seconds }
    }

    /// Whether more than half of the active time was rebuilt from app usage history.
    public var isMostlyReconstructed: Bool {
        reconstructedSeconds * 2 > activeSeconds
    }

    /// The foreground seconds per device, the most first, then by name.
    public var devices: [(name: String, seconds: Int)] {
        Self.totals(of: foreground, by: \.device)
    }

    /// The workspace with the most foreground seconds and its share of the
    /// active time; `nil` for a background block.
    public var dominantWorkspace: (workspace: String, share: Double)? {
        guard let top = Self.totals(of: foreground, by: \.item.workspace).first, activeSeconds > 0 else {
            return nil
        }
        return (top.name, Double(top.seconds) / Double(activeSeconds))
    }

    /// The foreground item with the most seconds.
    public var dominantItem: ActivityBlockItem? {
        foreground.enumerated().max { lhs, rhs in
            lhs.element.seconds == rhs.element.seconds ? lhs.offset > rhs.offset : lhs.element.seconds < rhs.element.seconds
        }?.element
    }

    /// The block's part on `devices`: only their items, or `nil` when it
    /// has none there. `nil` devices keeps every device, which an empty
    /// set cannot express.
    public func part(on devices: Set<String>?) -> Self? { // swiftlint:disable:this discouraged_optional_collection
        guard let devices else {
            return self
        }
        var result = self
        result.foreground = foreground.filter { devices.contains($0.device) }
        result.background = background.filter { devices.contains($0.device) }
        guard !result.foreground.isEmpty || (isBackgroundBlock && !result.background.isEmpty) else {
            return nil
        }
        // Only the Mac's time is reconstructed; the part can't hold more than it credits.
        result.reconstructedSeconds = min(reconstructedSeconds, result.activeSeconds)
        return result
    }

    /// Seconds per key, the most first, then by key.
    static func totals(of items: [ActivityBlockItem], by key: KeyPath<ActivityBlockItem, String>) -> [(name: String, seconds: Int)] {
        var seconds: [String: Int] = [:]
        for item in items {
            seconds[item[keyPath: key], default: 0] += item.seconds
        }
        return seconds.map { (name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds == $1.seconds ? $0.name < $1.name : $0.seconds > $1.seconds }
    }
}
