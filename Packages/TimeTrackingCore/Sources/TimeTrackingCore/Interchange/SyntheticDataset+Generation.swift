// SyntheticDataset generation: names, colors, and the day schedule (spec_data_and_sync.md §9.1).

import Foundation

/// SplitMix64: a small deterministic generator.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0 ..< 1, using: &self) < probability
    }

    /// A log-normal duration in seconds between 3 minutes and 3 hours.
    mutating func duration() -> Int {
        let normal = sqrt(-2 * log(Double.random(in: 1e-9 ..< 1, using: &self))) * cos(2 * .pi * Double.random(in: 0 ..< 1, using: &self))
        return Int(min(max(exp(log(2400) + 0.8 * normal), 180), 10_800))
    }
}

extension SyntheticDataset {
    private static let clientNames = [
        "University",
        "Consulting",
        "Home",
        "Foundation",
        "Startup",
        "Journal",
        "Community",
        "Lab",
        "Studio",
        "Library",
    ]
    private static let areaNames = [
        "Research",
        "Teaching",
        "Admin",
        "Writing",
        "Review",
        "Outreach",
        "Software",
        "Grants",
        "Travel",
        "Finance",
    ]
    private static let adjectives = ["Noise", "Quantum", "Control", "Survey", "Budget", "Course", "Website", "Data", "Model", "Field"]
    private static let nouns = [
        "paper",
        "notes",
        "pipeline",
        "workshop",
        "proposal",
        "review",
        "toolkit",
        "report",
        "lecture",
        "audit",
        "book",
        "plan",
    ]
    private static let verbs = ["Draft", "Revise", "Clarify", "Review", "Plan", "Fix", "Discuss", "Prepare", "Check", "Outline"]
    private static let objects = [
        "intro",
        "figures",
        "noise model",
        "methods",
        "budget",
        "slides",
        "tests",
        "abstract",
        "appendix",
        "schedule",
        "references",
        "email",
    ]

    private func id(_ kind: String, _ index: Int) -> String {
        UUID.version5(namespace: Self.namespace, name: "\(kind):\(seed):\(index)").uuidString.lowercased()
    }

    /// The structure records; the first area of each client is its general area.
    private func structure(createdAt: String) -> StructureRecords {
        var colors: [AreaColor] = []
        var clientRecords: [[String: Any]] = []
        var areaRecords: [[String: Any]] = []
        let clientCount = max(clients, 0)
        for index in 0 ..< clientCount {
            let name = Self.clientNames[index % Self.clientNames.count] + (index >= Self.clientNames.count ? " \(index)" : "")
            clientRecords.append(["id": id("client", index), "name": name, "createdAt": createdAt])
        }
        for index in 0 ..< max(areas, clientCount) where clientCount > 0 {
            let client = index % clientCount
            let general = index < clientCount
            let color = AreaColor.defaultColor(existing: colors)
            colors.append(color)
            let name = general ? clientRecords[client]["name"] as? String ?? "" : Self
                .areaNames[(index - clientCount) % Self.areaNames.count]
                + ((index - clientCount) >= Self.areaNames.count ? " \(index)" : "")
            areaRecords.append([
                "id": id("area", index), "clientID": id("client", client), "name": name, "general": general,
                "color": color.hex, "sortOrder": general ? 0 : index / clientCount, "retired": false, "createdAt": createdAt,
            ])
        }
        var projectRecords: [[String: Any]] = []
        for index in 0 ..< max(projects, 0) where !areaRecords.isEmpty {
            let area = areaRecords[index % areaRecords.count]
            let name = "\(Self.adjectives[index % Self.adjectives.count]) \(Self.nouns[(index / Self.adjectives.count) % Self.nouns.count])"
            let archived = index % 7 == 6
            projectRecords.append([
                "id": id("project", index), "areaID": area["id"] ?? "", "name": name, "archived": archived,
                "archivedAt": archived ? createdAt : NSNull(), "createdAt": createdAt,
            ])
        }
        return StructureRecords(clients: clientRecords, areas: areaRecords, projects: projectRecords)
    }

    /// The task phrases of project `index` (20 to 60).
    private func tasks(project index: Int) -> [String] {
        var generator = SeededGenerator(seed: seed &+ UInt64(index) &* 7919)
        let count = Int.random(in: 20 ... 60, using: &generator)
        return (0 ..< count).map { offset in
            "\(Self.verbs[(offset + index) % Self.verbs.count]) \(Self.objects[(offset * 7 + index) % Self.objects.count])"
                + (offset >= Self.verbs.count ? " \(offset / Self.verbs.count + 1)" : "")
        }
    }

    /// The document fed to the importer.
    func rawDocument() throws -> Data {
        let created = TimeStore.rfc3339(TrackingCalendar(timeZone: zone).startOfDay(days.lowerBound))
        let records = structure(createdAt: created)
        let entries = clients == 0 ? [] : entryRecords(projects: records.projects)
        let document: [String: Any] = [
            "format": 1, "clients": records.clients, "areas": records.areas, "projects": records.projects, "entries": entries,
            "settings": clients == 0 ? [:] : [
                "pomodoro.focusMinutes": 25,
                "pinnedProjectIDs": Array(records.projects.prefix(3).compactMap { $0["id"] }),
            ],
        ]
        return try JSONSerialization.data(withJSONObject: document)
    }

    /// IDs of the entries `write(to:)` tombstones.
    func tombstoneIDs() -> [EntryID] {
        guard tombstoneShare > 0, let data = try? rawDocument(),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["entries"] as? [[String: Any]]
        else {
            return []
        }
        var generator = SeededGenerator(seed: seed ^ 0xDEAD)
        return entries.compactMap { entry in
            generator.chance(tombstoneShare) ? (entry["id"] as? String).flatMap { EntryID($0) } : nil
        }
    }

    private func entryRecords(projects: [[String: Any]]) -> [[String: Any]] {
        var generator = SeededGenerator(seed: seed)
        let active = projects.enumerated().filter { $0.element["archived"] as? Bool != true }
        let calendar = TrackingCalendar(timeZone: zone)
        var records: [[String: Any]] = []
        func add(_ start: Date, _ end: Date?) {
            let pick = active.isEmpty || generator.chance(0.05) ? nil : active[Int.random(in: 0 ..< active.count, using: &generator)]
            let phrases = pick.map { tasks(project: $0.offset) } ?? ["Email", "Planning", "Reading"]
            records.append([
                "id": id("entry", records.count), "projectID": pick?.element["id"] ?? NSNull(),
                "task": phrases[Int.random(in: 0 ..< phrases.count, using: &generator)],
                "start": TimeStore.rfc3339(start), "end": end.map { TimeStore.rfc3339($0) as Any } ?? NSNull(),
                "timeZone": timeZone, "deviceID": deviceID.rawValue,
            ])
        }
        var day = days.lowerBound
        while day <= days.upperBound {
            if day.isoWeekday <= 5 {
                var time = calendar.startOfDay(day) + TimeInterval(8 * 3600 + Int.random(in: 0 ... 90, using: &generator) * 60)
                let dayEnd = calendar.startOfDay(day) + 18.5 * 3600
                for _ in 0 ..< Int.random(in: 6 ... 14, using: &generator) where time < dayEnd {
                    let end = min(time + TimeInterval(generator.duration()), dayEnd)
                    add(time, end)
                    let overlap = generator.chance(overlapShare) ? -min(600, end.timeIntervalSince(time) / 2) : 0
                    time = end + TimeInterval(Int.random(in: 0 ... 15, using: &generator) * 60) + overlap
                }
                if generator.chance(0.10) {
                    let pastMidnight = generator.chance(0.2)
                    let start = calendar.startOfDay(day) + (pastMidnight ? 23 * 3600 : TimeInterval(19 * 3600 + Int.random(
                        in: 0 ... 90,
                        using: &generator
                    ) * 60))
                    add(start, start + (pastMidnight ? 5400 : TimeInterval(generator.duration() / 2 + 600)))
                }
            }
            day = day.adding(days: 1)
        }
        if let runningMinutes {
            add(nowDate - TimeInterval(runningMinutes * 60), nil)
        }
        return records
    }
}

/// The structure part of the raw document.
private struct StructureRecords {
    var clients: [[String: Any]]
    var areas: [[String: Any]]
    var projects: [[String: Any]]
}
