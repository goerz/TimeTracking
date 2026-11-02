// The iPhone Timer: card, picker, project dialog, list, and edit sheet
// (spec_ios.md §2).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingiOS

@MainActor
struct TimerScreenTests {
    @Test("IOS-1 Start with an empty field and no project runs an empty entry; a second start stops the first at its start")
    func startEmpty() async throws {
        let test = try await TestPhone()
        await test.model.timer.start()
        let first = try #require(test.model.timer.running)
        #expect(first.task.isEmpty)
        #expect(first.projectID == nil)
        test.clock.advance(by: 600)
        test.model.timer.taskText = "Second"
        await test.model.timer.start()
        let second = try #require(test.model.timer.running)
        #expect(second.id != first.id)
        #expect(try await test.store.entry(first.id)?.end == second.start)
        #expect(test.scheduler.authorizationRequests == 1)
    }

    @Test("IOS-2 Return starts an entry while nothing runs and commits the task while one runs")
    func returnKey() async throws {
        let test = try await TestPhone()
        test.model.timer.taskText = "Write intro"
        await test.model.timer.submitTask()
        let running = try #require(test.model.timer.running)
        #expect(running.task == "Write intro")
        test.model.timer.taskText = "Write introduction"
        await test.model.timer.submitTask()
        #expect(try await test.store.entry(running.id)?.task == "Write introduction")
        #expect(try await test.store.runningEntry()?.id == running.id)
    }

    @Test("IOS-3 typing @hou opens the picker with search hou; choosing Household assigns it and removes @hou")
    func atTrigger() async throws {
        let test = try await TestPhone()
        let household = try await test.projects(["Household", "Paper"])[0]
        test.model.timer.taskText = "Order toner"
        await test.model.timer.start()
        test.model.timer.taskText = "Order toner @hou"
        let trigger = try #require(TaskFieldModel.trigger(in: test.model.timer.taskText))
        test.model.openPicker(search: trigger.query)
        guard case let .picker(picker) = test.model.sheet else {
            Issue.record("no picker sheet")
            return
        }
        #expect(picker.search == "hou")
        await picker.reload()
        #expect(picker.chooseHighlighted() == .project(household.id))
        await test.model.choose(.project(household.id))
        #expect(test.model.sheet == nil)
        let running = try #require(try await test.store.runningEntry())
        #expect(running.projectID == household.id)
        #expect(running.task == "Order toner")
        #expect(test.model.timer.taskText == "Order toner")
    }

    @Test("IOS-4 Create Project from the picker with a new client and area creates all three and assigns the project")
    func createFromPicker() async throws {
        let test = try await TestPhone()
        await test.model.timer.start()
        test.model.openPicker(search: "Garden")
        await test.model.choose(.create("Garden"))
        let dialog = try #require(test.model.dialogModel)
        await dialog.load()
        // "New Client…" and "New Area…" in the dialog: the forms' Create.
        let clientForm = await ClientFormModel.create(store: test.store)
        clientForm.name = "Family"
        await clientForm.validate()
        let (client, general) = try #require(await clientForm.submit())
        await dialog.clientCreated(client, general: general)
        let areaForm = await AreaFormModel.create(store: test.store, client: client.id)
        areaForm.name = "Outdoors"
        areaForm.color = "#3A7D44"
        await areaForm.validate()
        let area = try #require(await areaForm.submit())
        await dialog.areaCreated(area)
        let project = try #require(await dialog.submit())
        await test.model.dialogFinished(project)
        #expect(test.model.sheet == nil)
        let rows = try await test.store.projects(filter: ProjectFilter(state: .all))
        let row = try #require(rows.first { $0.project.name == "Garden" })
        #expect(row.client?.name == "Family")
        #expect(row.area?.name == "Outdoors")
        #expect(row.area?.color == "#3A7D44")
        #expect(try await test.store.clients(includeRetired: true).map(\.name).contains("Family"))
        #expect(try await test.store.runningEntry()?.projectID == project.id)
    }

    @Test("IOS-5 Continue on a row with an archived project shows the restore alert; Cancel starts nothing")
    func archivedContinue() async throws {
        let test = try await TestPhone()
        let old = try await test.projects(["Old"])[0]
        let entry = try await test.store.create(EntryDraft(
            projectID: old.id,
            task: "Archive me",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T09:00")
        ))
        try await test.store.archive(old.id)
        await test.model.fanOut(structureChanged: true)
        await test.model.timer.continueEntry(entry[0].id)
        #expect(test.model.timer.alert == .restoreProject(entry[0].id, projectName: "Old"))
        test.model.timer.alert = nil
        #expect(try await test.store.runningEntry() == nil)
    }

    @Test("IOS-6 a row's Continue (play button or full leading swipe) continues it")
    func rowContinue() async throws {
        let test = try await TestPhone()
        let entry = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Read",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T09:00")
        ))
        await test.model.fanOut(structureChanged: false)
        #expect(test.model.list.rows.map(\.id) == [entry[0].id])
        await test.model.timer.continueEntry(entry[0].id)
        #expect(test.model.timer.running?.task == "Read")
    }

    @Test("IOS-7 at 00:30 an entry started at 23:00 shows 1:30:00 before and after the split; Today holds 0:30:00 of it")
    func chainElapsed() async throws {
        let test = try await TestPhone(now: "2024-03-14T23:00")
        await test.model.timer.start()
        try test.clock.set(test.date("2024-03-15T00:30"))
        await test.model.timer.refresh()
        #expect(test.model.timer.timerText(at: test.clock.now) == "1:30:00")
        try await test.store.checkInvariants()
        await test.model.fanOut(structureChanged: false)
        #expect(test.model.timer.timerText(at: test.clock.now) == "1:30:00")
        let today = try #require(test.model.list.days.first)
        #expect(test.model.list.title(for: today.day) == "Today")
        #expect(today.totalSeconds(at: test.clock.now) == 1800)
    }

    @Test("IOS-8 saving 23:00 to 01:00 splits at midnight; future and reversed ends are refused; an overlap offers Keep and Revert")
    func editSheet() async throws {
        let test = try await TestPhone(now: "2024-03-15T10:00")
        let entry = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Late",
            start: test.date("2024-03-14T22:00"),
            end: test.date("2024-03-14T22:30")
        ))[0]
        let editor = EntryEditSheetModel(store: test.store, clock: test.clock)
        await editor.load(entry.id)
        editor.start = try test.date("2024-03-14T23:00")
        editor.end = try test.date("2024-03-15T01:00")
        #expect(editor.midnightNoticeText == EntryEditSheetModel.midnightNotice)
        #expect(await editor.save())
        let pieces = try await test.store.entries(
            in: DateInterval(start: test.date("2024-03-14T00:00"), end: test.date("2024-03-16T00:00")),
            includeDeleted: false
        )
        #expect(pieces.count == 2)
        #expect(Set(pieces.map(\.rootID)).count == 1)

        let other = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Morning",
            start: test.date("2024-03-15T08:00"),
            end: test.date("2024-03-15T09:00")
        ))[0]
        let second = EntryEditSheetModel(store: test.store, clock: test.clock)
        await second.load(other.id)
        second.end = try test.date("2024-03-15T11:00")
        #expect(await second.save() == false)
        #expect(second.message == EntryEditSheetModel.futureMessage)
        second.end = try test.date("2024-03-15T07:00")
        #expect(await second.save() == false)
        #expect(second.message == EntryEditSheetModel.orderMessage)

        second.start = try test.date("2024-03-15T00:30")
        second.end = try test.date("2024-03-15T09:00")
        #expect(await second.save() == false)
        #expect(second.overlap?.hasPrefix("Overlaps “Late”") == true)
        second.revertOverlap()
        #expect(second.start == other.start)
        second.start = try test.date("2024-03-15T00:30")
        #expect(await second.save() == false)
        #expect(await second.keepOverlap())
        #expect(try await test.store.entry(other.id)?.start == test.date("2024-03-15T00:30"))
    }

    @Test("IOS-8 the running entry's sheet changes only start, task, and project")
    func editRunning() async throws {
        let test = try await TestPhone()
        await test.model.timer.start()
        let running = try #require(test.model.timer.running)
        let editor = EntryEditSheetModel(store: test.store, clock: test.clock)
        await editor.load(running.id)
        #expect(editor.isRunning)
        editor.start = test.clock.now - 600
        editor.task = "Renamed"
        #expect(await editor.save())
        let stored = try #require(try await test.store.entry(running.id))
        #expect(stored.isRunning)
        #expect(stored.start == test.clock.now - 600)
        #expect(stored.task == "Renamed")
    }

    @Test("IOS-42 the running entry's sheet keeps a task stored after it loaded; a Start or project change writes only that field")
    func editRunningKeepsTask() async throws {
        let test = try await TestPhone()
        let projects = try await test.projects(["Household"])
        test.model.timer.taskText = "Prepare methods"
        await test.model.timer.start()
        let running = try #require(test.model.timer.running)
        let editor = EntryEditSheetModel(store: test.store, clock: test.clock)
        await editor.load(running.id)
        // The card's field commits a new task while the sheet is open.
        test.model.timer.taskText = "Outline results"
        await test.model.timer.commitTask()
        editor.start = test.clock.now - 1200
        await editor.setProject(projects[0].id)
        #expect(await editor.save())
        let stored = try #require(try await test.store.entry(running.id))
        #expect(stored.task == "Outline results")
        #expect(stored.projectID == projects[0].id)
        #expect(stored.start == test.clock.now - 1200)
        await test.model.localWrite()
        #expect(test.model.timer.taskText == "Outline results")
        #expect(test.model.timer.elapsedSeconds(at: test.clock.now) == 1200)
    }
}
