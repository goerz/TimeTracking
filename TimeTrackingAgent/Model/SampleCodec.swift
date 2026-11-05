// SampleCodec: samples as JSON Lines, for samples.sqlite, `--record`, and
// `--replay` (activity_tracking.md §4.1, §5; architecture.md §3.4).

import Foundation
import TimeTrackingCore

/// One sample per line:
///
/// ```json
/// {"type":"header","format":1,"tz":"-04:00","dev":"macbook"}
/// {"t":"2024-03-14T09:00:00","state":"active","p":["tmux:paper","draft","nvim
/// notes.tex","tmux:paper","com.github.wez.wezterm"],"bg":[],"app":"com.github.wez.wezterm"}
/// ```
///
/// Times are local times at the `tz` of the latest header. Items are
/// `[context, subject, detail, group key, app]`. Keys after `state` are left
/// out when empty.
nonisolated enum SampleCodec {
    /// A header line.
    static func headerLine(utcOffset: Int, device: String) -> String {
        var writer = JSONObjectWriter()
        writer.add("type", "header")
        writer.add("format", 1)
        writer.add("tz", ActivityTimestamp.offsetText(utcOffset))
        writer.add("dev", device)
        return writer.text
    }

    /// The line of `sample` with local times at `utcOffset`.
    static func line(_ sample: Sample, utcOffset: Int) -> String {
        var writer = JSONObjectWriter()
        writer.add("t", ActivityTimestamp.text(sample.time, utcOffset: utcOffset))
        writer.add("state", sample.state.rawValue)
        if let event = sample.event {
            writer.add("event", event.rawValue)
        }
        if let primary = sample.primary {
            writer.add("p", fields(primary))
        }
        if !sample.secondaries.isEmpty {
            writer.add("bg", sample.secondaries.map(fields))
        }
        for (key, value) in [("app", sample.bundleID), ("title", sample.title), ("tmux", sample.tmuxTarget), ("url", sample.url)]
            where !value.isEmpty
        {
            writer.add(key, value)
        }
        return writer.text
    }

    /// Parses a sample line at `utcOffset`; `nil` for headers and malformed lines.
    static func sample(_ line: some StringProtocol, utcOffset: Int) -> Sample? {
        guard let record = try? JSONDecoder().decode(Record.self, from: Data(line.utf8)), record.type == nil,
              let text = record.time, let time = ActivityTimestamp.date(text, utcOffset: utcOffset),
              let stateText = record.state, let state = TrackerPresenceState(rawValue: stateText)
        else {
            return nil
        }
        return Sample(
            time: time,
            state: state,
            event: record.event.flatMap(PresenceEvent.init(rawValue:)),
            primary: record.primary.flatMap(item),
            secondaries: record.background.compactMap(item),
            bundleID: record.app ?? "",
            title: record.title ?? "",
            tmuxTarget: record.tmux ?? "",
            url: record.url ?? ""
        )
    }

    /// The header's offset and device, if `line` is a header.
    static func header(_ line: some StringProtocol) -> (utcOffset: Int, device: String)? {
        guard let record = try? JSONDecoder().decode(Record.self, from: Data(line.utf8)), record.type == "header",
              let zone = record.zone, let offset = ActivityTimestamp.parseOffset(zone)
        else {
            return nil
        }
        return (offset, record.dev ?? "")
    }

    /// Parses a whole sample file; samples before the first header use `defaultOffset`.
    static func samples(inFile text: String, defaultOffset: Int = 0) -> (samples: [Sample], device: String) {
        var offset = defaultOffset
        var device = ""
        var result: [Sample] = []
        for line in text.split(separator: "\n") where !line.isEmpty {
            if let header = header(line) {
                offset = header.utcOffset
                device = header.device
            } else if let sample = sample(line, utcOffset: offset) {
                result.append(sample)
            }
        }
        return (result, device)
    }

    private static func fields(_ item: SampleItem) -> [String] {
        [item.context, item.subject, item.detail, item.groupKey, item.app]
    }

    private static func item(_ fields: [String]) -> SampleItem? {
        guard fields.count >= 2 else {
            return nil
        }
        func field(_ index: Int) -> String {
            index < fields.count ? fields[index] : ""
        }
        let group = field(3).isEmpty ? fields[0] : field(3)
        return SampleItem(context: fields[0], subject: fields[1], detail: field(2), groupKey: group, app: field(4))
    }
}

/// Every key a sample or header line may carry.
private nonisolated struct Record: Decodable {
    enum CodingKeys: String, CodingKey {
        case type, dev, state, event, app, title, tmux, url
        case zone = "tz"
        case time = "t"
        case primary = "p"
        case background = "bg"
    }

    var type: String?
    var dev: String?
    var zone: String?
    var time: String?
    var state: String?
    var event: String?
    // A missing primary (idle) differs from an empty one.
    // swiftlint:disable:next discouraged_optional_collection
    var primary: [String]?
    var background: [[String]]
    var app: String?
    var title: String?
    var tmux: String?
    var url: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.dev = try container.decodeIfPresent(String.self, forKey: .dev)
        self.zone = try container.decodeIfPresent(String.self, forKey: .zone)
        self.time = try container.decodeIfPresent(String.self, forKey: .time)
        self.state = try container.decodeIfPresent(String.self, forKey: .state)
        self.event = try container.decodeIfPresent(String.self, forKey: .event)
        self.primary = try container.decodeIfPresent([String].self, forKey: .primary)
        self.background = try container.decodeIfPresent([[String]].self, forKey: .background) ?? []
        self.app = try container.decodeIfPresent(String.self, forKey: .app)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.tmux = try container.decodeIfPresent(String.self, forKey: .tmux)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
    }
}
