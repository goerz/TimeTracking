// Tests of the suggestion engine on the synthetic world
// (spec_calendar.md §5.6, PC-22).

import Foundation
import Testing
import TimeTrackingCore

@Suite("Suggestion engine")
struct SuggestionEngineTests {
    static func blocks(_ day: TrackingDay, _ start: String, minutes: Int, context: String, subject: String) -> [ActivityBlock] {
        let begin = SuggestionWorld.time(day, start)
        let block = ActivityBlock(
            start: begin,
            end: begin + Double(minutes * 60),
            activeSeconds: minutes * 54,
            device: "macbook",
            groupKey: context,
            groupShare: 1,
            items: [ActivityItem(context: context, subject: subject, detail: "", seconds: minutes * 54)],
            utcOffset: SuggestionWorld.zone.secondsFromGMT(for: begin)
        )
        return [block]
    }

    static func query(_ blocks: [ActivityBlock], title: String? = nil) -> SuggestionQuery {
        let interval = DateInterval(start: blocks.map(\.start).min() ?? .distantPast, end: blocks.map(\.end).max() ?? .distantPast)
        return SuggestionQuery(blocks: blocks, interval: interval, calendarTitle: title, timeZone: SuggestionWorld.zone)
    }

    static let heldOut = SuggestionWorld.heldOutDay
    static let saturday = TrackingDay(year: 2024, month: 3, day: 23)
    static let tuesday = TrackingDay(year: 2024, month: 3, day: 19)

    @Test("PC-22 the committed fixture matches its generator, and its block log reads back")
    func fixtureIsCurrent() async throws {
        let generated = SuggestionWorld.generate()
        if ProcessInfo.processInfo.environment["TIMETRACKING_WRITE_FIXTURES"] == "1" {
            try generated.write(to: SuggestionWorld.folder)
        }
        let loaded = try await SuggestionWorld.load()
        #expect(loaded.document == generated.document)
        #expect(loaded.blocks.map(\.id) == generated.blocks.map(\.id))
        #expect(loaded.blocks.map(\.items) == generated.blocks.map(\.items))
    }

    @Test("PC-22 a terminal session always tracked to one project is suggested above 0.8, also on a weekend evening")
    func terminalSession() async throws {
        let world = try await SuggestionWorld.load()
        let index = world.index()
        let morning = index.suggest(Self.query(Self.blocks(
            Self.heldOut,
            "09:05",
            minutes: 30,
            context: "tmux:paper",
            subject: "~/Papers/2026_Noise"
        )))
        #expect(morning.first?.projectID == SuggestionWorld.id(SuggestionWorld.noise))
        #expect(morning.first?.task == "Draft paper")
        #expect((morning.first?.confidence ?? 0) > 0.8)
        #expect(morning.first?.logsDirectly == true)
        let evening = index.suggest(Self.query(Self.blocks(
            Self.saturday,
            "20:15",
            minutes: 30,
            context: "tmux:paper",
            subject: "~/Papers/2026_Noise"
        )))
        #expect(evening.first?.projectID == SuggestionWorld.id(SuggestionWorld.noise))
        #expect((evening.first?.confidence ?? 0) > 0.8)
        #expect(evening.first?.reasons.contains(.groupKey("tmux:paper")) == true)
    }

    @Test("PC-22 a calendar title suggests the project of past events with that title for a block without activity")
    func calendarTitle() async throws {
        let world = try await SuggestionWorld.load()
        let start = SuggestionWorld.time(Self.tuesday, "11:30")
        let query = SuggestionQuery(
            parts: [],
            interval: DateInterval(start: start, duration: 1800),
            calendarTitle: "Noise paper sync",
            timeZone: SuggestionWorld.zone
        )
        let result = world.index().suggest(query)
        #expect(result.first?.projectID == SuggestionWorld.id(SuggestionWorld.noise))
        #expect(result.first?.task == "Sync meeting")
        #expect(result.first?.reasons.contains(.title) == true)
    }

    @Test("PC-22 a group-key rule beats the neighbors at confidence 1 with tasks from the model")
    func groupKeyRule() async throws {
        let world = try await SuggestionWorld.load()
        let rule = SuggestionRule(kind: .groupKey, pattern: "tmux:paper", projectID: SuggestionWorld.id(SuggestionWorld.acme))
        let query = Self.query(Self.blocks(
            Self.heldOut,
            "09:05",
            minutes: 30,
            context: "tmux:paper",
            subject: "~/Papers/2026_Noise"
        ))
        let result = world.index().suggest(query, rules: [rule])
        #expect(result.first?.projectID == SuggestionWorld.id(SuggestionWorld.acme))
        #expect(result.first?.confidence == 1)
        #expect(result.first?.reasons == [.rule])
        #expect(result.dropFirst().first?.projectID == SuggestionWorld.id(SuggestionWorld.noise))
        let withTask = SuggestionRule(
            kind: .context,
            pattern: "tmux:paper",
            projectID: SuggestionWorld.id(SuggestionWorld.admin),
            task: "Paperwork"
        )
        #expect(world.index().suggest(query, rules: [withTask]).first?.task == "Paperwork")
    }

    @Test("PC-22 builds and queries are deterministic, and fewer than five examples give nothing")
    func deterministic() async throws {
        let world = try await SuggestionWorld.load()
        let query = Self.query(Self.blocks(
            Self.heldOut,
            "13:10",
            minutes: 40,
            context: "tmux:acme",
            subject: "~/Code/acme-sequencer"
        ))
        let first = world.index().suggest(query)
        let second = SuggestionWorld.generate().index().suggest(query)
        #expect(first == second)
        #expect(first.count <= 5)
        #expect(first.first?.projectID == SuggestionWorld.id(SuggestionWorld.acme))
        let tiny = SuggestionIndex(examples: Array(world.index().examples.prefix(4)))
        #expect(tiny.suggest(query).isEmpty)
    }

    @Test("PC-22 held-out top-1 accuracy is at least 0.7 and top-3 at least 0.9")
    func heldOutAccuracy() async throws {
        let world = try await SuggestionWorld.load()
        let index = world.index()
        let cutoff = TrackingCalendar(timeZone: SuggestionWorld.zone).startOfDay(Self.heldOut)
        let heldOut = world.entries.filter { $0.start >= cutoff }
        var top1 = 0
        var top3 = 0
        for entry in heldOut {
            let interval = DateInterval(start: entry.start, end: entry.end ?? entry.start)
            let blocks = world.blocks.filter { $0.start < interval.end && $0.end > interval.start }
            let query = SuggestionQuery(
                blocks: blocks,
                interval: interval,
                calendarTitle: SuggestionCalendarTitle.covering(interval, in: world.titles),
                timeZone: SuggestionWorld.zone
            )
            let result = index.suggest(query)
            top1 += result.first?.projectID == entry.projectID ? 1 : 0
            top3 += result.prefix(3).contains { $0.projectID == entry.projectID } ? 1 : 0
        }
        #expect(heldOut.count > 20)
        #expect(Double(top1) / Double(heldOut.count) >= 0.7)
        #expect(Double(top3) / Double(heldOut.count) >= 0.9)
    }

    @Test("PC-22 examples from accepted suggestions weigh 2, others 1")
    func feedbackWeight() async throws {
        let world = try await SuggestionWorld.load()
        let entry = try #require(world.entries.first)
        let feedback = SuggestionFeedback(
            recordedAt: entry.start,
            queryStart: entry.start,
            queryEnd: entry.end ?? entry.start,
            queryItems: 1,
            source: .block,
            proposedProjectID: entry.projectID,
            proposedTask: entry.task,
            confidence: 0.9,
            outcome: .accepted,
            entryID: entry.id
        )
        let examples = world.index(feedback: [feedback]).examples
        #expect(examples.first { $0.entryID == entry.id }?.weight == 2)
        #expect(examples.filter { $0.weight == 2 }.count == 1)
    }

    @Test("PC-22 tokens of contexts, subjects, details, sites, and titles")
    func tokens() {
        let item = ActivityItem(context: "tmux:paper", subject: "~/Documents/Papers/2026_Noise", detail: "nvim notes.tex", seconds: 60)
        let tokens = SuggestionTokens.tokens(of: item)
        #expect(tokens.isSuperset(of: [
            "c:tmux",
            "c:tmux:paper",
            "s:documents",
            "s:papers",
            "s:2026_noise",
            "s:~/documents/papers/2026_noise",
            "d:nvim",
            "d:notes.tex",
            "d:notes",
        ]))
        #expect(!tokens.contains("s:2026"))
        let site = SuggestionTokens.tokens(of: ActivityItem(context: "safari", subject: "github.com/owner/repo", detail: "", seconds: 60))
        #expect(site.isSuperset(of: ["s:github.com", "s:github.com/owner", "s:github.com/owner/repo"]))
        #expect(SuggestionTokens.titleTokens("Noise paper sync") == ["k:noise", "k:paper", "k:sync"])
        #expect(SuggestionTokens.groupToken("tmux:paper") == "g:tmux:paper")
    }
}

/// The §5.6 size targets; slow, so only with TIMETRACKING_TEST_SLOW=1.
@Suite(.tags(.slow), .enabled(if: ProcessInfo.processInfo.environment["TIMETRACKING_TEST_SLOW"] == "1"))
struct SuggestionPerformanceTests {
    @Test("PC-22 5,000 entries and 20,000 blocks build in under 2 seconds and a query takes under 20 ms")
    func sizeTargets() {
        let world = SuggestionWorld.generate()
        var entries: [TimeEntry] = []
        var blocks: [ActivityBlock] = []
        let shift = 56.0 * 86_400
        var round = 0.0
        while entries.count < 5000 || blocks.count < 20_000 {
            entries += world.entries.map { entry in
                var copy = entry
                copy.id = EntryID()
                copy.start += round * shift
                copy.end = copy.end.map { $0 + round * shift }
                return copy
            }
            blocks += world.blocks.map { block in
                ActivityBlock(
                    start: block.start + round * shift,
                    end: block.end + round * shift,
                    activeSeconds: block.activeSeconds,
                    device: block.device,
                    groupKey: block.groupKey,
                    groupShare: block.groupShare,
                    items: block.items,
                    utcOffset: block.utcOffset
                )
            }
            round += 1
        }
        let now = (entries.compactMap(\.end).max() ?? .now) + 3600
        let start = ContinuousClock.now
        let index = SuggestionIndex(examples: SuggestionTraining.examples(
            entries: entries,
            blocks: blocks,
            titles: world.titles,
            feedback: [],
            now: now,
            trainDays: 730 * 4,
            timeZone: SuggestionWorld.zone
        ))
        let build = ContinuousClock.now - start
        #expect(index.count >= 5000)
        #expect(build < .seconds(2))
        let query = SuggestionQuery(
            blocks: Array(blocks.suffix(2)),
            interval: DateInterval(start: blocks[blocks.count - 2].start, end: blocks[blocks.count - 1].end),
            timeZone: SuggestionWorld.zone
        )
        let queryStart = ContinuousClock.now
        _ = index.suggest(query)
        #expect(ContinuousClock.now - queryStart < .milliseconds(20))
    }
}
