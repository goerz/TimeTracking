// The Activity section's view model: the shared range, the filter, the
// footer, drill-down into the Calendar, the setup card, and exclusions
// (spec_activity.md §6).

import Foundation
import Synchronization
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct ActivitySectionTests {
    static func block(_ day: String, _ start: String, _ end: String, _ items: [(String, Int)]) throws -> ActivityBlock {
        let begin = try TestApp.date("\(day)T\(start)")
        return try ActivityBlock(
            start: begin,
            end: TestApp.date("\(day)T\(end)"),
            activeSeconds: items.reduce(0) { $0 + $1.1 },
            devices: [ActivityDeviceTime(name: "macbook", seconds: items.reduce(0) { $0 + $1.1 }, isRecordingMac: true)],
            groupKey: items.first?.0 ?? "",
            groupShare: 1,
            items: items.map { ActivityItem(context: $0.0, subject: "s", detail: "", seconds: $0.1, device: "macbook") },
            utcOffset: TimeZone.current.secondsFromGMT(for: begin)
        )
    }

    /// The week of 2024-03-11 (today Thursday the 14th) with two contexts.
    static func week() throws -> [ActivityBlock] {
        try [
            block("2024-03-11", "09:00", "10:00", [("safari", 1800), ("tmux:paper", 1500)]),
            block("2024-03-12", "09:00", "09:30", [("mail", 1500)]),
            block("2024-03-14", "08:00", "09:00", [("tmux:paper", 3000)]),
        ]
    }

    static func router(_ test: TestApp, blocks: [ActivityBlock], state: TrackerState? = nil) -> (SectionRouter, InMemoryActivityStore) {
        let activity = InMemoryActivityStore(blocks: blocks, trackerState: state)
        let router = SectionRouter(store: test.store, clock: test.clock, device: test.app.settings.device, activity: activity)
        router.range.set(.preset(.thisWeek))
        return (router, activity)
    }

    @Test("PA-22 a slow reload finishing after a later one leaves the later range's figures and no loading indicator")
    func laterReloadWins() async throws {
        let test = try await TestApp()
        let reader = try GatedActivityReader(InMemoryActivityStore(blocks: Self.week()))
        let router = SectionRouter(store: test.store, clock: test.clock, device: test.app.settings.device, activity: reader)
        let model = router.activity
        router.range.set(.preset(.thisYear))
        let slow = Task { await model.reload() }
        await reader.waitUntilHeld()
        router.range.set(.preset(.today))
        await model.reload()
        #expect(model.summary?.total == 3000)
        reader.release()
        await slow.value
        #expect(model.summary?.total == 3000)
        #expect(!model.isLoading)
    }

    @Test("PA-3 a range changed in Reports changes Activity and back; a custom range over 366 days is clipped with the note")
    func sharedRange() async throws {
        let test = try await TestApp()
        let (router, _) = try Self.router(test, blocks: Self.week())
        let model = router.activity
        await router.reports.previousPeriod()
        #expect(model.days == TrackingDay(year: 2024, month: 3, day: 4) ... TrackingDay(year: 2024, month: 3, day: 10))
        await model.shiftPeriod(by: 1)
        #expect(router.reports.range.days == TrackingDay(year: 2024, month: 3, day: 11) ... TrackingDay(year: 2024, month: 3, day: 17))
        router.range.set(.days(TrackingDay(year: 2022, month: 1, day: 1), TrackingDay(year: 2024, month: 3, day: 14)))
        #expect(model.days.lowerBound == TrackingDay(year: 2024, month: 3, day: 14).adding(days: -365))
        #expect(model.clipNote == "Showing the last 366 days of the selection")
    }

    @Test("PA-4 chips toggle, All clears, the filter resets on a range change but not on the period arrows, and on reopening")
    func filter() async throws {
        let test = try await TestApp()
        let (router, _) = try Self.router(test, blocks: Self.week())
        let model = router.activity
        await model.reload()
        #expect(model.summary?.total == 7800)
        await model.toggle("tmux:paper")
        #expect(model.summary?.total == 4500)
        await model.toggle("mail")
        #expect(model.contexts == ["tmux:paper", "mail"])
        await model.selectAll()
        #expect(model.contexts.isEmpty)
        await model.showOnly("mail")
        await model.shiftPeriod(by: -1)
        await model.shiftPeriod(by: 1)
        #expect(model.contexts == ["mail"])
        router.range.select(.lastMonth)
        await model.reload()
        #expect(model.contexts.isEmpty)
        await model.showOnly("safari")
        #expect(model.subjectKind == .sites)
        model.mainWindowReopened()
        #expect(model.contexts.isEmpty)
    }

    @Test("PA-16 the Mac footer's dot matches the Tracker pane's status for the same current.json")
    func footer() async throws {
        let now = try TestApp.date("2024-03-14T10:00")
        let state = TrackerState(
            device: "macbook",
            openBlock: nil,
            primary: nil,
            presence: TrackerPresence(state: .active, since: now - 600),
            health: TrackerHealth(
                lastTick: now - 12,
                version: "1.0",
                sources: [TrackerSourceHealth(id: "terminal", name: "Terminal", status: .active)]
            )
        )
        let test = try await TestApp(trackerState: state)
        test.agent.registration = .enabled
        await test.app.tracker.refresh()
        let (router, _) = Self.router(test, blocks: [], state: state)
        router.activity.registration = { .enabled }
        await router.activity.loadHealth()
        #expect(router.activity.health?.statusLine == test.app.tracker.liveness.statusLine(now: now))
        #expect(router.activity.health?.dot == .green)
        // The iPad footer: LiveState's lastTick, no sources.
        router.activity.isRecordingMac = false
        router.activity.remoteActivity = {
            LiveState.MacActivity(
                device: "macbook",
                primary: nil,
                groupKey: nil,
                presence: "active",
                since: nil,
                agentRunning: true,
                lastTick: now - 120,
                health: [],
                updatedAt: now
            )
        }
        await router.activity.loadHealth()
        #expect(router.activity.health?.statusLine == "Mac tracker: checked 2 min ago")
    }

    @Test("PA-16 while the footer is visible it re-reads the tracker's status every 10 seconds")
    func footerRefreshLoop() async throws {
        let now = try TestApp.date("2024-03-14T10:00")
        let state = TrackerState(
            device: "macbook",
            openBlock: nil,
            primary: nil,
            presence: TrackerPresence(state: .active, since: now - 600),
            health: TrackerHealth(lastTick: now - 12, version: "1.0", sources: [])
        )
        let test = try await TestApp(trackerState: state)
        let (router, _) = Self.router(test, blocks: [], state: state)
        let model = router.activity
        var registration = AgentRegistration.notRegistered
        model.registration = { registration }
        let gate = SleepGate()
        let loop = Task { await model.followHealth(sleep: { try await gate.sleep($0) }) }
        await gate.waitForSleep(1)
        let before = model.health?.dot
        #expect(before != .green)
        // Enabled meanwhile: the next pass, one period later, shows it.
        registration = .enabled
        #expect(model.health?.dot == before)
        gate.release()
        await gate.waitForSleep(2)
        #expect(model.health?.dot == .green)
        #expect(gate.durations == [.seconds(10), .seconds(10)])
        loop.cancel()
        gate.cancel()
        await loop.value
    }

    @Test("PA-17 clicking a cell opens the Calendar at that day and hour with the hour's blocks pulsed; ⌘5 returns unchanged")
    func drillIntoCalendar() async throws {
        let test = try await TestApp()
        let (router, _) = try Self.router(test, blocks: Self.week())
        let model = router.activity
        await model.reload()
        await model.showOnly("tmux:paper")
        let summary = try #require(model.summary)
        let row = try #require(summary.heatmap.rows.first { $0.label == "Mon 11" })
        model.showInCalendar(row: row, hour: 9)
        #expect(router.section == .calendar)
        #expect(router.calendarRequest == CalendarRequest(day: TrackingDay(year: 2024, month: 3, day: 11), hour: 9, highlight: .hour(9)))
        await router.consumeCalendarRequest()
        #expect(router.calendar.firstDay == TrackingDay(year: 2024, month: 3, day: 11))
        #expect(router.calendar.scrollRequest?.hour == 9)
        router.select(.activity)
        #expect(model.contexts == ["tmux:paper"])
        #expect(model.range.range == .preset(.thisWeek))
    }

    @Test("PA-18 with an empty log and no tracker the setup card shows and opens the Tracker pane; after a block exists it does not return")
    func setupCard() async throws {
        let test = try await TestApp()
        let (router, activity) = Self.router(test, blocks: [])
        let model = router.activity
        var opened: [TrackerExclusionDraft?] = []
        router.openTrackerSettings = { opened.append($0) }
        await model.reload()
        #expect(model.emptyState == .setup)
        router.showTrackerSettings()
        #expect(opened == [nil])
        try activity.append(Self.week())
        await model.reload()
        #expect(model.emptyState == .panels)
        try activity.remove(Set(Self.week().map(\.id)))
        await model.reload()
        #expect(model.emptyState == .noActivity(trackerNotRunning: false))
    }

    @Test("PA-15 the Away panel counts gaps by the settings file's idle_close")
    func awayFollowsIdleClose() async throws {
        let test = try await TestApp()
        let blocks = try [
            Self.block("2024-03-14", "08:00", "08:30", [("mail", 1800)]),
            Self.block("2024-03-14", "08:40", "09:00", [("mail", 1200)]),
        ]
        let activity = InMemoryActivityStore(blocks: blocks, idleClose: 900)
        let router = SectionRouter(store: test.store, clock: test.clock, device: test.app.settings.device, activity: activity)
        router.range.set(.preset(.thisWeek))
        await router.activity.reload()
        #expect(router.activity.summary?.away.seconds == 0)
    }

    @Test("PA-18 the tracker counts as set up only when enabled, with a current.json and Accessibility", arguments: [
        (TrackerSourceStatus.active, AgentRegistration.enabled, true),
        (.fallback, .enabled, false),
        (.active, .notRegistered, false),
    ])
    func setupNeedsAccessibility(window: TrackerSourceStatus, registration: AgentRegistration, setUp: Bool) async throws {
        let now = try TestApp.date("2024-03-14T10:00")
        let state = TrackerState(
            device: "macbook",
            openBlock: nil,
            primary: nil,
            presence: TrackerPresence(state: .active, since: now - 600),
            health: TrackerHealth(
                lastTick: now - 12,
                version: "1.0",
                sources: [TrackerSourceHealth(id: "window", name: "Window titles", status: window)]
            )
        )
        let test = try await TestApp(trackerState: state)
        test.agent.registration = registration
        await test.app.tracker.refresh()
        let model = test.app.sections.activity
        #expect(await model.trackerSetUp() == setUp)
        await model.reload()
        #expect((model.emptyState == .setup) == !setUp)
    }

    @Test("PA-19 Exclude from tracking opens the Tracker pane with the right list and value and saves nothing")
    func exclude() async throws {
        let test = try await TestApp()
        let (router, _) = try Self.router(test, blocks: Self.week())
        router.openTrackerSettings = test.app.sections.openTrackerSettings
        router.activity.exclude(context: "tmux:paper")
        #expect(test.app.trackerSettings.pendingExclusion == PendingExclusion(list: .excludeTmuxSessions, value: "paper"))
        #expect(test.router.calls.last == .openSettings(.tracker))
        router.activity.exclude(site: "github.com/owner/repo")
        #expect(test.app.trackerSettings.pendingExclusion == PendingExclusion(list: .excludeDomains, value: "github.com"))
        #expect(test.app.trackerSettings.entries(.excludeDomains).isEmpty)
    }
}

/// An activity reader whose first `blocks(in:devices:)` waits until
/// `release()`, so a test can finish a later read first.
final class GatedActivityReader: ActivityReading {
    private let base: InMemoryActivityStore
    private let state = Mutex<GateState>(GateState())

    private struct GateState {
        var used = false
        var held: CheckedContinuation<Void, Never>?
        var waiting: CheckedContinuation<Void, Never>?
        var released = false
    }

    init(_ base: InMemoryActivityStore) {
        self.base = base
    }

    /// Returns once the first read is waiting at the gate.
    func waitUntilHeld() async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state in
                guard state.held == nil else {
                    return true
                }
                state.waiting = continuation
                return false
            }
            if ready {
                continuation.resume()
            }
        }
    }

    /// Lets the first read go on.
    func release() {
        let held = state.withLock { state in
            state.released = true
            defer { state.held = nil }
            return state.held
        }
        held?.resume()
    }

    // swiftlint:disable:next discouraged_optional_collection
    func blocks(in interval: DateInterval, devices: Set<String>?) async -> [ActivityBlock] {
        let first = state.withLock { state in
            defer { state.used = true }
            return !state.used
        }
        if first {
            await withCheckedContinuation { continuation in
                let (proceed, waiting) = state.withLock { state in
                    if state.released {
                        return (true, CheckedContinuation<Void, Never>?.none)
                    }
                    state.held = continuation
                    defer { state.waiting = nil }
                    return (false, state.waiting)
                }
                waiting?.resume()
                if proceed {
                    continuation.resume()
                }
            }
        }
        return base.blocks(in: interval, devices: devices)
    }

    // swiftlint:disable:next discouraged_optional_collection
    func backgroundStretches(in interval: DateInterval, devices: Set<String>?) -> [ActivityBackgroundStretch] {
        base.backgroundStretches(in: interval, devices: devices)
    }

    func detail(for id: ActivityBlock.ID) -> ActivityBlockDetail? {
        base.detail(for: id)
    }

    func details(for ids: [ActivityBlock.ID]) async throws -> [ActivityBlock.ID: ActivityBlockDetail] {
        try await base.details(for: ids)
    }

    func currentState() -> TrackerState? {
        base.currentState()
    }

    func aggregate(in interval: DateInterval, by key: ActivityGroupKey, device: String?) -> [ActivityAggregate] {
        base.aggregate(in: interval, by: key, device: device)
    }

    func bundleIdentifier(forContext context: String) -> String? {
        base.bundleIdentifier(forContext: context)
    }

    var exclusions: ExclusionRules {
        base.exclusions
    }

    var idleClose: TimeInterval {
        base.idleClose
    }

    var changes: AsyncStream<ActivityChange> {
        base.changes
    }
}
