// ⌘F and the Timer list's filter field (timer.md §3).

import Testing
@testable import TimeTracking

@MainActor
struct TimerFilterFocusTests {
    @Test("TM-17 every ⌘F asks for the focus, also with the filter field shown")
    func requests() async throws {
        let test = try await TestApp()
        let list = test.app.activeTimer.list
        list.showFilter()
        list.showFilter()
        #expect(list.isFilterVisible)
        #expect(list.filterFocusRequests == 2)
    }
}
