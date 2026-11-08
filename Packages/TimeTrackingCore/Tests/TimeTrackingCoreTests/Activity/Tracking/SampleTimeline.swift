// A builder of Samples for the rebuild tests (activity_tracking.md §2.7):
// stretches of one state every 30 seconds, as the local activity loop and
// the remote activity loop take them, in New York time.

import Foundation
@testable import TimeTrackingCore

struct SampleTimeline {
    static let mac = "mac-uuid"
    static let iPhone = "iphone-id"
    static let iPad = "ipad-id"
    static let names = [mac: "MacBook", iPhone: "iPhone", iPad: "iPad"]
    static let zone = TestTime.newYork

    var day = "2024-03-14"
    private(set) var samples: [Sample] = []

    /// The instant of `HH:MM` or `HH:MM:SS` on the timeline's day, or on
    /// the next day with a `+` prefix.
    func time(_ clock: String) -> Date {
        var text = clock
        var date = day
        if text.hasPrefix("+") {
            text.removeFirst()
            date = TrackingDay(day).map { $0.adding(days: 1).description } ?? day
        }
        let full = text.count == 5 ? text + ":00" : text
        return ActivityTimestamp.date("\(date)T\(full)", timeZone: Self.zone) ?? .distantPast
    }

    /// One Sample every 30 seconds in `[from, to)`.
    mutating func add(
        _ from: String,
        _ to: String,
        device: String = mac,
        source: SampleSource = .live,
        state: TrackerPresenceState = .active,
        _ item: ActivityItem? = nil,
        background: [ActivityItem] = []
    ) {
        var time = time(from)
        let end = self.time(to)
        while time < end {
            samples.append(Sample(time: time, deviceID: device, source: source, state: state, foreground: item, background: background))
            time += 30
        }
    }

    /// The Mac at work on `item` in `[from, to)`.
    mutating func work(_ from: String, _ to: String, _ item: ActivityItem, background: [ActivityItem] = []) {
        add(from, to, item, background: background)
    }

    /// The Mac in `state` (idle, locked, asleep, …) in `[from, to)`.
    mutating func away(_ from: String, _ to: String, _ state: TrackerPresenceState = .idle, background: [ActivityItem] = []) {
        add(from, to, state: state, background: background)
    }

    /// One Sample at `at`.
    mutating func once(_ at: String, device: String = mac, state: TrackerPresenceState, _ item: ActivityItem? = nil) {
        samples.append(Sample(time: time(at), deviceID: device, source: .live, state: state, foreground: item))
    }

    /// An iOS device on `item` in `[from, to)`: a Sample every 30 seconds,
    /// the last one 60 seconds before `to`, as the remote activity loop
    /// places them, so the stretch's coverage ends at `to`.
    mutating func device(_ device: String, _ from: String, _ to: String, _ item: ActivityItem, source: SampleSource = .screenTime) {
        let last = time(to) - 60
        var times = Array(stride(from: time(from), to: last, by: 30))
        times.append(max(time(from), last))
        for time in times {
            samples.append(Sample(time: time, deviceID: device, source: source, state: .active, foreground: item))
        }
    }

    var sorted: [Sample] {
        samples.sorted { $0.time < $1.time }
    }

    /// The pass of the timeline's day, from its 00:00, with all its time passed.
    func pass(settings: TrackerBlockSettings = TrackerBlockSettings(), now: Date = .distantFuture) -> DatePass {
        let boundaries = DayBoundaries(zone: Self.zone)
        let day = TrackingDay(day) ?? TrackingDay(year: 2024, month: 3, day: 14)
        return BlockFormer(settings: settings, macDeviceID: Self.mac, deviceNames: Self.names)
            .pass(day: day, samples: sorted, boundaries: boundaries, readStart: boundaries.start(of: day), now: now)
    }
}

extension ActivityBlock {
    /// `HH:MM–HH:MM` in New York time, for compact expectations.
    var span: String {
        let start = ActivityTimestamp.text(start, timeZone: SampleTimeline.zone)
        let end = ActivityTimestamp.text(end, timeZone: SampleTimeline.zone)
        return "\(start.dropFirst(11).prefix(5))–\(end.dropFirst(11).prefix(5))"
    }

    /// The foreground seconds per device name.
    func seconds(on device: String) -> Int {
        foreground.filter { $0.device == device }.reduce(0) { $0 + $1.seconds }
    }
}
