// ActivityItem+Coding: the short keys of an Item and a BlockItem, shared by
// the block log, current.json, and the agent's Samples
// (activity_tracking.md §4.2, §4.4).

extension ActivityItem {
    /// Writes the Item's keys in the order of §4.2, omitting empty values.
    func write(to writer: inout JSONObjectWriter) {
        writer.addIfPresent("a", app)
        writer.addIfPresent("i", appID)
        writer.addIfPresent("w", window)
        writer.addIfPresent("h", host)
        writer.addIfPresent("ss", session)
        writer.addIfPresent("l", location)
        if !documents.isEmpty {
            writer.add("dc", documents)
        }
        writer.addIfPresent("c", command)
        writer.addIfPresent("ws", workspace)
    }

    /// The Item as one JSON object.
    public var jsonText: String {
        var writer = JSONObjectWriter()
        write(to: &writer)
        return writer.text
    }

    /// The Item of a decoded JSON object. Every key may be missing or of the
    /// wrong kind, which reads as empty; a missing `ws` reads as the app.
    init(json object: [String: Any]) {
        self.init(
            app: object.string("a"),
            appID: object.string("i"),
            window: object.string("w"),
            host: object.string("h"),
            session: object.string("ss"),
            location: object.string("l"),
            documents: (object["dc"] as? [Any])?.compactMap { $0 as? String } ?? [],
            command: object.string("c"),
            workspace: object.string("ws")
        )
    }
}

extension ActivityBlockItem {
    /// `{"d":…,"t":…, item keys}`.
    var jsonText: String {
        var writer = JSONObjectWriter()
        writer.addIfPresent("d", device)
        if seconds != 0 {
            writer.add("t", seconds)
        }
        item.write(to: &writer)
        return writer.text
    }

    init(json object: [String: Any]) {
        self.init(device: object.string("d"), seconds: object.int("t"), item: ActivityItem(json: object))
    }
}

extension [String: Any] {
    /// The string at `key`, `""` when missing or not a string.
    func string(_ key: String) -> String {
        self[key] as? String ?? ""
    }

    /// The whole number at `key`, 0 when missing or not a number.
    func int(_ key: String) -> Int {
        if let value = self[key] as? Int {
            return value
        }
        return (self[key] as? Double).map { Int($0) } ?? 0
    }
}
