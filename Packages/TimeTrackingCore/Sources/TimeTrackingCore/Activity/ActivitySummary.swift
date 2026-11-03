// ActivitySummary: every figure of the Activity section for a range, a
// device, and a context filter (spec_activity.md §1). Pure: built
// from blocks the reader returned (exclusions applied) and, on the
// recording Mac, their details.

public import Foundation

/// What a summary is built from.
public struct ActivitySummaryInput: Sendable {
    /// The blocks of every device in the range, exclusions applied.
    public var blocks: [ActivityBlock]
    /// The background stretches in the range, exclusions applied.
    public var stretches: [ActivityBackgroundStretch]
    /// The shown days (at most 366).
    public var days: ClosedRange<TrackingDay>
    public var today: TrackingDay
    /// The selected contexts; empty means All.
    public var contexts: Set<String>
    /// The device of the "All devices" popup, or `nil` for all.
    public var device: String?
    /// The detail records found on this Mac, by block id.
    public var details: [ActivityBlock.ID: ActivityBlockDetail]
    /// The tracker's `idle_close` (away gaps are longer).
    public var idleClose: TimeInterval
    /// The current exclusions (`private_domains` hide details).
    public var exclusions: ExclusionRules?

    public init(
        blocks: [ActivityBlock],
        days: ClosedRange<TrackingDay>,
        today: TrackingDay,
        contexts: Set<String> = [],
        device: String? = nil,
        details: [ActivityBlock.ID: ActivityBlockDetail] = [:],
        idleClose: TimeInterval = 300,
        exclusions: ExclusionRules? = nil,
        stretches: [ActivityBackgroundStretch] = []
    ) {
        self.blocks = blocks
        self.stretches = stretches
        self.days = days
        self.today = today
        self.contexts = contexts
        self.device = device
        self.details = details
        self.idleClose = idleClose
        self.exclusions = exclusions
    }
}

/// The figures of the Activity section.
public struct ActivitySummary: Sendable {
    public let input: ActivitySummaryInput
    /// The blocks of the range narrowed to the device, by start.
    public let blocks: [ActivityBlock]
    /// The background stretches of the range narrowed to the device, by start.
    public let stretches: [ActivityBackgroundStretch]
    /// The header total: the sum of `a`, or the selected contexts' item seconds.
    public let total: Int
    /// The sum of `a` without the context filter (shares are relative to it).
    public let unfilteredTotal: Int
    /// Days with time under the filter.
    public let activeDays: Int
    /// Totals per device (unfiltered by device), largest first; empty with one device.
    public let deviceTotals: [DeviceTotal]
    /// Every device of the range with its total, for the device popup.
    public let devices: [DeviceTotal]
    /// Every context of the range by item seconds, largest first (the chips).
    public let ranking: [ContextTotal]

    /// A device and its time.
    public struct DeviceTotal: Sendable, Hashable, Identifiable {
        public var device: String
        public var seconds: Int

        public init(device: String, seconds: Int) {
            self.device = device
            self.seconds = seconds
        }

        public var id: String {
            device
        }

        /// The header's name: `remote` reads "Other devices (Safari)".
        public var displayName: String {
            ActivityContext.deviceName(device)
        }
    }

    /// A context and its item seconds.
    public struct ContextTotal: Sendable, Hashable, Identifiable {
        public var context: String
        public var seconds: Int

        public init(context: String, seconds: Int) {
            self.context = context
            self.seconds = seconds
        }

        public var id: String {
            context
        }
    }

    public init(_ input: ActivitySummaryInput) {
        self.input = input
        let inRange = input.blocks.filter { block in
            TrackingDay(block.localDay).map { input.days.contains($0) } ?? false
        }
        let blocks = inRange.compactMap { block in input.device.map { block.restricted(to: [$0]) } ?? block }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        self.blocks = blocks
        self.stretches = input.stretches
            .filter { TrackingDay($0.localDay).map { input.days.contains($0) } ?? false }
            .compactMap { $0.part(on: input.device.map { [$0] }) }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        let value = Self.valueFunction(contexts: input.contexts)
        self.total = blocks.reduce(0) { $0 + value($1) }
        self.unfilteredTotal = blocks.reduce(0) { $0 + $1.activeSeconds }
        self.activeDays = Set(blocks.filter { value($0) > 0 }.map(\.localDay)).count
        let perDevice = inRange.reduce(into: [String: Int]()) { totals, block in
            for device in block.deviceNames {
                totals[device, default: 0] += block.restricted(to: [device]).map(value) ?? 0
            }
        }
        let devices = perDevice.map { DeviceTotal(device: $0.key, seconds: $0.value) }
            .sorted { ($1.seconds, $0.device) < ($0.seconds, $1.device) }
        self.devices = devices
        self.deviceTotals = devices.count > 1 ? devices : []
        self.ranking = Self.rank(blocks.flatMap(\.items))
    }

    /// The per-block value under a filter: `a`, or the selected item seconds.
    static func valueFunction(contexts: Set<String>) -> @Sendable (ActivityBlock) -> Int {
        if contexts.isEmpty {
            return \.activeSeconds
        }
        return { block in block.items.filter { contexts.contains($0.context) }.reduce(0) { $0 + $1.seconds } }
    }

    /// The items of `block` the filter selects.
    func selectedItems(_ block: ActivityBlock) -> [ActivityItem] {
        input.contexts.isEmpty ? block.items : block.items.filter { input.contexts.contains($0.context) }
    }

    func value(_ block: ActivityBlock) -> Int {
        Self.valueFunction(contexts: input.contexts)(block)
    }

    static func rank(_ items: [ActivityItem]) -> [ContextTotal] {
        items.reduce(into: [String: Int]()) { $0[$1.context, default: 0] += $1.seconds }
            .map { ContextTotal(context: $0.key, seconds: $0.value) }
            .sorted { ($1.seconds, $0.context) < ($0.seconds, $1.context) }
    }

    /// The average per day with time (the header's second figure).
    public var averagePerActiveDay: Int {
        activeDays == 0 ? 0 : total / activeDays
    }

    /// Whether the range has blocks for the device (before the context filter).
    public var hasBlocks: Bool {
        !blocks.isEmpty
    }

    /// Whether the filter leaves anything.
    public var hasFilteredTime: Bool {
        total > 0 || blocks.contains { !selectedItems($0).isEmpty }
    }

    /// The days of the range not after today (averages count only these).
    public var pastDays: [TrackingDay] {
        Self.days(input.days).filter { $0 <= input.today }
    }

    /// The header's second line: days, average, device totals.
    public var headerDetail: String {
        var parts = ["\(activeDays) \(activeDays == 1 ? "day" : "days") with activity"]
        parts.append("\(ActivityText.duration(averagePerActiveDay)) per day")
        parts += deviceTotals.map { "\($0.displayName) \(ActivityText.duration($0.seconds))" }
        return parts.joined(separator: " · ")
    }

    /// Every day of `range`.
    public static func days(_ range: ClosedRange<TrackingDay>) -> [TrackingDay] {
        (0 ... range.lowerBound.distance(to: range.upperBound)).map { range.lowerBound.adding(days: $0) }
    }
}
