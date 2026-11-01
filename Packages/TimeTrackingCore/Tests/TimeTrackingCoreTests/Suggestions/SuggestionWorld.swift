// SuggestionWorld: the suggestion engine's synthetic fixture
// (spec_calendar.md §5.6): eight weeks of entries in
// America/New_York from 2024-01-29, the blocks recorded during them in
// block-log format, and calendar titles. Committed under
// Fixtures/Activity/suggestions/; `TIMETRACKING_WRITE_FIXTURES=1 swift test
// --filter SuggestionFixtureTests` rewrites it.

import Foundation
import TimeTrackingCore

struct SuggestionWorld {
    struct ProjectSpec: Codable, Equatable {
        var id: String
        var name: String
    }

    struct EntrySpec: Codable, Equatable {
        var id: String
        var project: String?
        var task: String
        var start: String
        var end: String
    }

    struct TitleSpec: Codable, Equatable {
        var title: String
        var start: String
        var end: String
    }

    struct Document: Codable, Equatable {
        var projects: [ProjectSpec]
        var entries: [EntrySpec]
        var titles: [TitleSpec]
    }

    static let zone = TestTime.newYork
    static let firstDay = TrackingDay(year: 2024, month: 1, day: 29)
    static let dayCount = 56
    /// The held-out last week starts here.
    static let heldOutDay = TrackingDay(year: 2024, month: 3, day: 18)

    static let noise = project("Noise Model", 1)
    static let admin = project("Admin", 2)
    static let optics = project("Quantum Optics", 3)
    static let acme = project("Acme Sequencer", 4)
    static let garden = project("Garden Blog", 5)

    static func project(_ name: String, _ number: Int) -> ProjectSpec {
        ProjectSpec(id: "00000000-0000-4000-8000-00000000000\(number)", name: name)
    }

    var document: Document
    var blocks: [ActivityBlock]

    // MARK: Times

    static func time(_ day: TrackingDay, _ clock: String) -> Date {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        let midnight = TrackingCalendar(timeZone: zone).startOfDay(day)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: midnight) ?? midnight
    }

    static func text(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )
    }

    /// A local time in `zone`. A bad text fails the running test (`#require`
    /// records the issue) and reads as `.distantPast`.
    static func date(_ text: String) -> Date {
        (try? TestTime.local(text, in: zone)) ?? .distantPast
    }

    // MARK: Files

    static var folder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Activity/suggestions", directoryHint: .isDirectory)
    }

    /// Writes the block log and `world.json` into `folder`.
    func write(to folder: URL) throws {
        let blockFolder = folder.appending(path: "blocks", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: blockFolder)
        try FileManager.default.createDirectory(at: blockFolder, withIntermediateDirectories: true)
        var writer = BlockLogWriter(folder: blockFolder, device: "macbook")
        for block in blocks {
            try writer.append(block, contexts: ["skim": "net.sourceforge.skim-app.skim", "mail": "com.apple.mail", "zoom": "us.zoom.xos"])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(document).write(to: folder.appending(path: "world.json"))
    }

    /// The committed fixture: `world.json` and the block log read back.
    static func load() async throws -> Self {
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: folder.appending(path: "world.json")))
        let local = try TemporaryFolder()
        defer { local.remove() }
        let reader = FileActivityStore(
            folders: ActivityFolders(shared: folder, local: local.url),
            timeZone: zone,
            clock: ManualClock(date("2024-03-25T00:00"))
        )
        let blocks = try await reader.blocks(in: DateInterval(start: date("2024-01-01T00:00"), end: date("2024-04-01T00:00")), devices: nil)
        return Self(document: document, blocks: blocks)
    }

    // MARK: Library values

    var entries: [TimeEntry] {
        document.entries.map { spec in
            TimeEntry(
                id: EntryID(spec.id) ?? EntryID(),
                projectID: spec.project.flatMap { ProjectID($0) },
                task: spec.task,
                start: Self.date(spec.start),
                end: Self.date(spec.end),
                timeZone: Self.zone.identifier,
                deviceID: DeviceID("00000000-0000-4000-8000-000000000001") ?? DeviceID(),
                createdAt: Self.date(spec.start),
                modifiedAt: Self.date(spec.end)
            )
        }
    }

    var titles: [SuggestionCalendarTitle] {
        document.titles.map { spec in
            SuggestionCalendarTitle(title: spec.title, interval: DateInterval(start: Self.date(spec.start), end: Self.date(spec.end)))
        }
    }

    static func id(_ spec: ProjectSpec) -> ProjectID? {
        ProjectID(spec.id)
    }

    /// The index trained on everything before `day` (default: the held-out week).
    func index(before day: TrackingDay = heldOutDay, feedback: [SuggestionFeedback] = []) -> SuggestionIndex {
        let now = TrackingCalendar(timeZone: Self.zone).startOfDay(day)
        let examples = SuggestionTraining.examples(
            entries: entries.filter { $0.start < now },
            blocks: blocks.filter { $0.start < now },
            titles: titles,
            feedback: feedback,
            now: now,
            trainDays: 180,
            timeZone: Self.zone
        )
        return SuggestionIndex(examples: examples)
    }
}

extension SuggestionWorld {
    // MARK: Generation

    private struct Session {
        var start: String
        var minutes: Int
        var project: ProjectSpec
        var task: String
        var title: String?
        var activity: [Use]
    }

    /// An item of a session and its share of the active time.
    private struct Use {
        var context: String
        var subject: String
        var detail: String
        var share: Double

        init(_ context: String, _ subject: String, _ detail: String, _ share: Double) {
            self.context = context
            self.subject = subject
            self.detail = detail
            self.share = share
        }

        func with(share: Double) -> Self {
            Self(context, subject, detail, share)
        }
    }

    private struct Random {
        var state: UInt64

        mutating func next(_ range: ClosedRange<Int>) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return range.lowerBound + Int((state >> 33) % UInt64(range.count))
        }
    }

    private static let paper = Use("tmux:paper", "~/Papers/2026_Noise", "nvim paper.tex", 0.8)
    private static let arxiv = Use("safari", "arxiv.org", "", 0.2)
    private static let lectures = Use("tmux:lectures", "~/Teaching/QuantumOptics", "nvim lecture.tex", 0.7)
    private static let skim = Use("skim", "lecture-notes.pdf", "", 0.3)
    private static let github = Use("safari", "github.com/acme/sequencer", "", 0.6)
    private static let code = Use("tmux:acme", "~/Code/acme-sequencer", "nvim sequencer.py", 0.4)

    private static func sessions(isoWeekday: Int) -> [Session] {
        if isoWeekday == 6 {
            let post = Session(
                start: "20:00",
                minutes: 90,
                project: garden,
                task: "Write post",
                activity: [Use("safari", "wordpress.com/garden", "", 1)]
            )
            return [post]
        }
        guard isoWeekday <= 5 else {
            return []
        }
        var result = [
            Session(start: "09:00", minutes: 90, project: noise, task: "Draft paper", activity: [paper, arxiv]),
            Session(start: "10:45", minutes: 45, project: admin, task: "Email", activity: [Use("mail", "Inbox", "", 1)]),
        ]
        if isoWeekday == 2 || isoWeekday == 4 {
            result.append(Session(
                start: "11:30",
                minutes: 30,
                project: noise,
                task: "Sync meeting",
                title: "Noise paper sync",
                activity: []
            ))
            result.append(Session(start: "13:00", minutes: 60, project: acme, task: "Code review", activity: [github, code]))
        } else {
            result.append(Session(start: "13:00", minutes: 90, project: optics, task: "Prepare lecture", activity: [lectures, skim]))
        }
        if isoWeekday == 5 {
            result.append(Session(
                start: "14:45",
                minutes: 60,
                project: admin,
                task: "Expense report",
                activity: [Use("safari", "concur.example.com", "", 0.7), Use("mail", "Inbox", "", 0.3)]
            ))
        } else {
            result.append(Session(
                start: "14:45",
                minutes: 90,
                project: acme,
                task: "Implement sequencer",
                activity: [code.with(share: 0.9), github.with(share: 0.1)]
            ))
        }
        if isoWeekday == 3 {
            result.append(Session(
                start: "16:30",
                minutes: 30,
                project: optics,
                task: "Office hours",
                title: "Office hours",
                activity: [Use("zoom", "Office hours", "", 1)]
            ))
        }
        return result
    }

    static func generate() -> Self {
        var random = Random(state: 42)
        var entries: [EntrySpec] = []
        var titles: [TitleSpec] = []
        var blocks: [ActivityBlock] = []
        for offset in 0 ..< dayCount {
            let day = firstDay.adding(days: offset)
            var previousEnd = Date.distantPast
            for session in sessions(isoWeekday: day.isoWeekday) {
                let jitter = random.next(-10 ... 10)
                let start = max(time(day, session.start) + Double(jitter * 60), previousEnd + 60)
                let end = start + Double((session.minutes + random.next(-10 ... 10)) * 60)
                previousEnd = end
                entries.append(EntrySpec(
                    id: String(format: "10000000-0000-4000-8000-%012d", entries.count + 1),
                    project: session.project.id,
                    task: session.task,
                    start: text(start),
                    end: text(end)
                ))
                if let title = session.title {
                    titles.append(TitleSpec(
                        title: title,
                        start: text(time(day, session.start)),
                        end: text(time(day, session.start) + Double(session.minutes * 60))
                    ))
                }
                blocks += Self.blocks(from: start, to: end, activity: session.activity)
            }
        }
        let projects = [noise, admin, optics, acme, garden]
        return Self(document: Document(projects: projects, entries: entries, titles: titles), blocks: blocks)
    }

    /// 30-minute blocks with 90 % active time split by the activity shares.
    private static func blocks(from start: Date, to end: Date, activity: [Use]) -> [ActivityBlock] {
        guard let main = activity.first else {
            return []
        }
        var result: [ActivityBlock] = []
        var cursor = start
        while cursor < end {
            let next = min(end, cursor + 1800)
            let active = Int(next.timeIntervalSince(cursor) * 0.9)
            let items = activity.map { use in
                ActivityItem(context: use.context, subject: use.subject, detail: use.detail, seconds: Int(Double(active) * use.share))
            }
            let total = items.reduce(0) { $0 + $1.seconds }
            result.append(ActivityBlock(
                start: cursor,
                end: next,
                activeSeconds: total,
                device: "macbook",
                groupKey: main.context,
                groupShare: Double(items[0].seconds) / Double(max(total, 1)),
                items: items,
                utcOffset: zone.secondsFromGMT(for: cursor)
            ))
            cursor = next
        }
        return result
    }
}
