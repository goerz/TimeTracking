// The iPad's tabs, keyboard commands, calendar access, drawing, and the
// Planner's iPad wiring on the view models (spec_ios.md §2.3, §6.4, §10;
// spec_planner_calendar.md §3.3; spec_planner_activity.md §5). The idiom is
// injected, so these run on the iPhone simulator.

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingiOS

@MainActor
struct PadTests {
    /// An iPad over in-memory calendars (access not yet asked) and `blocks`.
    static func pad(
        events: InMemoryCalendarEventStore = InMemoryCalendarEventStore(access: .notDetermined),
        blocks: [ActivityBlock] = []
    ) async throws -> TestPhone {
        try await TestPhone(settings: .ephemeral(isPad: true), pad: { store, clock, device in
            PadPlanner(store: store, clock: clock, device: device, activity: InMemoryActivityStore(blocks: blocks), events: events)
        })
    }

    static func block(_ start: String, _ end: String, open: Bool = false) throws -> ActivityBlock {
        let begin = try TestPhone.date("2024-03-14T\(start)")
        let finish = try TestPhone.date("2024-03-14T\(end)")
        let seconds = Int(finish.timeIntervalSince(begin) * 0.9)
        return ActivityBlock(
            start: begin,
            end: finish,
            activeSeconds: seconds,
            device: "macbook",
            groupKey: "tmux:paper",
            groupShare: 1,
            items: [ActivityItem(context: "tmux:paper", subject: "~/Papers", detail: "", seconds: seconds)],
            utcOffset: TimeZone.current.secondsFromGMT(for: begin),
            isOpen: open
        )
    }

    @Test(
        "IOS-33 the iPhone has no Planner and no calendar store; the iPad asks for calendar access only when the Calendar tab first opens"
    )
    func calendarAccess() async throws {
        let phone = try await TestPhone()
        #expect(phone.model.pad == nil)
        let router = PhoneURLRouter(model: phone.model, scheme: "timetracking")
        try await router.open(#require(URL(string: "timetracking://planner/calendar")))
        #expect(phone.model.pad == nil)
        await phone.model.perform(.calendar)
        #expect(phone.model.pad == nil)

        let events = InMemoryCalendarEventStore(access: .notDetermined)
        let test = try await Self.pad(events: events)
        let pad = try #require(test.model.pad)
        await test.model.timer.start()
        await test.model.storeChanged(.entries([]))
        for tab in [PadTab.projects, .reports, .activity, .timer] {
            test.model.padTab = tab
        }
        await test.model.storeChanged(.structure)
        try await PhoneURLRouter(model: test.model, scheme: "timetracking").open(#require(URL(string: "timetracking://planner/reports")))
        #expect(events.access() == .notDetermined)
        #expect(!pad.opened.contains(.calendar))

        test.model.padTab = .calendar
        #expect(pad.opened.contains(.calendar))
        // What the Calendar tab's view does when it first appears.
        await pad.router.calendar.reload()
        #expect(events.access() == .fullAccess)
    }

    @Test("IOS-34 ⌥⌘R selects the Timer with the task field focused, ⌘1 to ⌘4 the Planner tabs; ⌘T does nothing in Timer and Projects")
    func keyboard() async throws {
        let test = try await Self.pad()
        let model = test.model
        let router = try #require(model.pad?.router)
        for (command, tab) in [
            (PadCommand.projects, PadTab.projects),
            (.calendar, .calendar),
            (.reports, .reports),
            (.activity, .activity),
        ] {
            await model.perform(command)
            #expect(model.padTab == tab)
            #expect(router.section == tab.section)
        }
        let focus = model.timer.focusTaskFieldRequest
        await model.perform(.timerTab)
        #expect(model.padTab == .timer)
        #expect(model.timer.focusTaskFieldRequest == focus + 1)
        await model.perform(.planner)
        #expect(model.padTab == .activity)

        // Away from today in Calendar and Reports.
        await router.calendar.shift(days: -10)
        await router.reports.previousPeriod()
        let firstDay = router.calendar.firstDay
        let range = router.reports.range.range
        for tab in [PadTab.timer, .projects] {
            model.padTab = tab
            #expect(!model.isEnabled(.today))
            await model.perform(.today)
            #expect(router.calendar.firstDay == firstDay)
            #expect(router.reports.range.range == range)
            #expect(model.padTab == tab)
        }
        model.padTab = .calendar
        await model.perform(.today)
        #expect(router.calendar.firstDay != firstDay)
        #expect(router.calendar.days.contains(router.calendar.today))

        // ⌘P is the Timer tab's Set Project only.
        model.padTab = .reports
        #expect(!model.isEnabled(.setProject))
        await model.perform(.setProject)
        #expect(model.sheet == nil)
        model.padTab = .timer
        await model.perform(.setProject)
        if case .picker = model.sheet {} else {
            Issue.record("⌘P in the Timer tab did not open the picker")
        }
    }

    @Test("IOS-35 drawing in the iPad's Tracked column creates an entry and opens the editor; a drawing past now is refused")
    func drawing() async throws {
        let test = try await Self.pad()
        let model = test.model
        model.padTab = .calendar
        let calendar = try #require(model.pad?.router.calendar)
        await calendar.reload()
        let today = calendar.today
        try calendar.draw(on: today, from: test.date("2024-03-14T08:00"), to: test.date("2024-03-14T09:00"))
        let draft = try #require(calendar.draft)
        #expect(try draft.interval == DateInterval(start: test.date("2024-03-14T08:00"), end: test.date("2024-03-14T09:00")))
        calendar.draft?.task = "Drawn on the iPad"
        await calendar.commitDraft()
        #expect(calendar.draft == nil)
        let stored = try await test.store.entries(in: calendar.visibleInterval, includeDeleted: false)
        #expect(stored.map(\.task) == ["Drawn on the iPad"])
        // The Timer's list follows the Calendar's write.
        #expect(model.list.days.flatMap(\.rows).contains { $0.entry.task == "Drawn on the iPad" })

        try calendar.draw(on: today, from: test.date("2024-03-14T10:30"), to: test.date("2024-03-14T11:00"))
        #expect(calendar.draft == nil)
        #expect(calendar.notice?.text == CalendarEditing.futureNotice)
    }

    @Test("PC-15 the iPad does not offer Delete This Activity and hides the open block")
    func noDeleteFromLog() async throws {
        let closed = try Self.block("08:00", "08:30")
        let open = try Self.block("09:30", "10:00", open: true)
        let test = try await Self.pad(blocks: [closed, open])
        let calendar = try #require(test.model.pad?.router.calendar)
        await calendar.reload()
        #expect(calendar.blocks.map(\.id) == [closed.id])
        #expect(!calendar.canDeleteFromLog(closed))
        #expect(calendar.sendTrackerCommand == nil)
        #expect(calendar.gapLabels.isEmpty)
    }

    @Test("PA-16 the iPad footer shows the Mac's lastTick from LiveState without sources")
    func remoteFooter() async throws {
        let test = try await Self.pad(blocks: [Self.block("08:00", "08:30"), Self.block("09:30", "10:00", open: true)])
        let activity = try #require(test.model.pad?.router.activity)
        let mac = LiveState.MacActivity(
            device: "macbook",
            primary: nil,
            groupKey: nil,
            presence: "active",
            since: nil,
            agentRunning: true,
            lastTick: test.clock.now - 120,
            health: [],
            updatedAt: test.clock.now
        )
        try await test.store.setLiveActivity(mac, for: DeviceID())
        await activity.reload()
        #expect(activity.health?.statusLine == "Mac tracker: last tick 2 min ago")
        #expect(activity.health?.activeSources.isEmpty == true)
        #expect(activity.health?.dot == .green)
        // No open block on the iPad.
        #expect(try activity.newestBlockEnd == (test.date("2024-03-14T08:30")))
    }

    @Test("IOS-38 on the iPad, timetracking://planner/reports selects the Reports tab; the Mac activity line opens Activity")
    func urlTabs() async throws {
        let test = try await Self.pad()
        let router = PhoneURLRouter(model: test.model, scheme: "timetracking")
        let outcome = try await router.open(#require(URL(string: "timetracking://planner/reports")))
        #expect(outcome == .shown)
        #expect(test.model.padTab == .reports)
        #expect(test.model.pad?.router.section == .reports)
        try await router.open(#require(URL(string: "timetracking://planner/calendar?date=2024-03-04")))
        #expect(test.model.padTab == .calendar)
        try await router.open(#require(URL(string: "timetracking://show")))
        #expect(test.model.padTab == .timer)
        test.model.macActivityTapped()
        #expect(test.model.padTab == .activity)

        let phone = try await TestPhone()
        phone.model.macActivityTapped()
        #expect(phone.model.padTab == .timer)
    }
}
