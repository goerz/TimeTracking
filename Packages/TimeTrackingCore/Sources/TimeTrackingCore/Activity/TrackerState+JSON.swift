// TrackerState+JSON: reading and writing current.json (activity_tracking.md §4.4).

public import Foundation

extension TrackerState {
    /// Parses `current.json`. Its times are local times of `timeZone` (the
    /// Mac's zone); times with an offset are accepted too. Unknown keys are
    /// ignored.
    public static func parse(_ data: Data, timeZone: TimeZone) throws(ActivityError) -> Self {
        let file: CurrentFile
        do {
            file = try JSONDecoder().decode(CurrentFile.self, from: data)
        } catch {
            throw .invalidState(error.localizedDescription)
        }
        func instant(_ text: String, _ field: String) throws(ActivityError) -> Date {
            guard let date = LocalTimestamp.instant(text, timeZone: timeZone) else {
                throw .invalidState("\(field) is not a time: \(text)")
            }
            return date
        }
        var openBlock: TrackerOpenBlock?
        if let block = file.block {
            openBlock = try TrackerOpenBlock(
                start: instant(block.start, "block.s"),
                activeSeconds: block.active,
                devices: block.devices,
                groupKey: block.group ?? "",
                groupShare: block.share ?? 0,
                items: block.items,
                background: block.background,
                reconstructedSeconds: block.reconstructed ?? 0
            )
        }
        var primary: TrackerPrimaryItem?
        if file.hasPrimary {
            let fields = file.primary
            guard fields.count >= 2 else {
                throw .invalidState("primary has \(fields.count) fields")
            }
            primary = TrackerPrimaryItem(context: fields[0], subject: fields[1], detail: fields.count > 2 ? fields[2] : "")
        }
        return try Self(
            device: file.dev ?? "",
            openBlock: openBlock,
            primary: primary,
            presence: TrackerPresence(
                state: file.presence.state,
                since: instant(file.presence.since, "presence.since"),
                lastInput: file.presence.lastInput.map { text throws(ActivityError) in try instant(text, "presence.last_input") }
            ),
            health: TrackerHealth(
                lastTick: instant(file.health.lastTick, "health.last_tick"),
                version: file.health.version ?? "",
                sources: file.health.sources.map { source in
                    TrackerSourceHealth(id: source.id, name: source.name ?? source.id, status: source.status, reason: source.reason ?? "")
                }
            ),
            format: file.format ?? 1
        )
    }

    /// The `current.json` text, with local times of `timeZone`.
    public func jsonText(timeZone: TimeZone) -> String {
        func local(_ date: Date) -> String {
            LocalTimestamp(date: date, utcOffset: timeZone.secondsFromGMT(for: date)).text
        }
        var writer = JSONObjectWriter()
        writer.add("format", format)
        writer.add("dev", device)
        if let openBlock {
            var block = JSONObjectWriter()
            block.add("s", local(openBlock.start))
            block.add("a", openBlock.activeSeconds)
            block.add("dev", openBlock.devices)
            block.add("rec", openBlock.reconstructedSeconds)
            block.add("g", openBlock.groupKey)
            block.add("gs", openBlock.groupShare)
            block.add("items", openBlock.items)
            block.add("bg", openBlock.background)
            writer.addRaw("block", block.text)
        } else {
            writer.addRaw("block", "null")
        }
        if let primary {
            writer.add("primary", [primary.context, primary.subject, primary.detail])
        } else {
            writer.addRaw("primary", "null")
        }
        var presenceWriter = JSONObjectWriter()
        presenceWriter.add("state", presence.state)
        presenceWriter.add("since", local(presence.since))
        if let lastInput = presence.lastInput {
            presenceWriter.add("last_input", local(lastInput))
        }
        writer.addRaw("presence", presenceWriter.text)
        var healthWriter = JSONObjectWriter()
        healthWriter.add("last_tick", local(health.lastTick))
        healthWriter.add("version", health.version)
        healthWriter.add("sources", health.sources.map(SourceRecord.init(source:)))
        writer.addRaw("health", healthWriter.text)
        return writer.text
    }
}

// MARK: - File records

private struct CurrentFile: Decodable {
    enum CodingKeys: String, CodingKey {
        case format, dev, block, primary, presence, health
    }

    var format: Int?
    var dev: String?
    var block: BlockRecord?
    var primary: [String]
    /// Whether `primary` is present and not `null`.
    var hasPrimary: Bool
    var presence: PresenceRecord
    var health: HealthRecord

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.format = try container.decodeIfPresent(Int.self, forKey: .format)
        self.dev = try container.decodeIfPresent(String.self, forKey: .dev)
        self.block = try container.decodeIfPresent(BlockRecord.self, forKey: .block)
        let fields = try container.decodeIfPresent([String].self, forKey: .primary)
        self.primary = fields ?? []
        self.hasPrimary = fields != nil
        self.presence = try container.decode(PresenceRecord.self, forKey: .presence)
        self.health = try container.decode(HealthRecord.self, forKey: .health)
    }
}

private struct BlockRecord: Decodable {
    enum CodingKeys: String, CodingKey {
        case start = "s"
        case active = "a"
        case devices = "dev"
        case reconstructed = "rec"
        case group = "g"
        case share = "gs"
        case items
        case background = "bg"
    }

    var start: String
    var active: Int
    var devices: [ActivityDeviceTime]
    var reconstructed: Int?
    var group: String?
    var share: Double?
    var items: [ActivityItem]
    var background: [ActivityItem]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.start = try container.decode(String.self, forKey: .start)
        self.active = try container.decode(Int.self, forKey: .active)
        self.devices = try container.decodeIfPresent([ActivityDeviceTime].self, forKey: .devices) ?? []
        self.reconstructed = try container.decodeIfPresent(Int.self, forKey: .reconstructed)
        self.group = try container.decodeIfPresent(String.self, forKey: .group)
        self.share = try container.decodeIfPresent(Double.self, forKey: .share)
        self.items = try container.decodeIfPresent([ActivityItem].self, forKey: .items) ?? []
        self.background = try container.decodeIfPresent([ActivityItem].self, forKey: .background) ?? []
    }
}

private struct PresenceRecord: Decodable {
    enum CodingKeys: String, CodingKey {
        case state
        case since
        case lastInput = "last_input"
    }

    var state: TrackerPresenceState
    var since: String
    var lastInput: String?
}

private struct HealthRecord: Decodable {
    enum CodingKeys: String, CodingKey {
        case lastTick = "last_tick"
        case version
        case sources
    }

    var lastTick: String
    var version: String?
    var sources: [SourceRecord]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.lastTick = try container.decode(String.self, forKey: .lastTick)
        self.version = try container.decodeIfPresent(String.self, forKey: .version)
        self.sources = try container.decodeIfPresent([SourceRecord].self, forKey: .sources) ?? []
    }
}

private struct SourceRecord: Codable {
    var id: String
    var name: String?
    var status: TrackerSourceStatus
    var reason: String?

    init(source: TrackerSourceHealth) {
        self.id = source.id
        self.name = source.name
        self.status = source.status
        self.reason = source.reason
    }
}
