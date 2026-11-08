// DeviceEvents of an iPhone or iPad as Samples, and the workspace rules
// (activity_tracking.md §2.3, §6.2).

import Foundation
import Testing
@testable import TimeTrackingCore

struct DeviceEventConverterTests {
    private static let offset = -4 * 3600
    private static let converter = DeviceEventConverter(maxBlock: 90 * 60, urls: URLWorkspaces(patterns: TrackerWorkspaceSettings().urls))

    private static func event(
        _ time: String,
        _ source: DeviceEvent.Source,
        _ label: String,
        _ kind: String,
        payload: [String: any Sendable] = [:],
        sequence: Int = 0
    ) throws -> DeviceEvent {
        try DeviceEvent(
            deviceID: SampleTimeline.iPhone,
            time: ActivityFixture.instant(time),
            source: source,
            label: label,
            kind: kind,
            payload: DeviceEvent.payloadText(payload),
            sequence: sequence,
            utcOffset: offset,
            deviceName: "iPhone"
        )
    }

    /// The Samples of the local date `day` at the events' UTC offset.
    private static func samples(_ day: String, _ events: [DeviceEvent], before: [DeviceEvent] = [], after: [DeviceEvent] = []) -> [Sample] {
        let offset = (events.last ?? before.last ?? after.first)?.utcOffset ?? 0
        let start = ActivityTimestamp.date("\(day)T00:00:00", utcOffset: offset) ?? .distantPast
        return converter.samples(
            deviceID: SampleTimeline.iPhone,
            deviceName: "iPhone",
            date: DateInterval(start: start, duration: 86_400),
            events: events,
            before: before,
            after: after
        )
    }

    @Test(
        "TRK-18 Screen Time minutes 1 to 20, a 10-minute gap, and 21 to 30 give two iPhone blocks; the set's label is app and workspace"
    )
    func screenTimeMinutes() throws {
        var events: [DeviceEvent] = []
        for minute in 1 ... 20 {
            try events.append(Self.event(
                String(format: "2024-03-14T09:%02d:00-04:00", minute),
                .screenTime,
                "Social",
                "minute",
                payload: ["n": minute],
                sequence: minute
            ))
        }
        for minute in 21 ... 30 {
            try events.append(Self.event(
                String(format: "2024-03-14T09:%02d:00-04:00", minute + 10),
                .screenTime,
                "Social",
                "minute",
                payload: ["n": minute],
                sequence: minute
            ))
        }
        let samples = Self.samples("2024-03-14", events)
        #expect(samples.first?.foreground == ActivityItem(app: "Social", appID: "screenTime", workspace: "Social"))
        let rig = try RebuildRig()
        try rig.insert(SampleTimeline(), until: nil)
        try rig.store.insert(samples, rules: rig.rules)
        try rig.run(now: .distantFuture)
        let blocks = rig.blocks("2024-03-14")
        #expect(blocks.map(\.span) == ["09:00–09:20", "09:30–09:40"])
        #expect(blocks.map { $0.seconds(on: "iPhone") } == [20 * 60, 10 * 60])
    }

    @Test(
        "TRK-58 an app automation from 23:50 to 00:20 gives Samples on both dates; a pausing Focus from Friday to Monday pauses four dates"
    )
    func timeContinuesIntoTheNextDate() throws {
        let opened = try Self.event("2024-03-14T23:50:00-04:00", .intent, "Goodnotes", ActivityEventKind.appOpened.rawValue)
        let closed = try Self.event("2024-03-15T00:20:00-04:00", .intent, "Goodnotes", ActivityEventKind.appClosed.rawValue, sequence: 1)
        let first = Self.samples("2024-03-14", [opened], after: [closed])
        let second = Self.samples("2024-03-15", [closed], before: [opened])
        #expect(try first.first?.time == ActivityFixture.instant("2024-03-14T23:50:00-04:00"))
        #expect(first.count == 19 && first.allSatisfy { $0.foreground?.app == "Goodnotes" })
        #expect(try second.first?.time == ActivityFixture.instant("2024-03-15T00:00:00-04:00"))
        #expect(try second.last?.time == ActivityFixture.instant("2024-03-15T00:19:00-04:00"))
        // Before the close arrives, the opening counts a minute and nothing of the next date.
        #expect(Self.samples("2024-03-14", [opened]).count == 1)
        #expect(Self.samples("2024-03-15", [], before: [opened]).isEmpty)

        let focusOn = try Self.event("2024-03-15T18:00:00-04:00", .focus, "Sleep", "on", payload: ["collect": false])
        let focusOff = try Self.event("2024-03-18T08:00:00-04:00", .focus, "Sleep", "off", sequence: 1)
        for day in ["2024-03-15", "2024-03-16", "2024-03-17", "2024-03-18"] {
            let paused = Self.samples(
                day,
                day == "2024-03-18" ? [focusOff] : (day == "2024-03-15" ? [focusOn] : []),
                before: day == "2024-03-15" ? [] : [focusOn]
            )
            #expect(!paused.isEmpty && paused.allSatisfy { $0.state == .paused && $0.source == .focus })
        }
    }

    @Test("A stretch's Samples come every 30 seconds, the last one a minute before its end")
    func sampleTimes() throws {
        let date = try DateInterval(start: ActivityFixture.instant("2024-03-14T00:00:00-04:00"), duration: 86_400)
        let start = try ActivityFixture.instant("2024-03-14T09:00:00-04:00")
        let times = DeviceEventConverter.times(of: DateInterval(start: start, duration: 150), within: date)
        #expect(times.map { $0.timeIntervalSince(start) } == [0, 30, 60, 90])
        #expect(DeviceEventConverter.times(of: DateInterval(start: start, duration: 20), within: date)
            .map { $0.timeIntervalSince(start) } == [0])
    }

    @Test(
        "TRK-8 workspace: nearest root marker, a worktree's main repository, never home, a localhost server's folder, URL, host, app"
    )
    func workspaces() {
        var rules = WorkspaceRules(
            settings: TrackerWorkspaceSettings(),
            homeDirectory: "/Users/alex",
            hasRootMarker: { ["/Users/alex/Code/MyApp", "/Users/alex/Code/MyApp-fix"].contains($0) },
            mainRepository: { $0 == "/Users/alex/Code/MyApp-fix" ? "/Users/alex/Code/MyApp" : nil }
        )
        rules.urls.repositories = ["owner/MyApp": "~/Code/MyApp"]
        func workspace(_ item: ActivityItem) -> String {
            rules.workspace(of: item) { $0 == 8888 ? "/Users/alex/Code/MyApp/notebooks" : nil }
        }
        #expect(workspace(ActivityItem(app: "WezTerm", location: "~/Code/MyApp/src")) == "~/Code/MyApp")
        #expect(workspace(ActivityItem(app: "WezTerm", location: "/Users/alex/Code/MyApp-fix/src")) == "~/Code/MyApp")
        #expect(workspace(ActivityItem(app: "Skim", location: "~/Papers/2026_Noise", documents: ["~/Papers/2026_Noise/notes.pdf"])) ==
            "~/Papers/2026_Noise")
        #expect(workspace(ActivityItem(app: "WezTerm", location: "~")) == "WezTerm")
        #expect(workspace(ActivityItem(app: "Safari", location: "http://localhost:8888/lab")) == "~/Code/MyApp")
        #expect(workspace(ActivityItem(app: "Safari", location: "https://github.com/owner/MyApp/pull/123?w=1")) == "~/Code/MyApp")
        #expect(workspace(ActivityItem(app: "Safari", location: "https://github.com/other/Lib")) == "other/Lib")
        #expect(workspace(ActivityItem(app: "Safari", location: "https://www.arxiv.org/abs/2401.1")) == "arxiv.org")
        #expect(workspace(ActivityItem(app: "WezTerm", host: "hpc", location: "/scratch/run7")) == "hpc:/scratch/run7")
        #expect(workspace(ActivityItem(app: "Mail", window: "Inbox")) == "Mail")
    }
}
