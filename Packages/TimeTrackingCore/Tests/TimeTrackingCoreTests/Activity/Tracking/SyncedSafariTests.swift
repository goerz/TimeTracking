// Tests of synced Safari visits as Samples: their length, the device a run
// belongs to, and late visits (activity_tracking.md §6.1).

import Foundation
import Testing
@testable import TimeTrackingCore

struct SyncedSafariTests {
    let timeline = SampleTimeline()
    let urls = URLWorkspaces(patterns: [])

    func visit(_ clock: String, _ url: String) -> SyncedVisit {
        SyncedVisit(time: timeline.time(clock), url: url, title: "Page")
    }

    func gain(_ deviceID: String, _ url: String, _ from: String, _ to: String) -> CloudTabGain {
        CloudTabGain(deviceID: deviceID, url: url, interval: DateInterval(start: timeline.time(from), end: timeline.time(to)))
    }

    /// The covered seconds of each device: each Sample covers until the next of its device, at most a minute.
    func seconds(_ samples: [Sample]) -> [String: TimeInterval] {
        var result: [String: TimeInterval] = [:]
        for (deviceID, own) in Dictionary(grouping: samples, by: \.deviceID) {
            let times = own.map(\.time).sorted()
            result[deviceID] = zip(times, times.dropFirst().map(Optional.some) + [nil]).reduce(0) { total, pair in
                total + min(60, pair.1.map { $0.timeIntervalSince(pair.0) } ?? 60)
            }
        }
        return result
    }

    @Test(
        "TRK-19 a visit lasts until the next within 5 minutes, else a minute; a run is the one device's with a tab gain, else remote"
    )
    func lengthsAndDevices() {
        let visits = [
            visit("09:00", "https://example.com/a"),
            visit("09:04", "https://example.com/b#top"),
            visit("09:30", "https://example.com/c"),
            visit("10:00", "https://example.com/d"),
        ]
        let gains = [
            // During the first run, for one of its URLs (the fragment aside).
            gain(SampleTimeline.iPhone, "https://example.com/b", "09:02", "09:07"),
            // Two devices gained the third run's URL.
            gain(SampleTimeline.iPhone, "https://example.com/c", "09:28", "09:33"),
            gain(SampleTimeline.iPad, "https://example.com/c", "09:28", "09:33"),
            // Long before the fourth run.
            gain(SampleTimeline.iPad, "https://example.com/d", "08:00", "08:05"),
        ]
        let samples = SyncedSafari.samples(visits: visits, gains: gains, urls: urls)
        #expect(samples.allSatisfy { $0.source == .safariHistory && $0.foreground?.app == "Safari" })
        let covered = seconds(samples)
        // 09:00 to 09:05 on the iPhone; 09:30 and 10:00 a minute each, remote.
        #expect(covered[SampleTimeline.iPhone] == 300)
        #expect(covered[ActivityBlockItem.remoteDevice] == 120)
        #expect(covered[SampleTimeline.iPad] == nil)
        #expect(samples.first { $0.time == timeline.time("09:04") }?.foreground?.location == "https://example.com/b#top")
    }

    @Test("TRK-19 a read records the URLs a known device newly has open as gains between the reads; old gains go after a day")
    func tabMemory() {
        let first = CloudTabMemory.empty.reading([SampleTimeline.iPhone: ["https://a.com"]], at: timeline.time("09:00"))
        #expect(first.gains.isEmpty)
        let second = first.reading(
            [SampleTimeline.iPhone: ["https://a.com", "https://b.com"], SampleTimeline.iPad: ["https://c.com"]],
            at: timeline.time("09:05")
        )
        #expect(second.gains == [gain(SampleTimeline.iPhone, "https://b.com", "09:00", "09:05")])
        let later = second.reading(second.tabs, at: timeline.time("+09:06"))
        #expect(later.gains.isEmpty)
    }

    @Test("TRK-19 visits arriving after the loop read past their time still form a block")
    func lateVisits() throws {
        let rig = try RebuildRig()
        var mac = SampleTimeline()
        mac.add("09:00", "09:20", ActivityFixture.app("Xcode", appID: "com.apple.dt.Xcode"))
        try rig.insert(mac)
        try rig.run(now: mac.time("12:00"))
        #expect(rig.blocks("2024-03-14").count == 1)
        // Synced at noon, visits from 10:00 to 10:20.
        let visits = stride(from: 0, to: 20, by: 4).map { visit(String(format: "10:%02d", $0), "https://example.com/\($0)") }
        let samples = SyncedSafari.samples(visits: visits, gains: [], urls: urls)
        let range = DateInterval(start: mac.time("12:00") - SyncedSafari.lookback, end: mac.time("12:00"))
        try rig.store.replace(SampleSelection(range: range, sources: [.safariHistory]), with: samples, rules: rig.rules)
        try rig.run(now: mac.time("12:00"))
        let blocks = rig.blocks("2024-03-14")
        #expect(blocks.count == 2)
        #expect(blocks.last?.foreground.first?.device == ActivityBlockItem.remoteDevice)
    }
}
