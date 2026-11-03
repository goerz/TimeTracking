// BlockLogLine+Encoding: writing block-log and detail-log lines
// (spec_activity_tracking.md §4.2, §4.3).

import Foundation

extension BlockLogLine {
    /// The line's JSON text without the newline, keys in the order of the
    /// spec's examples. A block's local times use its own `utcOffset`, which
    /// must equal the `tz` of the header in effect.
    public var jsonText: String {
        switch self {
        case let .header(header):
            Self.headerText(header)
        case let .block(block, detail):
            Self.blockText(block, detail: detail)
        case let .background(stretch):
            Self.backgroundText(stretch)
        case let .other(type):
            Self.otherText(type)
        }
    }

    private static func headerText(_ header: BlockLogHeader) -> String {
        var writer = JSONObjectWriter()
        writer.add("type", "header")
        writer.add("format", header.format)
        writer.add("tz", LocalTimestamp.offsetText(header.utcOffset))
        writer.add("dev", header.device)
        writer.add("contexts", header.contexts)
        if !header.keys.isEmpty {
            var legend = JSONObjectWriter()
            for key in BlockLogHeader.keyOrder(header.keys) {
                legend.add(key, header.keys[key] ?? "")
            }
            writer.addRaw("keys", legend.text)
        }
        return writer.text
    }

    private static func otherText(_ type: String) -> String {
        var writer = JSONObjectWriter()
        writer.add("type", type)
        return writer.text
    }

    private static func backgroundText(_ stretch: ActivityBackgroundStretch) -> String {
        var writer = JSONObjectWriter()
        writer.add("type", backgroundType)
        writer.add("s", LocalTimestamp(date: stretch.start, utcOffset: stretch.utcOffset).text)
        writer.add("e", LocalTimestamp(date: stretch.end, utcOffset: stretch.utcOffset).text)
        writer.add("bg", stretch.items)
        return writer.text
    }

    private static func blockText(_ block: ActivityBlock, detail: ActivityBlockDetail?) -> String {
        func local(_ date: Date) -> String {
            LocalTimestamp(date: date, utcOffset: block.utcOffset).text
        }
        var writer = JSONObjectWriter()
        writer.add("s", local(block.start))
        writer.add("e", local(block.end))
        writer.add("a", block.activeSeconds)
        writer.add("dev", block.devices)
        writer.add("rec", block.reconstructedSeconds)
        writer.add("g", block.groupKey)
        writer.add("gs", block.groupShare)
        writer.add("items", detail?.items ?? block.items)
        writer.add("bg", block.background)
        if let detail {
            writer.add("urls", detail.urls.map { [local($0.time), $0.browser, $0.url, $0.title] })
            writer.add("files", detail.files.map { [local($0.time), $0.path] })
            writer.add("presence", detail.presence.map { [local($0.time), $0.state.rawValue] })
            if !detail.dwell.isEmpty {
                writer.add("dwell", detail.dwell.map { DwellField(time: local($0.time), url: $0.url, seconds: $0.seconds) })
            }
        }
        return writer.text
    }
}

/// A `dwell` entry `[time, url, seconds]` of the detail log.
struct DwellField: Codable {
    var time: String
    var url: String
    var seconds: Int

    init(time: String, url: String, seconds: Int) {
        self.time = time
        self.url = url
        self.seconds = seconds
    }

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.time = try container.decode(String.self)
        self.url = try container.decode(String.self)
        self.seconds = try container.decode(Int.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(time)
        try container.encode(url)
        try container.encode(seconds)
    }
}
