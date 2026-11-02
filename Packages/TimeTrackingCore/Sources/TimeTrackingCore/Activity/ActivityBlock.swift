// ActivityBlock: a closed (or today's open) block of activity
// (spec_data_and_sync.md §6, spec_activity_tracking.md §2.6 to §2.8, §4.2).

public import Foundation

/// A block of the block log: a stretch of the user's attention on the Mac,
/// an iPhone or iPad, or in synced Safari history, possibly several.
///
/// A block lies on one local date (the tracker closes blocks at midnight),
/// and no two blocks share time. `utcOffset` is the offset of the header
/// `tz` in effect when it was written, so its local hour and date do not
/// depend on the reader's zone.
public struct ActivityBlock: Sendable, Hashable, Identifiable {
    /// The start as RFC 3339 with offset, e.g. `2026-10-28T09:10:00-04:00`.
    public var id: String
    public var start: Date
    public var end: Date
    /// The active seconds, the sum of item seconds before the summary cut.
    public var activeSeconds: Int
    /// The active seconds per device, most first.
    public var devices: [ActivityDeviceTime]
    /// The active seconds reconstructed from the Mac's app usage history.
    public var reconstructedSeconds: Int
    /// The dominant group key and its share.
    public var groupKey: String
    public var groupShare: Double
    /// The summary items and the secondaries (`bg`).
    public var items: [ActivityItem]
    public var background: [ActivityItem]
    /// Today's provisional block from `current.json`.
    public var isOpen: Bool
    /// Seconds east of UTC of the local times, from the header `tz`.
    public var utcOffset: Int

    public init(
        start: Date,
        end: Date,
        activeSeconds: Int,
        devices: [ActivityDeviceTime],
        groupKey: String,
        groupShare: Double,
        items: [ActivityItem],
        utcOffset: Int,
        background: [ActivityItem] = [],
        reconstructedSeconds: Int = 0,
        isOpen: Bool = false
    ) {
        self.id = Self.makeID(start: start, utcOffset: utcOffset)
        self.start = start
        self.end = end
        self.activeSeconds = activeSeconds
        self.devices = devices
        self.reconstructedSeconds = reconstructedSeconds
        self.groupKey = groupKey
        self.groupShare = groupShare
        self.items = items
        self.background = background
        self.isOpen = isOpen
        self.utcOffset = utcOffset
    }

    /// The id of the block starting at `start`, written with `utcOffset`.
    public static func makeID(start: Date, utcOffset: Int) -> String {
        "\(LocalTimestamp(date: start, utcOffset: utcOffset).text)\(LocalTimestamp.offsetText(utcOffset))"
    }

    /// The local date of the block, `YYYY-MM-DD`.
    public var localDay: String {
        LocalTimestamp(date: start, utcOffset: utcOffset).dayKey
    }

    /// The month file the block belongs to, `YYYY-MM`.
    public var month: String {
        LocalTimestamp(date: start, utcOffset: utcOffset).monthKey
    }

    /// Every context the block mentions, items first.
    public var contexts: [String] {
        var seen = Set<String>()
        return (items + background).map(\.context).filter { seen.insert($0).inserted }
    }

    /// The device names, most time first.
    public var deviceNames: [String] {
        devices.map(\.name)
    }

    /// Whether most of the active time was reconstructed from the Mac's
    /// app usage history rather than observed.
    public var isMostlyReconstructed: Bool {
        reconstructedSeconds * 2 > activeSeconds
    }

    /// The part of the block spent on `names`: their items, secondaries,
    /// and active time, or `nil` when the block spent no time on them.
    public func restricted(to names: Set<String>) -> Self? {
        let kept = devices.filter { names.contains($0.name) }
        guard !kept.isEmpty else {
            return nil
        }
        guard kept.count < devices.count else {
            return self
        }
        var result = self
        result.devices = kept
        result.activeSeconds = kept.reduce(0) { $0 + $1.seconds }
        result.items = items.filter { names.contains($0.device) }
        result.background = background.filter { names.contains($0.device) }
        // Only the recording Mac's time is ever reconstructed.
        result.reconstructedSeconds = kept.contains(where: \.isRecordingMac) ? reconstructedSeconds : 0
        return result
    }
}
