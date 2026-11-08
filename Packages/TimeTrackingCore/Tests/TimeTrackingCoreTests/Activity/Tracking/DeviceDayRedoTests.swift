// The remote activity loop's redo of a device-date in the Sample store:
// adjacent dates share their boundary (activity_tracking.md §2.5, §6.2).

import Foundation
import Testing
@testable import TimeTrackingCore

struct DeviceDayRedoTests {
    private static let converter = DeviceEventConverter(maxBlock: 90 * 60, urls: URLWorkspaces(patterns: TrackerWorkspaceSettings().urls))

    /// A Screen Time minute threshold at `time` (with its offset) on the iPhone.
    private static func minute(_ time: String, _ number: Int) throws -> DeviceEvent {
        let parsed = try #require(ActivityTimestamp.parseWithOffset(time))
        return DeviceEvent(
            deviceID: SampleTimeline.iPhone,
            time: parsed.date,
            source: .screenTime,
            label: "Social",
            kind: "minute",
            payload: DeviceEvent.payloadText(["n": number]),
            sequence: number,
            utcOffset: parsed.utcOffset,
            deviceName: "iPhone"
        )
    }

    @Test("TRK-68 on the night daylight saving time ends, the iPhone's dates meet at one midnight: its first hour is converted once")
    func fallBackBoundary() throws {
        let rig = try RebuildRig()
        // Saturday evening and the first minutes of Sunday at -04:00; Sunday
        // morning, after the clocks went back, at -05:00.
        var events = try (1 ... 5).map { try Self.minute(String(format: "2024-11-02T22:%02d:00-04:00", $0), $0) }
        events += try (6 ... 15).map { try Self.minute(String(format: "2024-11-03T00:%02d:00-04:00", $0 + 4), $0) }
        events += try (16 ... 20).map { try Self.minute(String(format: "2024-11-03T09:%02d:00-05:00", $0), $0) }
        try rig.store.storeDeviceEvents(events, token: Data(), rules: rig.rules)
        let today = try #require(TrackingDay("2024-11-04"))
        for day in ["2024-11-02", "2024-11-03"] {
            let deviceDay = try DeviceDay(deviceID: SampleTimeline.iPhone, day: #require(TrackingDay(day)))
            try rig.store.redo(deviceDay, converter: Self.converter, today: today, rules: rig.rules)
        }
        let everything = DateInterval(start: .distantPast, end: .distantFuture)
        let samples = try rig.store.samples(SampleSelection(range: everything, deviceID: SampleTimeline.iPhone))
        let times = samples.map(\.time)
        #expect(Set(times).count == times.count)
        let firstHour = try DateInterval(
            start: #require(ActivityTimestamp.parseWithOffset("2024-11-03T00:00:00-04:00")).date,
            duration: 3600
        )
        // Minutes 6 to 15 run from 00:10 to 00:20 EDT, a Sample every 30 seconds.
        #expect(times.filter(firstHour.contains).count >= 19)
    }
}
