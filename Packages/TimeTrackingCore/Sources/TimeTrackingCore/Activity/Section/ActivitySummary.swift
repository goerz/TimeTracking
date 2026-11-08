// ActivitySummary: every figure of the Activity section for a range, a
// device, and an app filter (activity.md §1). Pure: built from the blocks
// the reader returned, exclusions applied.

import Foundation

/// What a summary is built from.
public struct ActivitySummaryInput: Sendable {
    /// The foreground blocks of every device in the range, exclusions applied.
    public var blocks: [ActivityBlock]
    /// The background blocks in the range, exclusions applied.
    public var backgroundBlocks: [ActivityBlock]
    /// The shown days (at most 366).
    public var days: ClosedRange<TrackingDay>
    public var today: TrackingDay
    /// The selected apps, by the items' `app`; empty means All.
    public var apps: Set<String>
    /// The device of the "All devices" popup, or `nil` for all.
    public var device: String?
    /// The hour shown days start at.
    public var startOfDayHour: Int
    /// The tracker settings: `idle_close` for the Away panel, `job_commands`
    /// for background labels, and the exclusions (`private_domains` hide items).
    public var settings: TrackerSettings
    public var exclusions: ExclusionRules?

    public init(
        blocks: [ActivityBlock],
        backgroundBlocks: [ActivityBlock] = [],
        days: ClosedRange<TrackingDay>,
        today: TrackingDay,
        apps: Set<String> = [],
        device: String? = nil,
        startOfDayHour: Int = 0,
        settings: TrackerSettings = .defaults,
        exclusions: ExclusionRules? = nil
    ) {
        self.blocks = blocks
        self.backgroundBlocks = backgroundBlocks
        self.days = days
        self.today = today
        self.apps = apps
        self.device = device
        self.startOfDayHour = startOfDayHour
        self.settings = settings
        self.exclusions = exclusions
    }
}

/// The figures of the Activity section.
public struct ActivitySummary: Sendable {
    public let input: ActivitySummaryInput
    /// The blocks of the range narrowed to the device, by start.
    public let blocks: [ActivityBlock]
    /// The background blocks of the range narrowed to the device, by start.
    public let backgroundBlocks: [ActivityBlock]
    /// The header total: the active time, or the selected apps' item seconds.
    public let total: Int
    /// The active time without the app filter (shares are relative to it).
    public let unfilteredTotal: Int
    /// Days with time under the filter.
    public let activeDays: Int
    /// Totals per device (unfiltered by device), largest first; empty with one device.
    public let deviceTotals: [DeviceTotal]
    /// Every device of the range with its total, for the device popup.
    public let devices: [DeviceTotal]
    /// Every app of the range by item seconds, largest first (the chips).
    public let ranking: [AppTotal]

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
            ActivityDeviceName.display(device)
        }
    }

    /// An app, its bundle identifier and kind, and its item seconds.
    public struct AppTotal: Sendable, Hashable, Identifiable {
        public var app: String
        /// The first appID its items have; empty for converted data without one.
        public var appID: String
        public var kind: ActivityAppKind
        public var seconds: Int

        public init(app: String, appID: String = "", kind: ActivityAppKind, seconds: Int) {
            self.app = app
            self.appID = appID
            self.kind = kind
            self.seconds = seconds
        }

        public var id: String {
            app
        }
    }

    public init(_ input: ActivitySummaryInput) {
        self.input = input
        let inRange = input.blocks.filter { input.days.contains($0.shownDay(startOfDayHour: input.startOfDayHour)) }
        let device = input.device.map { Set([$0]) }
        let blocks = inRange.compactMap { $0.part(on: device) }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        self.blocks = blocks
        self.backgroundBlocks = input.backgroundBlocks
            .filter { input.days.contains($0.shownDay(startOfDayHour: input.startOfDayHour)) }
            .compactMap { $0.part(on: device) }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        let value = Self.valueFunction(apps: input.apps)
        self.total = blocks.reduce(0) { $0 + value($1) }
        self.unfilteredTotal = blocks.reduce(0) { $0 + $1.activeSeconds }
        self.activeDays = Set(blocks.filter { value($0) > 0 }.map { $0.shownDay(startOfDayHour: input.startOfDayHour) }).count
        var perDevice: [String: Int] = [:]
        for block in inRange {
            for item in block.foreground where input.apps.isEmpty || input.apps.contains(item.item.appName) {
                perDevice[item.device, default: 0] += item.seconds
            }
        }
        let devices = perDevice.map { DeviceTotal(device: $0.key, seconds: $0.value) }
            .sorted { ($1.seconds, $0.device) < ($0.seconds, $1.device) }
        self.devices = devices
        self.deviceTotals = devices.count > 1 ? devices : []
        self.ranking = Self.rank(blocks.flatMap(\.foreground))
    }

    /// The per-block value under a filter: the active time, or the selected
    /// apps' item seconds.
    static func valueFunction(apps: Set<String>) -> @Sendable (ActivityBlock) -> Int {
        if apps.isEmpty {
            return \.activeSeconds
        }
        return { block in block.foreground.filter { apps.contains($0.item.appName) }.reduce(0) { $0 + $1.seconds } }
    }

    /// The foreground items of `block` the filter selects.
    func selectedItems(_ block: ActivityBlock) -> [ActivityBlockItem] {
        input.apps.isEmpty ? block.foreground : block.foreground.filter { input.apps.contains($0.item.appName) }
    }

    func value(_ block: ActivityBlock) -> Int {
        Self.valueFunction(apps: input.apps)(block)
    }

    /// The shown day of `block`.
    func shownDay(_ block: ActivityBlock) -> TrackingDay {
        block.shownDay(startOfDayHour: input.startOfDayHour)
    }

    /// Item seconds per app, largest first.
    static func rank(_ items: [ActivityBlockItem]) -> [AppTotal] {
        var seconds: [String: Int] = [:]
        var kinds: [String: ActivityAppKind] = [:]
        var appIDs: [String: String] = [:]
        for item in items {
            let app = item.item.appName
            seconds[app, default: 0] += item.seconds
            if kinds[app] == nil || kinds[app] == .other {
                kinds[app] = ActivityAppKind(item: item.item)
            }
            if appIDs[app, default: ""].isEmpty {
                appIDs[app] = item.item.appID
            }
        }
        return seconds.map { AppTotal(app: $0.key, appID: appIDs[$0.key] ?? "", kind: kinds[$0.key] ?? .other, seconds: $0.value) }
            .sorted { ($1.seconds, $0.app) < ($0.seconds, $1.app) }
    }

    /// The average per day with time (the header's second figure).
    public var averagePerActiveDay: Int {
        activeDays == 0 ? 0 : total / activeDays
    }

    /// Whether the range has blocks for the device (before the app filter).
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
