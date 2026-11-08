// The tool's activity listing: the blocks of the block log starting in a
// range, their totals, and their coverage by entries (automation.md §3.12).

public import Foundation

/// What `activity` lists.
public struct ActivityQuery: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case foreground
        case background
    }

    /// Lists the open block of `current.json` too.
    public var includeOpen: Bool
    /// Only blocks of this kind; both when `nil`.
    public var kind: Kind?
    /// Only foreground blocks with an uncovered stretch at least this long,
    /// and of their stretches only those.
    public var untrackedMinimum: TimeInterval?

    public init(includeOpen: Bool = false, kind: Kind? = nil, untrackedMinimum: TimeInterval? = nil) {
        self.includeOpen = includeOpen
        self.kind = kind
        self.untrackedMinimum = untrackedMinimum
    }
}

extension AutomationService {
    /// The blocks, foreground and background, whose start lies in `range`,
    /// each counted whole on the shown day of its start; foreground blocks
    /// with their stretches covered by no entry, by the Calendar's dimming
    /// rule (calendar.md §3.1), clamped at now.
    public func activity(
        in range: DayRange,
        reader: FileActivityStore,
        query: ActivityQuery
    ) async throws(AutomationError) -> ActivityListing {
        let interval = range.interval(in: calendar)
        let now = now
        let contains = { (block: ActivityBlock) in block.start >= interval.start && block.start < interval.end }
        var blocks: [ActivityBlock] = []
        if query.kind != .background {
            blocks += await reader.blocks(in: interval, devices: nil).filter { contains($0) && (query.includeOpen || !$0.isOpen) }
        }
        if query.kind != .foreground, query.untrackedMinimum == nil {
            blocks += await reader.backgroundBlocks(in: interval, devices: nil).filter(contains)
        }
        blocks.sort { ($0.start, $0.isBackgroundBlock ? 1 : 0) < ($1.start, $1.isBackgroundBlock ? 1 : 0) }

        let foreground = blocks.filter { !$0.isBackgroundBlock }
        var tracked: [DateInterval] = []
        if let first = foreground.map(\.start).min(), let last = foreground.map(\.end).max(), first < last {
            let store = store
            tracked = try await run { try await store.entries(in: DateInterval(start: first, end: last), includeDeleted: false) }
                .map { $0.interval(at: now) }
        }
        var rows: [ActivityListing.Row] = blocks.map { block in
            guard !block.isBackgroundBlock else {
                return ActivityListing.Row(block: block, coveredSeconds: nil, uncovered: [])
            }
            let span = DateInterval(start: block.start, end: max(block.start, min(block.end, now)))
            let uncovered = CalendarCoverage.uncovered(span, by: tracked).filter { $0.duration > 0 }
            let open = uncovered.reduce(0) { $0 + $1.duration }
            return ActivityListing.Row(block: block, coveredSeconds: Int((span.duration - open).rounded()), uncovered: uncovered)
        }
        if let minimum = query.untrackedMinimum {
            rows = rows.compactMap { row in
                var kept = row
                kept.uncovered = row.uncovered.filter { $0.duration >= minimum }
                return kept.uncovered.isEmpty ? nil : kept
            }
        }

        let dates = TrackingCalendar(timeZone: timeZone)
        let today = dates.day(containing: now)
        var files: [ActivityListing.DateFile] = []
        if interval.end > interval.start {
            var day = dates.day(containing: interval.start)
            let last = min(dates.day(containing: interval.end.addingTimeInterval(-1)), today)
            while day <= last {
                await files.append(ActivityListing.DateFile(day: day, status: reader.dateFileStatus(of: day)))
                day = day.adding(days: 1)
            }
        }
        return ActivityListing(range: range, rows: rows, files: files, calendar: calendar)
    }
}

/// The blocks `activity` lists, with the date files they come from.
public struct ActivityListing: Sendable {
    public struct Row: Sendable, Hashable {
        public var block: ActivityBlock
        /// Seconds of the block's span (clamped at now) covered by entries;
        /// `nil` for a background block.
        public var coveredSeconds: Int?
        /// The stretches no entry covers, in order; empty for a background block.
        public var uncovered: [DateInterval]
    }

    public struct DateFile: Sendable, Hashable {
        public var day: TrackingDay
        public var status: ActivityDateFileStatus
    }

    public var range: DayRange
    public var rows: [Row]
    /// The local dates whose files hold the range's blocks, up to today.
    public var files: [DateFile]
    /// The display calendar: the system zone and the start of day.
    public var calendar: TrackingCalendar

    private var timeZone: TimeZone {
        calendar.timeZone
    }

    /// `{"from", "to", "files": [{"date", "status"}], "blocks": [block records]}`.
    public var json: JSONValue {
        .object([
            "from": .string(range.fromText(in: timeZone)),
            "to": .string(range.toText(in: timeZone)),
            "files": .array(files.map { .object(["date": .string($0.day.description), "status": .string($0.status.rawValue)]) }),
            "blocks": .array(rows.map(record)),
        ])
    }

    /// The dates whose file could not be read, as one line each.
    public var fileProblems: [String] {
        files.compactMap { file in
            switch file.status {
            case .present: nil
            case .missing: "\(file.day): no date file"
            case .notDownloaded: "\(file.day): the date file is not downloaded from iCloud Drive yet"
            }
        }
    }

    private func timestamp(_ date: Date) -> JSONValue {
        .string(ReportCSVWriter.timestamp(date, in: timeZone))
    }

    /// One block: times, kind, totals, coverage, and its items.
    private func record(_ row: Row) -> JSONValue {
        let block = row.block
        // A background block's totals are those of its background items.
        let items = block.isBackgroundBlock ? block.background : block.foreground
        let total = items.reduce(0) { $0 + $1.seconds }
        let workspaces = ActivityBlock.totals(of: items, by: \.item.workspace)
        return .object([
            "start": timestamp(block.start),
            "end": timestamp(block.end),
            "day": .string(calendar.day(containing: block.start).description),
            "kind": .string(block.isBackgroundBlock ? "background" : "foreground"),
            "open": .bool(block.isOpen),
            "endReason": .optional(block.endReason?.rawValue),
            "seconds": .int(Int(block.interval.duration.rounded())),
            "activeSeconds": .int(block.activeSeconds),
            "reconstructedSeconds": .int(block.reconstructedSeconds),
            "devices": .array(ActivityBlock.totals(of: items, by: \.device).map { device in
                .object(["device": .string(device.name), "seconds": .int(device.seconds)])
            }),
            "workspaces": .array(workspaces.map { workspace in
                .object([
                    "workspace": .string(workspace.name),
                    "name": .string(ActivityItem.workspaceName(workspace.name)),
                    "seconds": .int(workspace.seconds),
                    "share": .double(total > 0 ? (Double(workspace.seconds) / Double(total) * 1000).rounded() / 1000 : 0),
                ])
            }),
            "dominantWorkspace": .optional(workspaces.first?.name),
            "coveredSeconds": row.coveredSeconds.map { .int($0) } ?? .null,
            "uncovered": block.isBackgroundBlock ? .null : .array(row.uncovered.map { stretch in
                .object([
                    "start": timestamp(stretch.start),
                    "end": timestamp(stretch.end),
                    "seconds": .int(Int(stretch.duration.rounded())),
                ])
            }),
            "foreground": .array(block.foreground.map(Self.item)),
            "background": .array(block.background.map(Self.item)),
        ])
    }

    /// A BlockItem with long key names: its device and seconds, then the Item.
    static func item(_ item: ActivityBlockItem) -> JSONValue {
        let head = [JSONValue.Member("device", .string(item.device)), JSONValue.Member("seconds", .int(item.seconds))]
        return .object(head + members(of: item.item))
    }

    /// An Item with long key names; empty values are `null`.
    static func item(_ item: ActivityItem) -> JSONValue {
        .object(members(of: item))
    }

    private static func members(of item: ActivityItem) -> [JSONValue.Member] {
        func text(_ string: String) -> JSONValue {
            string.isEmpty ? .null : .string(string)
        }
        return [
            JSONValue.Member("app", text(item.app)),
            JSONValue.Member("appID", text(item.appID)),
            JSONValue.Member("window", text(item.window)),
            JSONValue.Member("host", text(item.host)),
            JSONValue.Member("session", text(item.session)),
            JSONValue.Member("location", text(item.location)),
            JSONValue.Member("documents", .array(item.documents.map { .string($0) })),
            JSONValue.Member("command", text(item.command)),
            JSONValue.Member("workspace", text(item.workspace)),
        ]
    }
}
