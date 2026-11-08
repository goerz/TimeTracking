// TrackerState+JSON: reading and writing current.json (activity_tracking.md §4.4).

public import Foundation

extension TrackerState {
    /// Parses `current.json`. Times carry their UTC offsets; the block and
    /// the foreground Item use the keys of the block log. Unknown keys are
    /// skipped; a missing presence or health record, or an unreadable time
    /// in them, makes the file invalid.
    public static func parse(_ data: Data) throws(ActivityError) -> Self {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw .invalidState("current.json is not a JSON object")
        }
        if let format = object["format"] as? Int, format != BlockLogFile.format {
            throw .invalidState("current.json has format \(format), not \(BlockLogFile.format)")
        }
        guard let presence = object["presence"] as? [String: Any], let health = object["health"] as? [String: Any] else {
            throw .invalidState("current.json has no presence or health")
        }
        func time(_ record: [String: Any], _ key: String) throws(ActivityError) -> Date {
            guard let date = (record[key] as? String).flatMap(ActivityTimestamp.parseWithOffset)?.date else {
                throw .invalidState("\(key) is not a time")
            }
            return date
        }
        guard let state = (presence["state"] as? String).flatMap(TrackerPresenceState.init(rawValue:)) else {
            throw .invalidState("presence.state is not a presence state")
        }
        let sources = (health["sources"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.compactMap { source in
            (source["status"] as? String).flatMap(TrackerSourceStatus.init(rawValue:)).map { status in
                let id = source.string("id")
                let name = source.string("name")
                return TrackerSourceHealth(id: id, name: name.isEmpty ? id : name, status: status, reason: source.string("reason"))
            }
        }
        return try Self(
            block: (object["block"] as? [String: Any]).flatMap { ActivityBlock(json: $0, isOpen: true) },
            foreground: (object["foreground"] as? [String: Any]).map(ActivityItem.init(json:)),
            presence: TrackerPresence(
                state: state,
                since: time(presence, "since"),
                lastInput: presence["last_input"] == nil ? nil : time(presence, "last_input")
            ),
            health: TrackerHealth(lastTick: time(health, "last_tick"), version: health.string("version"), sources: sources)
        )
    }

    /// The `current.json` text, times at the offsets of `timeZone`.
    public func jsonText(timeZone: TimeZone) -> String {
        func time(_ date: Date) -> String {
            ActivityTimestamp.textWithOffset(date, utcOffset: timeZone.secondsFromGMT(for: date))
        }
        var writer = JSONObjectWriter()
        writer.add("format", BlockLogFile.format)
        writer.addRaw("block", block?.openBlockJSONText ?? "null")
        writer.addRaw("foreground", foreground?.jsonText ?? "null")
        var presenceWriter = JSONObjectWriter()
        presenceWriter.add("state", presence.state.rawValue)
        presenceWriter.add("since", time(presence.since))
        if let lastInput = presence.lastInput {
            presenceWriter.add("last_input", time(lastInput))
        }
        writer.addRaw("presence", presenceWriter.text)
        var healthWriter = JSONObjectWriter()
        healthWriter.add("last_tick", time(health.lastTick))
        healthWriter.add("version", health.version)
        let sources = health.sources.map { source in
            var sourceWriter = JSONObjectWriter()
            sourceWriter.add("id", source.id)
            sourceWriter.add("name", source.name)
            sourceWriter.add("status", source.status.rawValue)
            sourceWriter.add("reason", source.reason)
            return sourceWriter.text
        }
        healthWriter.addRaw("sources", "[\(sources.joined(separator: ","))]")
        writer.addRaw("health", healthWriter.text)
        return writer.text
    }
}

extension ActivityBlock {
    /// The open block as `current.json` writes it: the keys of a date file's
    /// line without `r`.
    var openBlockJSONText: String {
        var open = self
        open.endReason = nil
        return open.jsonText
    }
}
