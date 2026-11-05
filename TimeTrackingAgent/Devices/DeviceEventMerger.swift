// DeviceEventMerger: one device-day's DeviceEvents as stretches of the
// user's timeline (activity_tracking.md §2.8, §6.2, §7.2; ios.md §9).

import Foundation
import TimeTrackingCore

/// Turns the events of one device on one local day into stretches of
/// attention, each with an item and a rank:
/// - a counted ladder step k (not `early`) covers the minutes since the
///   set's previous counted step, ending at its time (one minute for the
///   day's first), with the set's label as context, subject, and group key;
///   "Everything" says only that the device was used, so its item is the
///   device's name as context and group key, without a subject;
/// - a web extension tab covers up to a minute, until the next tab, as a
///   `safari` item under the browser rules of §3.3 and the exclusions;
/// - an `appOpened` automation covers the time to the matching
///   `appClosed` (at most `max_block`), any other automation a minute,
///   with its label;
/// - the app's `foreground` covers the time to its `background`.
/// Where stretches overlap the most specific wins (`Timeline.resolve`):
/// the app, then automations, web tabs, named sets, and "Everything" last.
/// A Focus that suspends collection closes the block at its `on`.
nonisolated struct DeviceEventMerger {
    /// What a point event covers.
    static let pointLength: TimeInterval = 60
    static let safariApp = "com.apple.mobilesafari"

    var settings: TrackerSettings
    var exclusions: ExclusionRules

    /// A stretch of attention before it is tied to the device.
    struct Stretch {
        var start: Date
        var end: Date
        var item: SampleItem
        var rank: Int
    }

    /// The stretches of `events` (one device's, one local day's) on
    /// `device`, clipped to the day, and the times of the Focus closers.
    func stretches(_ events: [DeviceEvent], device: String, timeZone: TimeZone) -> (stretches: [TimelineStretch], closers: [Date]) {
        let sorted = events.sorted { ($0.time, $0.sequence) < ($1.time, $1.sequence) }
        guard let first = sorted.first else {
            return ([], [])
        }
        let dayStart = ActivityTimestamp.startOfDay(first.time, timeZone: timeZone)
        let dayEnd = ActivityTimestamp.nextMidnight(after: first.time, timeZone: timeZone)
        let stretches = (ladder(sorted, dayStart: dayStart, device: device) + web(sorted) + intents(sorted) + app(sorted))
            .compactMap { stretch in
                let start = max(stretch.start, dayStart)
                let end = min(stretch.end, dayEnd)
                return end > start ? TimelineStretch(start: start, end: end, item: stretch.item, device: device, rank: stretch.rank) : nil
            }
        let closers = sorted.filter { $0.source == .focus && $0.kind == "on" && !$0.payloadBool("collect", default: true) }.map(\.time)
        return (stretches, closers)
    }

    // MARK: Stretches

    private func ladder(_ events: [DeviceEvent], dayStart: Date, device: String) -> [Stretch] {
        var previous: [String: (step: Int, time: Date)] = [:]
        var result: [Stretch] = []
        for event in events where event.source == .ladder && event.kind == "minute" && !event.payloadBool("early", default: false) {
            guard let step = event.payloadInt("n") else {
                continue
            }
            let last = previous[event.label]
            if let last, step <= last.step {
                continue
            }
            let minutes = last.map { step - $0.step } ?? 1
            let start = max(last?.time ?? dayStart, event.time.addingTimeInterval(-TimeInterval(minutes) * 60))
            previous[event.label] = (step, event.time)
            let everything = event.label == LadderSet.everythingLabel
            let item = everything
                ? SampleItem(context: device, subject: "", groupKey: device, app: "ladder")
                : SampleItem(context: event.label, subject: event.label, groupKey: event.label, app: "ladder")
            result.append(Stretch(start: start, end: event.time, item: item, rank: everything ? 1 : 3))
        }
        return result
    }

    private func web(_ events: [DeviceEvent]) -> [Stretch] {
        let tabs = events.filter { $0.source == .webext && $0.kind == "tab" }
        let rules = BrowserItemRules(settings: settings.browser, exclusions: exclusions)
        return tabs.enumerated().compactMap { index, event in
            guard let parts = rules.parts(for: "https://" + event.label) else {
                return nil
            }
            let item = SampleItem(browser: "safari", parts: parts, app: Self.safariApp)
            var end = event.time.addingTimeInterval(Self.pointLength)
            if index + 1 < tabs.count {
                end = min(end, tabs[index + 1].time)
            }
            return Stretch(start: event.time, end: end, item: item, rank: 4)
        }
    }

    private func intents(_ events: [DeviceEvent]) -> [Stretch] {
        let automations = events.filter { $0.source == .intent }
        var result: [Stretch] = []
        let opened = ActivityEventKind.appOpened.rawValue
        let closed = ActivityEventKind.appClosed.rawValue
        for (index, event) in automations.enumerated() where event.kind != closed {
            var end = event.time.addingTimeInterval(Self.pointLength)
            let next = automations[(index + 1)...].first { $0.label == event.label && ($0.kind == opened || $0.kind == closed) }
            if event.kind == opened, let next, next.kind == closed, next.time.timeIntervalSince(event.time) <= settings.blocks.maxBlock {
                end = next.time
            }
            let item = SampleItem(context: event.label, subject: event.label, groupKey: event.label, app: "intent")
            result.append(Stretch(start: event.time, end: end, item: item, rank: 5))
        }
        return result
    }

    private func app(_ events: [DeviceEvent]) -> [Stretch] {
        let transitions = events.filter { $0.source == .app }
        var result: [Stretch] = []
        for (index, event) in transitions.enumerated() where event.kind == "foreground" {
            var end = event.time.addingTimeInterval(Self.pointLength)
            if let next = transitions[(index + 1)...].first, next.time.timeIntervalSince(event.time) <= settings.blocks.maxBlock {
                end = next.time
            }
            let item = SampleItem(
                context: CollectionLog.appLabel,
                subject: CollectionLog.appLabel,
                groupKey: CollectionLog.appLabel,
                app: "app"
            )
            result.append(Stretch(start: event.time, end: end, item: item, rank: 6))
        }
        return result
    }
}
