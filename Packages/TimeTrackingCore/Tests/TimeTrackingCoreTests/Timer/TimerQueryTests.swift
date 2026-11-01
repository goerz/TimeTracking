// Queries and writes behind the Timer, the entry editor, and the
// project picker (spec_timer.md §2 to §4, spec_projects.md §3, §5).

import Foundation
import Testing
import TimeTrackingCore

struct TimerQueryTests {
    @Test("TM-8 three characters give at most 8 (task, project) suggestions, the current project's first")
    func completions() async throws {
        let test = try await TestStore()
        let structure = try await test.structure(projects: ["Noise", "Other"])
        let noise = structure.projects[0].id
        let other = structure.projects[1].id
        var start = try test.date("2024-03-13T08:00")
        for index in 0 ..< 10 {
            _ = try await test.store.create(EntryDraft(projectID: other, task: "Clarify item \(index)", start: start, end: start + 60))
            start += 120
        }
        _ = try await test.store.create(EntryDraft(projectID: noise, task: "Clarify noise model", start: start - 7200, end: start - 7100))
        _ = try await test.store.create(EntryDraft(projectID: noise, task: "clarify NOISE model", start: start - 7000, end: start - 6900))
        let suggestions = try await test.store.taskCompletions(containing: "cla", preferredProject: noise)
        #expect(suggestions.count == 8)
        #expect(suggestions.first?.projectID == noise)
        // One pair per (task, project), with the latest spelling.
        #expect(suggestions.first?.task == "clarify NOISE model")
        #expect(suggestions.dropFirst().allSatisfy { $0.projectID == other })
        // Most recent first after the preferred project.
        #expect(suggestions[1].task == "Clarify item 9")
        // Substring, case- and diacritic-insensitive.
        let inner = try await test.store.taskCompletions(containing: "NÖISE", preferredProject: nil)
        #expect(inner.map(\.task) == ["clarify NOISE model"])
    }

    @Test("TM-10 PP-24 the picker search finds the project of a task tracked within 90 days, not one tracked 100 days ago")
    func pickerTaskMatching() async throws {
        let test = try await TestStore()
        let structure = try await test.structure(projects: ["Model", "Paper"])
        let recent = try test.date("2024-02-13T09:00")
        let old = try test.date("2023-12-05T09:00")
        _ = try await test.store.create(EntryDraft(
            projectID: structure.projects[0].id,
            task: "Clarify noise model",
            start: recent,
            end: recent + 600
        ))
        _ = try await test.store.create(EntryDraft(
            projectID: structure.projects[1].id,
            task: "Clarify the draft",
            start: old,
            end: old + 600
        ))
        let noise = try await test.store.pickerContent(search: "noise", taskMatching: true)
        #expect(noise.groups.flatMap(\.rows).map(\.project.name) == ["Model"])
        let clarify = try await test.store.pickerContent(search: "clarify", taskMatching: true)
        #expect(clarify.groups.flatMap(\.rows).map(\.project.name) == ["Model"])
        let withoutTasks = try await test.store.pickerContent(search: "clarify", taskMatching: false)
        #expect(withoutTasks.groups.isEmpty)
    }

    @Test("PP-22 the picker lists No Project, five Recent active projects newest first, then client groups by area order and name")
    func pickerLayout() async throws {
        let test = try await TestStore()
        let (beta, betaGeneral) = try await test.store.createClient(name: "Beta")
        let (alpha, _) = try await test.store.createClient(name: "alpha")
        let research = try await test.store.createArea(AreaDraft(clientID: alpha.id, name: "Research"))
        let teaching = try await test.store.createArea(AreaDraft(clientID: alpha.id, name: "Teaching"))
        var projects: [Project] = []
        for (index, name) in ["P1", "P2", "P3", "P4", "P5", "P6", "P7"].enumerated() {
            let area = index < 3 ? teaching.id : research.id
            try await projects.append(test.store.createProject(ProjectDraft(areaID: area, name: name)))
        }
        let general = try await test.store.createProject(ProjectDraft(areaID: betaGeneral.id, name: "Admin"))

        // Two tracked projects: two Recent rows.
        var start = try test.date("2024-03-14T07:00")
        for project in [projects[0], general] {
            _ = try await test.store.create(EntryDraft(projectID: project.id, task: "", start: start, end: start + 60))
            start += 120
        }
        var content = try await test.store.pickerContent(search: "")
        #expect(content.showsNoProject)
        #expect(content.recent.map(\.project.name) == ["Admin", "P1"])
        #expect(content.recent.map(\.trailing) == ["Beta", "alpha · Teaching"])
        #expect(content.groups.map(\.client.name) == ["alpha", "Beta"])
        // Research was created first, so it precedes Teaching.
        #expect(content.groups[0].rows.map(\.project.name) == ["P4", "P5", "P6", "P7", "P1", "P2", "P3"])
        #expect(content.groups[1].rows.map(\.trailing) == [""])
        #expect(content.items.first == .noProject)
        #expect(content.initialHighlight(current: general.id) == .recent(general.id))
        #expect(content.initialHighlight(current: projects[6].id) == .project(projects[6].id))
        #expect(content.initialHighlight(current: nil) == .recent(general.id))

        // Six tracked projects, the latest archived: five Recent, the sixth fills in.
        for project in projects.dropFirst() {
            _ = try await test.store.create(EntryDraft(projectID: project.id, task: "", start: start, end: start + 60))
            start += 120
        }
        try await test.store.archive(projects[6].id)
        content = try await test.store.pickerContent(search: "")
        #expect(content.recent.map(\.project.name) == ["P6", "P5", "P4", "P3", "P2"])
        #expect(!content.groups.flatMap(\.rows).contains { $0.project.name == "P7" })
        _ = beta
    }

    @Test("PP-23 typing hides Recent; Create Project appears for a new name and not for an existing one, folded")
    func pickerSearch() async throws {
        let test = try await TestStore()
        let structure = try await test.structure(projects: ["Noise Model", "Website"])
        let start = try test.date("2024-03-14T08:00")
        _ = try await test.store.create(EntryDraft(projectID: structure.projects[0].id, task: "", start: start, end: start + 60))
        let content = try await test.store.pickerContent(search: "noise")
        #expect(content.recent.isEmpty)
        #expect(!content.showsNoProject)
        #expect(content.groups.flatMap(\.rows).map(\.project.name) == ["Noise Model"])
        #expect(content.createName == "noise")
        #expect(content.initialHighlight(current: nil) == .project(structure.projects[0].id))
        #expect(try await test.store.pickerContent(search: " NOISE model ").createName == nil)
        #expect(try await test.store.pickerContent(search: "x").createName == "x")
        // Every word must match some name.
        #expect(try await test.store.pickerContent(search: "noise research").groups.count == 1)
        #expect(try await test.store.pickerContent(search: "noise teaching").groups.isEmpty)
    }

    @Test("PP-16 a name differing only in case or diacritics is taken within the client and free under another")
    func projectNameUniqueness() async throws {
        let test = try await TestStore()
        let first = try await test.structure(projects: ["Résumé"])
        let second = try await test.structure(projects: [])
        #expect(try await test.store.projectNameIsTaken(" resume ", client: first.client.id))
        #expect(try await !test.store.projectNameIsTaken("resume", client: second.client.id))
        #expect(try await !test.store.projectNameIsTaken("resume", client: first.client.id, excluding: first.projects[0].id))
        // Archived projects still count.
        try await test.store.archive(first.projects[0].id)
        #expect(try await test.store.projectNameIsTaken("RESUME", client: first.client.id))
    }

    @Test("TM-21 a task change on one piece of a chain changes every piece; a Start change only that piece")
    func chainEdits() async throws {
        let test = try await TestStore(now: "2024-03-14T10:00")
        let pieces = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Night",
            start: test.date("2024-03-13T23:10"),
            end: test.date("2024-03-14T00:35")
        ))
        #expect(pieces.count == 2)
        let chain = try await test.store.chain(of: pieces[1].id)
        #expect(try chain.map(\.start) == [test.date("2024-03-13T23:10"), test.date("2024-03-14T00:00")])
        try await test.store.updateChain(of: pieces[1].id, task: "Late night")
        #expect(try await test.store.chain(of: pieces[0].id).map(\.task) == ["Late night", "Late night"])
        _ = try await test.store.update(pieces[1].id, EntryChange(start: test.date("2024-03-14T00:10")))
        let after = try await test.store.chain(of: pieces[0].id)
        #expect(try after.map(\.start) == [test.date("2024-03-13T23:10"), test.date("2024-03-14T00:10")])
    }

    @Test("TM-18 TM-19 TM-20 the editor recomputes, moves by days, refuses the future, disables running fields, and splits at midnight")
    func editRules() async throws {
        let test = try await TestStore(now: "2024-03-14T10:00")
        let now = test.clock.now
        let pieces = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "",
            start: test.date("2024-03-13T09:10"),
            end: test.date("2024-03-13T09:35")
        ))
        let entry = pieces[0]
        func result(_ edit: EntryFieldEdit, _ target: TimeEntry = entry) -> Result<EntryEditResult, EntryEditError> {
            EntryEditRules.apply(edit, to: target, now: now)
        }
        // Start keeps Stop.
        #expect(try result(.start(9 * 3600)) == .success(EntryEditResult(
            start: test.date("2024-03-13T09:00"),
            end: test.date("2024-03-13T09:35")
        )))
        // Stop keeps Start; a Stop before Start is the next day.
        #expect(try result(.stop(10 * 3600)) == .success(EntryEditResult(start: entry.start, end: test.date("2024-03-13T10:00"))))
        #expect(try result(.stop(9 * 3600)) == .success(EntryEditResult(start: entry.start, end: test.date("2024-03-14T09:00"))))
        // Duration keeps Start.
        #expect(try result(.duration(3600)) == .success(EntryEditResult(start: entry.start, end: test.date("2024-03-13T10:10"))))
        // Date moves by whole days.
        #expect(try result(.date(TrackingDay(year: 2024, month: 3, day: 11))) == .success(EntryEditResult(
            start: test.date("2024-03-11T09:10"),
            end: test.date("2024-03-11T09:35")
        )))
        // TM-19: the future is refused.
        #expect(result(.date(TrackingDay(year: 2024, month: 3, day: 15))) == .failure(.inFuture))
        #expect(try result(.stop(11 * 3600 + 13 * 60)) == .success(EntryEditResult(start: entry.start, end: test.date("2024-03-13T11:13"))))
        #expect(result(.duration(26 * 3600)) == .failure(.inFuture))
        // TM-19: Stop, Duration, and Date are disabled for the running entry.
        let running = try await test.store.start(projectID: nil, task: "", at: test.date("2024-03-14T09:00"))
        #expect(result(.stop(9 * 3600 + 30 * 60), running) == .failure(.runningEntry))
        #expect(result(.duration(60), running) == .failure(.runningEntry))
        #expect(result(.date(running.day), running) == .failure(.runningEntry))
        #expect(try result(.start(8 * 3600), running) == .success(EntryEditResult(start: test.date("2024-03-14T08:00"), end: nil)))
        _ = try await test.store.stop(at: now)

        // TM-20: Stop 00:35 on an entry starting 23:10 stores two pieces.
        let late = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "",
            start: test.date("2024-03-12T23:10"),
            end: test.date("2024-03-12T23:50")
        ))[0]
        let change = try EntryEditRules.apply(.stop(35 * 60), to: late, now: now).get()
        let stored = try await test.store.update(late.id, change.change)
        #expect(stored.count == 2)
        #expect(try stored[0].end == (test.date("2024-03-13T00:00")))
        #expect(try stored[1].end == (test.date("2024-03-13T00:35")))
    }

    @Test("TM-13 TM-14 an entry running since 23:10 counts 0:55:00 at 00:05 by its chain start; today's total grows with the clock")
    func chainStartAndTotals() async throws {
        let test = try await TestStore(now: "2024-03-13T23:30")
        let running = try await test.store.start(projectID: nil, task: "Night", at: test.date("2024-03-13T23:10"))
        try test.clock.set(test.date("2024-03-14T00:05"))
        try await test.store.checkInvariants()
        let current = try #require(try await test.store.runningEntry())
        #expect(current.id != running.id)
        let chainStart = try await test.store.chainStart(of: current.id)
        #expect(DurationText.clock(Int(test.clock.now.timeIntervalSince(chainStart))) == "0:55:00")
        let today = TrackingDay(year: 2024, month: 3, day: 14)
        var days = try await test.store.days(ending: today, count: 2)
        #expect(days[0].totalSeconds == 300)
        #expect(days[1].totalSeconds == 50 * 60)
        test.clock.advance(by: 1)
        days = try await test.store.days(ending: today, count: 1)
        #expect(days[0].totalSeconds == 301)
    }

    @Test("TM-14 the running entry is Today's first row with its project; today's total includes it")
    func runningRow() async throws {
        let test = try await TestStore(now: "2024-03-14T10:00")
        try await test.store.start(projectID: nil, task: "Earlier", at: test.date("2024-03-14T09:00"))
        let running = try await test.store.start(projectID: nil, task: "Now", at: test.date("2024-03-14T09:30"))
        let list = try await test.store.timerList(dayLimit: 14)
        let today = try #require(list.first)
        #expect(today.runningListing?.id == running.id)
        #expect(today.runningListing?.project == nil)
        #expect(today.rows.map(\.entry.task) == ["Earlier"])
        #expect(today.totalSeconds(at: test.clock.now) == 3600)
        // A filter that misses the running entry hides its row and its seconds.
        let filtered = try #require(try await test.store.timerList(dayLimit: 14, filter: "earl").first)
        #expect(filtered.runningListing == nil)
        #expect(filtered.totalSeconds(at: test.clock.now) == 1800)
    }

    @Test("durations and times of day format and parse as the editor and bar read them")
    func durationText() {
        #expect(DurationText.clock(2547) == "0:42:27")
        #expect(DurationText.hoursMinutes(273) == "0:04")
        #expect(DurationText.hoursMinutes(25 * 3600) == "25:00")
        #expect(DurationText.parseDuration("25m") == 1500)
        #expect(DurationText.parseDuration("1h 30m") == 5400)
        #expect(DurationText.parseDuration("1:30") == 5400)
        #expect(DurationText.parseDuration("0:25:00") == 1500)
        #expect(DurationText.parseDuration("abc") == nil)
        #expect(DurationText.parseTimeOfDay("9:1") == 9 * 3600 + 600)
        #expect(DurationText.parseTimeOfDay("14:02") == 14 * 3600 + 120)
        #expect(DurationText.parseTimeOfDay("9:10 pm") == 21 * 3600 + 600)
        #expect(DurationText.parseTimeOfDay("12 am") == 0)
        #expect(DurationText.parseTimeOfDay("25:00") == nil)
    }
}
