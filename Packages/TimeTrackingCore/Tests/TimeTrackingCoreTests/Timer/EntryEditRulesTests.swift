// The entry editor's handling of stored seconds (spec_timer.md §4.1).

import Foundation
import Testing
import TimeTrackingCore

struct EntryEditRulesTests {
    @Test("TM-50 a Start or Stop in whole minutes keeps the stored seconds, so the shown time changes nothing; typed seconds apply")
    func editKeepsSeconds() async throws {
        let test = try await TestStore(now: "2024-03-14T10:00")
        let entry = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "",
            start: test.date("2024-03-13T09:10:37"),
            end: test.date("2024-03-13T09:35:12")
        ))[0]
        func result(_ edit: EntryFieldEdit) -> Result<EntryEditResult, EntryEditError> {
            EntryEditRules.apply(edit, to: entry, now: test.clock.now)
        }
        let unchanged = EntryEditResult(start: entry.start, end: entry.end)
        #expect(result(.start(9 * 3600 + 10 * 60)) == .success(unchanged))
        #expect(result(.stop(9 * 3600 + 35 * 60)) == .success(unchanged))
        #expect(try result(.start(9 * 3600 + 5 * 60)) == .success(EntryEditResult(start: test.date("2024-03-13T09:05:37"), end: entry.end)))
        #expect(try result(.stop(9 * 3600 + 40 * 60)) == .success(EntryEditResult(
            start: entry.start,
            end: test.date("2024-03-13T09:40:12")
        )))
        #expect(try result(.start(9 * 3600 + 5 * 60 + 9)) == .success(EntryEditResult(
            start: test.date("2024-03-13T09:05:09"),
            end: entry.end
        )))
    }
}
