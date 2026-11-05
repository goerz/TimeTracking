// SyncedSafariCollector: samples from Safari history synced from other
// devices, attributed through CloudTabs.db (activity_tracking.md §6.1).

import Foundation
import TimeTrackingCore

/// Turns `History.db` visits with `origin = 1` into samples of the user's
/// timeline, attributed through the `CloudTabs.db` tab sets.
struct SyncedSafariCollector {
    /// The gap that ends a run of visits, and the CloudTabs poll interval.
    static let gap: TimeInterval = 300
    static let remoteDevice = ActivityDeviceTime.remote

    /// Tabs per device at the last poll.
    private var lastTabs: [String: Set<String>] = [:]
    /// URLs that appeared in a device's tab set, with the poll time.
    private(set) var additions: [TabAddition] = []

    /// Polls `CloudTabs.db` and records which device gained which tab.
    mutating func poll(history: any BrowserHistory, now: Date) {
        guard let devices = history.cloudTabs() else {
            return
        }
        for device in devices {
            let previous = lastTabs[device.name]
            if let previous {
                for url in device.urls.subtracting(previous) {
                    additions.append(TabAddition(time: now, device: device.name, url: url))
                }
            }
            lastTabs[device.name] = device.urls
        }
        additions.removeAll { now.timeIntervalSince($0.time) > 2 * 86_400 }
    }

    /// The visits as samples of the user's timeline (§2.8), each with its
    /// device: a run of visits without a gap over 5 minutes carries
    /// `remote` unless exactly one device's tab set gained a visited URL
    /// within the run (or 5 minutes around it); then that device's name.
    func samples(visits: [HistoryVisit], context: ResolveContext) -> [(sample: Sample, device: String)] {
        let rules = BrowserItemRules(settings: context.settings.browser, exclusions: context.exclusions)
        var runs: [[(sample: Sample, url: String?)]] = []
        var last = Date.distantPast
        for visit in visits.sorted(by: { $0.time < $1.time }) {
            guard let parts = rules.parts(for: visit.url) else {
                continue
            }
            let item = SampleItem(browser: "safari", parts: parts, app: BrowserApp.safariBundleID)
            let sample = Sample(time: visit.time, state: .active, primary: item, bundleID: BrowserApp.safariBundleID)
            let entry = (sample: sample, url: parts.isExcluded ? nil : Optional(visit.url))
            if visit.time.timeIntervalSince(last) > Self.gap || runs.isEmpty {
                runs.append([entry])
            } else {
                runs[runs.count - 1].append(entry)
            }
            last = visit.time
        }
        return runs.flatMap { run in
            let device = attribution(run)
            return run.map { (sample: $0.sample, device: device) }
        }
    }

    /// The one device whose tab set gained a URL of `run` around it, else `remote`.
    private func attribution(_ run: [(sample: Sample, url: String?)]) -> String {
        guard let start = run.first?.sample.time, let end = run.last?.sample.time else {
            return Self.remoteDevice
        }
        let visited = Set(run.compactMap(\.url))
        let devices = Set(additions.filter { addition in
            visited.contains(addition.url)
                && addition.time >= start.addingTimeInterval(-Self.gap)
                && addition.time <= end.addingTimeInterval(Self.gap)
        }.map(\.device))
        return devices.count == 1 ? devices.first ?? Self.remoteDevice : Self.remoteDevice
    }
}

/// A URL that appeared in a device's tab set at a poll.
struct TabAddition: Hashable {
    var time: Date
    var device: String
    var url: String
}
