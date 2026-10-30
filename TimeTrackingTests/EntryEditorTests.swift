// The edit popover (spec_timer_window.md §4).

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

    @Test("TW-18 Start keeps Stop, Stop and Duration keep Start, a Stop before Start is the next day, Date moves by days")
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

    @Test("TW-19 a commit after now is refused with Entries cannot be in the future; the running entry's Stop, Duration, Date are disabled")
    func futureAndRunning() async throws {
        let test = try await TestApp()
        let entry = try await test.entry("Notes", from: "09:10", to: "09:35")
        let model = await editor(test, entry)
        model.stopText = "10:30"
        await model.commitStop()
        #expect(model.message == "Entries cannot be in the future")
        #expect(try model.stopText == EntryEditorModel.time(test.time("09:35")))
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

    @Test("TW-20 Stop 00:35 on an entry from 23:10 stores two pieces and shows Continues on the next day until 00:35")
    func midnight() async throws {
        let test = try await TestApp()
        let entry = try await test.entry("Night", from: "2024-03-12T23:10", to: "2024-03-12T23:50")
        let model = await editor(test, entry)
        model.stopText = "0:35"
        await model.commitStop()
        let chain = try await test.store.chain(of: entry.id)
        #expect(chain.count == 2)
        #expect(model.entry.id == entry.id)
        #expect(try model.entry.end == (test.time("2024-03-13T00:00")))
        let next = try EntryEditorModel.day(test.time("2024-03-13T00:00"))
        #expect(try model.chainLines == ["Continues on \(next) until \(EntryEditorModel.time(test.time("2024-03-13T00:35")))"])
        let second = await editor(test, chain[1])
        #expect(second.chainLines == ["Continued from \(EntryEditorModel.day(entry.start)), \(EntryEditorModel.time(entry.start))"])
    }

    @Test("TW-21 a task change on one piece changes every piece; a Start change only that piece")
    func chainEdits() async throws {
        let test = try await TestApp()
        let pieces = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Night",
            start: test.time("2024-03-12T23:10"),
            end: test.time("2024-03-13T00:35")
        ))
        let model = await editor(test, pieces[1])
        model.task = "Late night"
        await model.commitTask()
        #expect(try await test.store.chain(of: pieces[0].id).map(\.task) == ["Late night", "Late night"])
        model.startText = "0:10"
        await model.commitStart()
        let chain = try await test.store.chain(of: pieces[0].id)
        #expect(try chain.map(\.start) == [test.time("2024-03-12T23:10"), test.time("2024-03-13T00:10")])
    }

    @Test("TW-22 an overlapping change shows the notice; Keep stores it, Revert restores the field")
    func overlap() async throws {
        let test = try await TestApp()
        try await test.entry("Morning Review", from: "09:00", to: "09:25")
        let entry = try await test.entry("Notes", from: "09:30", to: "09:45")
        let model = await editor(test, entry)
        model.startText = "9:20"
        await model.commitStart()
        let notice = try #require(model.overlap)
        let range = try "\(EntryEditorModel.time(test.time("09:00"))) to \(EntryEditorModel.time(test.time("09:25")))"
        #expect(notice.text == "Overlaps “Morning Review” (\(range))")
        #expect(try await test.store.entry(entry.id)?.start == (test.time("09:30")))
        model.revertOverlap()
        #expect(model.overlap == nil)
        #expect(try model.startText == EntryEditorModel.time(test.time("09:30")))
        model.startText = "9:20"
        await model.commitStart()
        await model.keepOverlap()
        #expect(try await test.store.entry(entry.id)?.start == (test.time("09:20")))
    }
}
