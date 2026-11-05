// The JSON fields of the LiveState record (data_and_sync.md §4.1).

import Foundation

extension LiveState {
    /// The `running` field text of §4.1, or `nil` when nothing runs.
    public static func runningJSON(_ running: Running?) -> String? {
        guard let running else {
            return nil
        }
        var writer = JSONObjectWriter()
        writer.add("entryID", running.entryID.rawValue)
        writer.add("projectID", running.projectID?.rawValue)
        writer.add("task", running.task)
        writer.add("projectName", running.projectName)
        writer.add("clientName", running.clientName)
        writer.add("areaColor", running.areaColor)
        writer.add("start", LiveStateTime.text(running.start))
        return writer.text
    }

    /// Parses the `running` field; `nil` for absent or malformed text. A
    /// device on schema version 3 or earlier writes `chainStart` for `start`.
    public static func running(json: String?) -> Running? {
        guard let object = json.map(LiveStateTime.object),
              let entryID = (object["entryID"] as? String).flatMap({ EntryID($0) }),
              let start = ((object["start"] ?? object["chainStart"]) as? String).flatMap(LiveStateTime.date)
        else {
            return nil
        }
        return Running(
            entryID: entryID,
            projectID: (object["projectID"] as? String).flatMap { ProjectID($0) },
            task: object["task"] as? String ?? "",
            projectName: object["projectName"] as? String,
            clientName: object["clientName"] as? String,
            areaColor: object["areaColor"] as? String,
            start: start
        )
    }

    /// The `activity` field text: an object keyed by device id, sorted.
    public static func activityJSON(_ activity: [String: MacActivity]) -> String {
        var writer = JSONObjectWriter()
        for key in activity.keys.sorted() {
            writer.addRaw(key, activity[key]?.json ?? "null")
        }
        return writer.text
    }

    /// Parses the `activity` field; malformed entries are dropped.
    public static func activity(json: String?) -> [String: MacActivity] {
        guard let object = json.map(LiveStateTime.object) else {
            return [:]
        }
        var result: [String: MacActivity] = [:]
        for (key, value) in object {
            if let entry = value as? [String: Any], let activity = MacActivity(object: entry) {
                result[key] = activity
            }
        }
        return result
    }
}

extension LiveState.MacActivity {
    /// The entry's JSON text, keys in the order of §4.1.
    public var json: String {
        var writer = JSONObjectWriter()
        writer.add("device", device)
        writer.add("primary", primary.map { [$0.context, $0.subject, $0.detail] })
        writer.add("groupKey", groupKey)
        writer.add("presence", presence)
        writer.add("since", since.map(LiveStateTime.text))
        writer.add("agentRunning", agentRunning)
        writer.add("lastTick", lastTick.map(LiveStateTime.text))
        writer.add("health", health)
        writer.add("updatedAt", LiveStateTime.text(updatedAt))
        return writer.text
    }

    init?(object: [String: Any]) {
        guard let device = object["device"] as? String,
              let updatedAt = (object["updatedAt"] as? String).flatMap(LiveStateTime.date)
        else {
            return nil
        }
        self.init(
            device: device,
            primary: Self.primary(object["primary"]),
            groupKey: object["groupKey"] as? String,
            presence: object["presence"] as? String,
            since: (object["since"] as? String).flatMap(LiveStateTime.date),
            agentRunning: object["agentRunning"] as? Bool ?? false,
            lastTick: (object["lastTick"] as? String).flatMap(LiveStateTime.date),
            health: object["health"] as? [String] ?? [],
            updatedAt: updatedAt
        )
    }

    private static func primary(_ value: Any?) -> TrackerPrimaryItem? {
        guard let parts = value as? [String], parts.count == 3 else {
            return nil
        }
        return TrackerPrimaryItem(context: parts[0], subject: parts[1], detail: parts[2])
    }
}

/// RFC 3339 UTC timestamps with whole seconds, as `LiveState` stores them.
enum LiveStateTime {
    static func text(_ date: Date) -> String {
        TimeStore.rfc3339(date)
    }

    static func date(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }

    static func object(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }
}
