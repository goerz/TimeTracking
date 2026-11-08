// DeviceEventConverter: one device-date's DeviceEvents as Samples
// (activity_tracking.md §2.5, §6.2; ios.md §9).

import Foundation

/// Turns the events of one iPhone or iPad on one of its local dates into
/// Samples, one every 30 seconds through the time each event counts:
/// - a counted Screen Time step covers the minutes since the set's previous
///   step that day, placed just before the step's time;
/// - a Safari tab counts until the next tab, at most a minute;
/// - an automation's app opening counts until its closing within
///   `max_block`, any other automation event a minute;
/// - the app's own time counts from foreground to background, at most
///   `max_block`;
/// - a Focus that pauses collection gives `paused` Samples while it is on.
///
/// The device's last events before the date tell what was still on at
/// 00:00, so such time continues into the date; its first events after the
/// date end what is on at the date's end.
public struct DeviceEventConverter: Sendable {
    /// What a point event counts.
    static let pointLength: TimeInterval = 60
    static let safariAppID = "com.apple.mobilesafari"

    public var maxBlock: TimeInterval
    /// The workspaces of web pages (§2.3 rule 4).
    public var urls: URLWorkspaces

    public init(maxBlock: TimeInterval, urls: URLWorkspaces) {
        self.maxBlock = maxBlock
        self.urls = urls
    }

    /// The Samples of `deviceID` in `date`, the device-date's interval,
    /// from `events` of that date, `before`, the device's last events
    /// before it, and `after`, its first events after it; `deviceName`
    /// names the "Everything" set.
    public func samples(
        deviceID: String,
        deviceName: String,
        date: DateInterval,
        events: [DeviceEvent],
        before: [DeviceEvent] = [],
        after: [DeviceEvent] = []
    ) -> [Sample] {
        let all = (before + events + after).sorted { ($0.time, $0.sequence) < ($1.time, $1.sequence) }
        var stretches = screenTime(all, deviceName: deviceName, date: date)
        stretches += tabs(all) + automations(all) + ownTime(all)
        var samples = stretches.flatMap { stretch in
            Self.times(of: stretch.interval, within: date).map { time in
                Sample(time: time, deviceID: deviceID, source: stretch.source, state: .active, foreground: stretch.item)
            }
        }
        samples += pauses(all, date: date).flatMap { interval in
            Self.times(of: interval, within: date).map { Sample(time: $0, deviceID: deviceID, source: .focus, state: .paused) }
        }
        return samples.sorted { $0.time < $1.time }
    }

    // MARK: Stretches

    private struct Stretch {
        var interval: DateInterval
        var item: ActivityItem
        var source: SampleSource
    }

    /// Counted steps (not `early`), each covering the minutes since the
    /// set's previous step of the same date, the first since the date's start.
    private func screenTime(_ events: [DeviceEvent], deviceName: String, date: DateInterval) -> [Stretch] {
        var previous: [String: (step: Int, time: Date)] = [:]
        var result: [Stretch] = []
        for event in events where event.source == .screenTime && event.kind == "minute" && !event.payloadBool("early", default: false) {
            guard let step = event.payloadInt("n"), date.contains(event.time) else {
                continue
            }
            let last = previous[event.label]
            if let last, step <= last.step {
                continue
            }
            previous[event.label] = (step, event.time)
            let minutes = TimeInterval(step - (last?.step ?? 0)) * 60
            let start = max(last?.time ?? date.start, event.time - minutes)
            let everything = event.label == ScreenTimeSet.everythingLabel
            let name = everything ? deviceName : event.label
            let item = ActivityItem(
                app: name,
                appID: everything ? ActivityItem.everythingAppID : ActivityItem.screenTimeAppID,
                workspace: name
            )
            result.append(Stretch(interval: DateInterval(start: start, end: max(start, event.time)), item: item, source: .screenTime))
        }
        return result
    }

    /// Each tab until the next, at most a minute.
    private func tabs(_ events: [DeviceEvent]) -> [Stretch] {
        let tabs = events.filter { $0.source == .webext && $0.kind == "tab" }
        return tabs.enumerated().map { index, event in
            let location = "https://" + event.label
            let item = ActivityItem(
                app: "Safari",
                appID: Self.safariAppID,
                location: location,
                workspace: urls.workspace(of: location) ?? "Safari"
            )
            var end = event.time + Self.pointLength
            if index + 1 < tabs.count {
                end = min(end, tabs[index + 1].time)
            }
            return Stretch(interval: DateInterval(start: event.time, end: max(event.time, end)), item: item, source: .webext)
        }
    }

    /// An app opening until its closing within `max_block`; any other event a minute.
    private func automations(_ events: [DeviceEvent]) -> [Stretch] {
        let automations = events.filter { $0.source == .intent }
        let opened = ActivityEventKind.appOpened.rawValue
        let closed = ActivityEventKind.appClosed.rawValue
        return automations.enumerated().compactMap { index, event in
            guard event.kind != closed else {
                return nil
            }
            var end = event.time + Self.pointLength
            let next = automations[(index + 1)...].first { $0.label == event.label && ($0.kind == opened || $0.kind == closed) }
            if event.kind == opened, let next, next.kind == closed, next.time.timeIntervalSince(event.time) <= maxBlock {
                end = next.time
            }
            let item = ActivityItem(app: event.label, appID: "intent", workspace: event.label)
            return Stretch(interval: DateInterval(start: event.time, end: max(event.time, end)), item: item, source: .intent)
        }
    }

    /// The app in front until it goes to the background, at most `max_block`.
    private func ownTime(_ events: [DeviceEvent]) -> [Stretch] {
        let transitions = events.filter { $0.source == .app }
        return transitions.enumerated().compactMap { index, event in
            guard event.kind == "foreground" else {
                return nil
            }
            var end = event.time + Self.pointLength
            if let next = transitions[(index + 1)...].first, next.kind == "background" {
                end = min(next.time, event.time + maxBlock)
            }
            let item = ActivityItem(app: CollectionLog.appLabel, appID: "app", workspace: CollectionLog.appLabel)
            return Stretch(interval: DateInterval(start: event.time, end: max(event.time, end)), item: item, source: .app)
        }
    }

    /// The time a Focus that pauses collection is on: from its `on` with
    /// `collect` false to the next `off` or `on`, else to the date's end.
    private func pauses(_ events: [DeviceEvent], date: DateInterval) -> [DateInterval] {
        let focus = events.filter { $0.source == .focus }
        return focus.enumerated().compactMap { index, event in
            guard event.kind == "on", !event.payloadBool("collect", default: true) else {
                return nil
            }
            let end = focus[(index + 1)...].first?.time ?? date.end
            return DateInterval(start: event.time, end: max(event.time, end))
        }
    }

    // MARK: Sample times

    /// The Sample times through `interval` clipped to the date.
    static func times(of interval: DateInterval, within date: DateInterval) -> [Date] {
        interval.intersection(with: date).map(Sample.times(through:)) ?? []
    }
}
