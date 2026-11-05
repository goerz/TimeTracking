// The edit popover (timer.md §4).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct EntryEditorTests {
    private func editor(_ test: TestApp, _ entry: TimeEntry) async -> EntryEditorModel {
        let model = EntryEditorModel(store: test.store, clock: test.clock, entry: entry)
        model.undoManager = test.undo
        await model.load()
        return model
    }

    @Test("TM-18 Start keeps Stop, Stop and Duration keep Start, a Stop before Start is the next day, Date moves by days")
    func recompute() async throws {
        let test = try await TestApp()
        let entry = try await test.entry("Notes", from: "2024-03-12T09:10", to: "2024-03-12T09:35")
        let model = await editor(test, entry)
        model.startText = "9:0"
        await model.commitStart()
        #expect(try model.entry.start == (test.time("2024-03-12T09:00")))
        #expect(try model.entry.end == (test.time("2024-03-12T09:35")))
        #expect(model.durationText == "0:35:00")
        model.durationText = "1h 30m"
        await model.commitDuration()
        #expect(try model.entry.end == (test.time("2024-03-12T10:30")))
        model.stopText = "10:00"
        await model.commitStop()
        #expect(try model.entry.end == (test.time("2024-03-12T10:00")))
        model.date = try test.time("2024-03-11T12:00")
        await model.commitDate()
        #expect(try model.entry.start == (test.time("2024-03-11T09:00")))
        #expect(try model.entry.end == (test.time("2024-03-11T10:00")))
    }

    @Test("TM-50 tabbing through an unchanged Start or Stop stores nothing; an edit keeps the stored seconds")
    func unchangedFieldStoresNothing() async throws {
        let test = try await TestApp()
        // Stop within Start's minute: rewritten, it would move to the next day.
        let brief = try await test.entry("Brief", from: "2024-03-12T08:00:10", to: "2024-03-12T08:00:40")
        let briefModel = await editor(test, brief)
        await briefModel.commitStart()
        await briefModel.commitStop()
        #expect(try await test.store.entry(brief.id) == brief)

        let entry = try await test.entry("Notes", from: "2024-03-12T09:10:37", to: "2024-03-12T09:35:12")
        let model = await editor(test, entry)
        await model.commitStart()
        await model.commitStop()
        await model.commitDuration()
        #expect(try await test.store.entry(entry.id) == entry)
        model.startText = "9:05"
        await model.commitStart()
        model.stopText = "9:40"
        await model.commitStop()
        #expect(try model.entry.start == (test.date("2024-03-12T09:05:37")))
        #expect(try model.entry.end == (test.date("2024-03-12T09:40:12")))
    }

    @Test("TM-19 a commit after now is refused with Entries cannot be in the future; the running entry's Stop, Duration, Date are disabled")
    func futureAndRunning() async throws {
        let test = try await TestApp()
        let entry = try await test.entry("Notes", from: "09:10", to: "09:35")
        let model = await editor(test, entry)
        model.stopText = "10:30"
        await model.commitStop()
        #expect(model.message == "Entries cannot be in the future")
        #expect(try model.stopText == LocalDateText.time(test.time("09:35")))
        #expect(try await test.store.entry(entry.id)?.end == (test.time("09:35")))
        let running = try await test.store.start(projectID: nil, task: "Now", at: test.time("09:50"))
        let live = await editor(test, running)
        #expect(live.isRunning)
        #expect(live.stopText == "running")
        test.clock.advance(by: 5)
        #expect(live.durationDisplay(at: test.clock.now) == "0:10:05")
        #expect(EntryFieldEdit.stop(0).isDisabledWhileRunning)
        #expect(EntryFieldEdit.duration(0).isDisabledWhileRunning)
        #expect(EntryFieldEdit.date(running.day).isDisabledWhileRunning)
    }

    @Test("TM-20 Stop 00:35 on an entry from 23:10 stores one entry ending at 00:35")
    func midnight() async throws {
        let test = try await TestApp()
        let entry = try await test.entry("Night", from: "2024-03-12T23:10", to: "2024-03-12T23:50")
        let model = await editor(test, entry)
        model.stopText = "0:35"
        await model.commitStop()
        #expect(model.entry.id == entry.id)
        #expect(try model.entry.end == (test.time("2024-03-13T00:35")))
        #expect(try await test.store.entry(entry.id) == model.entry)
    }

    @Test("TM-21 an edit of an entry across midnight acts on the whole entry")
    func wholeEntryEdits() async throws {
        let test = try await TestApp()
        let entry = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Night",
            start: test.time("2024-03-12T23:10"),
            end: test.time("2024-03-13T00:35")
        ))
        let model = await editor(test, entry)
        model.task = "Late night"
        await model.commitTask()
        #expect(try await test.store.entry(entry.id)?.task == "Late night")
        model.startText = "23:20"
        await model.commitStart()
        let stored = try #require(try await test.store.entry(entry.id))
        #expect(try stored.start == test.time("2024-03-12T23:20"))
        #expect(try stored.end == test.time("2024-03-13T00:35"))
    }

    @Test("TM-55 the popover's task field suggests earlier tasks; a choice stores task and project in one undoable edit")
    func taskAutocompletion() async throws {
        let test = try await TestApp()
        let project = try await test.projects(["Noise Model"])[0]
        try await test.entry("Clarify noise model", project, from: "08:00", to: "08:30")
        let entry = try await test.entry("", from: "09:00", to: "09:30")
        let model = await editor(test, entry)
        await model.taskEdited("clar")
        #expect(model.task == "clar")
        #expect(model.taskField.suggestions.map(\.task) == ["Clarify noise model"])
        await model.submitTask()
        let stored = try #require(try await test.store.entry(entry.id))
        #expect(stored.task == "Clarify noise model" && stored.projectID == project.id)
        #expect(model.task == "Clarify noise model")
        #expect(!model.taskField.isShowingSuggestions)
        test.undo.undo()
        var restored = try await test.store.entry(entry.id)
        for _ in 0 ..< 10_000 where restored?.projectID != nil {
            await Task.yield()
            restored = try await test.store.entry(entry.id)
        }
        #expect(restored?.task.isEmpty == true && restored?.projectID == nil)

        // Escape closes the suggestions and Return then commits the text.
        let plain = await editor(test, entry)
        await plain.taskEdited("clar")
        #expect(plain.taskField.escape(text: plain.task))
        await plain.submitTask()
        #expect(try await test.store.entry(entry.id)?.task == "clar")
    }

    @Test("TM-22 an overlapping change shows the notice; Keep stores it, Revert restores the field")
    func overlap() async throws {
        let test = try await TestApp()
        try await test.entry("Morning Review", from: "09:00", to: "09:25")
        let entry = try await test.entry("Notes", from: "09:30", to: "09:45")
        let model = await editor(test, entry)
        model.startText = "9:20"
        await model.commitStart()
        let notice = try #require(model.overlap)
        let range = try "\(LocalDateText.time(test.time("09:00"))) to \(LocalDateText.time(test.time("09:25")))"
        #expect(notice.text == "Overlaps “Morning Review” (\(range))")
        #expect(try await test.store.entry(entry.id)?.start == (test.time("09:30")))
        model.revertOverlap()
        #expect(model.overlap == nil)
        #expect(try model.startText == LocalDateText.time(test.time("09:30")))
        model.startText = "9:20"
        await model.commitStart()
        await model.keepOverlap()
        #expect(try await test.store.entry(entry.id)?.start == (test.time("09:20")))
    }

    @Test("TM-37 the running entry's editor shows its task before loading; a commit before the load or a Start edit keeps the task")
    func runningTaskBeforeLoad() async throws {
        let test = try await TestApp()
        let running = try await test.store.start(projectID: nil, task: "Prepare methods", at: test.time("09:35"))
        await test.app.afterChange()
        let model = EntryEditorModel(store: test.store, clock: test.clock, entry: running)
        model.onChange = { await test.app.afterChange() }
        // The popover's task field loses focus before `load()` returned.
        #expect(model.task == "Prepare methods")
        #expect(try model.startText == LocalDateText.time(test.time("09:35")))
        await model.commitTask()
        await model.commitStart()
        #expect(try await test.store.entry(running.id)?.task == "Prepare methods")
        // A task typed before the load survives it.
        model.task = "Prepare methods and results"
        await model.load()
        #expect(model.task == "Prepare methods and results")
        // A Start edit keeps the task in the store, the editor, and the bar.
        model.task = "Prepare methods"
        model.startText = "9:20"
        await model.commitStart()
        let stored = try #require(try await test.store.entry(running.id))
        #expect(try stored.start == test.time("09:20"))
        #expect(stored.task == "Prepare methods")
        #expect(model.task == "Prepare methods")
        #expect(test.app.timer.taskText == "Prepare methods")
        #expect(test.app.timer.elapsedSeconds(at: test.clock.now) == 40 * 60)
    }

    @Test("TM-37 opening the running entry's editor stores the task typed in the bar first; a task edited in the editor shows in the bar")
    func runningTaskFromBar() async throws {
        let test = try await TestApp()
        let running = try await test.store.start(projectID: nil, task: "Prepare methods", at: test.time("09:35"))
        await test.app.afterChange()
        // The debounce never fires on its own: the task is still pending.
        test.app.timer.debounce = { _ in try await Task.sleep(for: .seconds(3600)) }
        test.app.timer.taskText = "Outline results"
        test.app.timer.taskTextChanged()
        #expect(try await test.store.entry(running.id)?.task == "Prepare methods")
        let view = test.app.mainTimer
        await test.app.editRunningEntry(in: view).value
        #expect(view.editing == running.id)
        #expect(try await test.store.entry(running.id)?.task == "Outline results")
        let entry = try #require(test.app.timer.running)
        let model = EntryEditorModel(store: test.store, clock: test.clock, entry: entry)
        model.onChange = { await test.app.afterChange() }
        await model.load()
        #expect(model.task == "Outline results")
        model.startText = "9:20"
        await model.commitStart()
        #expect(test.app.timer.taskText == "Outline results")
        model.task = "Draft results"
        await model.commitTask()
        #expect(test.app.timer.taskText == "Draft results")
        #expect(test.app.timer.running?.task == "Draft results")
    }
}
