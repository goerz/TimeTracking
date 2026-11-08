// SampleFixture: Samples as fixture lines, and the replay of a fixture
// against its expected block log (activity_tracking.md §5; architecture.md §3.4).

public import Foundation

/// A fixture folder: `samples.jsonl` (one Sample per line), `fixture.json`
/// (`{"zone": …, "mac": …, "names": {id: name}}`), and `blocks/`, the date
/// files the Samples must form.
public enum SampleFixture {
    /// What a fixture says besides its Samples.
    public struct Description: Codable, Sendable, Hashable {
        public var zone: String
        /// The Mac's device id.
        public var mac: String
        /// The current name of each device id.
        public var names: [String: String]

        public init(zone: String, mac: String, names: [String: String]) {
            self.zone = zone
            self.mac = mac
            self.names = names
        }
    }

    /// `{"t":…,"d":…,"src":…,"st":…,"f":{…},"b":[…]}`, the time with `utcOffset`.
    public static func line(_ sample: Sample, utcOffset: Int) -> String {
        var writer = JSONObjectWriter()
        writer.add("t", ActivityTimestamp.textWithOffset(sample.time, utcOffset: utcOffset))
        writer.add("d", sample.deviceID)
        writer.add("src", sample.source.rawValue)
        writer.add("st", sample.state.rawValue)
        let items = sample.itemsJSON
        if items != "{}" {
            writer.addRaw("items", items)
        }
        return writer.text
    }

    /// The Sample of a fixture line, `nil` for any other line.
    public static func sample(line: some StringProtocol) -> Sample? {
        guard let object = ActivityBlock.jsonObject(line),
              let time = (object["t"] as? String).flatMap(ActivityTimestamp.parseWithOffset)?.date,
              let source = (object["src"] as? String).flatMap(SampleSource.init(rawValue:)),
              let state = (object["st"] as? String).flatMap(TrackerPresenceState.init(rawValue:))
        else {
            return nil
        }
        let items = (object["items"] as? [String: Any]).map { (try? JSONSerialization.data(withJSONObject: $0)) ?? Data() }
            .map { Sample.items(fromJSON: String(decoding: $0, as: UTF8.self)) }
        return Sample(
            time: time,
            deviceID: object.string("d"),
            source: source,
            state: state,
            foreground: items?.foreground,
            background: items?.background ?? []
        )
    }

    /// Forms the date files of the fixture in `folder` from its Samples,
    /// two days after the last of them and with the default settings, and returns
    /// the dates whose file differs from the expected one (empty: a match).
    public static func replay(folder: URL, settings: TrackerSettings = .defaults) throws -> [String] {
        let description = try JSONDecoder().decode(Description.self, from: Data(contentsOf: folder.appending(path: "fixture.json")))
        guard let zone = TimeZone(identifier: description.zone) else {
            return ["fixture.json: unknown zone \(description.zone)"]
        }
        let text = try String(contentsOf: folder.appending(path: "samples.jsonl"), encoding: .utf8)
        let samples = text.split(whereSeparator: \.isNewline).compactMap(sample(line:))
        let output = FileManager.default.temporaryDirectory.appending(path: "replay-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: output) }
        let store = try SampleStore(url: nil)
        let rules = SampleRules(exclusions: .empty, zone: zone, maxPassiveBlock: settings.blocks.maxPassiveBlock)
        try store.setMeta(.deviceNames, description.names)
        try store.insert(samples, rules: rules)
        let log = BlockLogFolder(url: output)
        let loop = RebuildLoop(store: store, log: log)
        let context = RebuildContext(
            settings: settings.blocks,
            rules: rules,
            macDeviceID: description.mac,
            macName: description.names[description.mac] ?? description.mac,
            redactor: Redactor(privacy: settings.privacy)
        )
        // Two days after the last Sample, every date of the fixture is
        // settled, and the loop has a today to stop at.
        let now = (samples.map(\.time).max() ?? Date(timeIntervalSince1970: 0)) + 2 * 86_400
        while try loop.runOnePass(now: now, context: context) != nil {}
        let expected = BlockLogFolder(url: folder.appending(path: "blocks", directoryHint: .isDirectory))
        return Set(expected.days() + log.days()).sorted().compactMap { day in
            expected.content(for: day) == log.content(for: day) ? nil : day.description
        }
    }
}
