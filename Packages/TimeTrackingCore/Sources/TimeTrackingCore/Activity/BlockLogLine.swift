// BlockLogLine: one line of the block log or the detail log
// (spec_activity_tracking.md §4.2, §4.3).

public import Foundation

/// A header of a month file: the time zone, the device, and the map from
/// context keys to bundle identifiers (or process names).
public struct BlockLogHeader: Sendable, Hashable {
    public var format: Int
    /// Seconds east of UTC of the following lines' local times (`tz`).
    public var utcOffset: Int
    public var device: String
    public var contexts: [String: String]

    public init(utcOffset: Int, device: String, contexts: [String: String], format: Int = 1) {
        self.format = format
        self.utcOffset = utcOffset
        self.device = device
        self.contexts = contexts
    }
}

/// A parsed line of a month file.
public enum BlockLogLine: Sendable, Hashable {
    case header(BlockLogHeader)
    /// A block, with its detail when the line came from the detail log.
    case block(ActivityBlock, detail: ActivityBlockDetail?)
    /// An object with a `type` other than `header`, which readers skip.
    case other(type: String)

    /// Parses one line. Block times are local times converted with the
    /// `tz` of `header`, the latest header before the line; a block before
    /// any header is malformed. Unknown keys are ignored.
    public static func parse(_ line: some DataProtocol, header: BlockLogHeader?) throws(ActivityError) -> Self {
        try parse(Data(line), header: header, decoder: JSONDecoder())
    }

    static func parse(_ data: Data, header: BlockLogHeader?, decoder: JSONDecoder) throws(ActivityError) -> Self {
        let record: LineRecord
        do {
            record = try decoder.decode(LineRecord.self, from: data)
        } catch {
            // A line of another type may use the block keys differently.
            if let probe = try? decoder.decode(TypeProbe.self, from: data), let type = probe.type, type != "header" {
                return .other(type: type)
            }
            throw .malformedLine(error.localizedDescription)
        }
        switch record.type {
        case "header":
            return try .header(Self.header(record))
        case let .some(type):
            return .other(type: type)
        case .none:
            guard let header else {
                throw .malformedLine("a block before the first header")
            }
            return try block(record, header: header)
        }
    }

    private static func header(_ record: LineRecord) throws(ActivityError) -> BlockLogHeader {
        guard let zone = record.zone, let offset = LocalTimestamp.parseOffset(zone) else {
            throw .malformedLine("a header without a valid tz")
        }
        return BlockLogHeader(utcOffset: offset, device: record.dev ?? "", contexts: record.contexts, format: record.format ?? 1)
    }

    private static func block(_ record: LineRecord, header: BlockLogHeader) throws(ActivityError) -> Self {
        guard let startText = record.start, let start = LocalTimestamp(text: startText),
              let endText = record.end, let end = LocalTimestamp(text: endText)
        else {
            throw .malformedLine("a block without valid s and e")
        }
        guard let active = record.active, record.hasItems else {
            throw .malformedLine("a block without a or items")
        }
        var source = ActivitySource.live
        if let text = record.src {
            guard let value = ActivitySource(rawValue: text) else {
                throw .malformedLine("unknown src \(text)")
            }
            source = value
        }
        let startDate = start.date(utcOffset: header.utcOffset)
        let endDate = end.date(utcOffset: header.utcOffset)
        guard endDate >= startDate else {
            throw .malformedLine("a block ending before its start")
        }
        let block = ActivityBlock(
            start: startDate,
            end: endDate,
            activeSeconds: active,
            device: record.dev ?? header.device,
            groupKey: record.group ?? "",
            groupShare: record.share ?? 0,
            items: record.items,
            utcOffset: header.utcOffset,
            source: source,
            background: record.background
        )
        guard record.hasDetail else {
            return .block(block, detail: nil)
        }
        return try .block(block, detail: detail(record, block: block))
    }

    private static func detail(_ record: LineRecord, block: ActivityBlock) throws(ActivityError) -> ActivityBlockDetail {
        func time(_ text: String) throws(ActivityError) -> Date {
            guard let local = LocalTimestamp(text: text) else {
                throw .malformedLine("detail time \(text)")
            }
            return local.date(utcOffset: block.utcOffset)
        }
        var urls: [ActivityURLVisit] = []
        for fields in record.urls where fields.count >= 3 {
            let title = fields.count > 3 ? fields[3] : ""
            try urls.append(ActivityURLVisit(time: time(fields[0]), browser: fields[1], url: fields[2], title: title))
        }
        var files: [ActivityFileChange] = []
        for fields in record.files where fields.count >= 2 {
            try files.append(ActivityFileChange(time: time(fields[0]), path: fields[1]))
        }
        var presence: [ActivityPresenceTransition] = []
        for fields in record.presence where fields.count >= 2 {
            if let state = TrackerPresenceState(rawValue: fields[1]) {
                try presence.append(ActivityPresenceTransition(time: time(fields[0]), state: state))
            }
        }
        var dwell: [ActivityDwell] = []
        for field in record.dwell {
            try dwell.append(ActivityDwell(time: time(field.time), url: field.url, seconds: field.seconds))
        }
        return ActivityBlockDetail(blockID: block.id, items: block.items, urls: urls, files: files, presence: presence, dwell: dwell)
    }
}

// MARK: - Line records

/// Every key a line may carry; unknown keys are ignored.
private struct LineRecord: Decodable {
    enum CodingKeys: String, CodingKey {
        case type, format, dev, contexts
        case zone = "tz"
        case start = "s"
        case end = "e"
        case active = "a"
        case group = "g"
        case share = "gs"
        case items
        case background = "bg"
        case src, urls, files, presence, dwell
    }

    var type: String?
    var format: Int?
    var zone: String?
    var dev: String?
    var contexts: [String: String]
    var start: String?
    var end: String?
    var active: Int?
    var group: String?
    var share: Double?
    var items: [ActivityItem]
    var hasItems: Bool
    var background: [ActivityItem]
    var src: String?
    var urls: [[String]]
    var files: [[String]]
    var presence: [[String]]
    var dwell: [DwellField]
    /// Whether the line carries detail-log keys.
    var hasDetail: Bool

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.format = try container.decodeIfPresent(Int.self, forKey: .format)
        self.zone = try container.decodeIfPresent(String.self, forKey: .zone)
        self.dev = try container.decodeIfPresent(String.self, forKey: .dev)
        self.contexts = try container.decodeIfPresent([String: String].self, forKey: .contexts) ?? [:]
        self.start = try container.decodeIfPresent(String.self, forKey: .start)
        self.end = try container.decodeIfPresent(String.self, forKey: .end)
        self.active = try container.decodeIfPresent(Int.self, forKey: .active)
        self.group = try container.decodeIfPresent(String.self, forKey: .group)
        self.share = try container.decodeIfPresent(Double.self, forKey: .share)
        self.hasItems = container.contains(.items)
        self.items = try container.decodeIfPresent([ActivityItem].self, forKey: .items) ?? []
        self.background = try container.decodeIfPresent([ActivityItem].self, forKey: .background) ?? []
        self.src = try container.decodeIfPresent(String.self, forKey: .src)
        self.hasDetail = container.contains(.urls) || container.contains(.files) || container.contains(.presence)
        self.urls = try container.decodeIfPresent([[String]].self, forKey: .urls) ?? []
        self.files = try container.decodeIfPresent([[String]].self, forKey: .files) ?? []
        self.presence = try container.decodeIfPresent([[String]].self, forKey: .presence) ?? []
        self.dwell = try container.decodeIfPresent([DwellField].self, forKey: .dwell) ?? []
    }
}

private struct TypeProbe: Decodable {
    var type: String?
}
