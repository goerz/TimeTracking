// SyncedSafariCollector: blocks from Safari history synced from other
// devices, attributed through CloudTabs.db (spec_activity_tracking.md §6.1).

import Foundation
import TimeTrackingCore

/// Forms blocks from `History.db` visits with `origin = 1`: each visit is a
/// sample, and a gap over 5 minutes closes the block. A block carries `dev`
/// `remote` unless exactly one device's `CloudTabs.db` tab set changed to
/// include a visited URL within the block; then it carries that device's name.
struct SyncedSafariCollector {
    /// The gap that closes a block, and the CloudTabs poll interval.
    static let gap: TimeInterval = 300
    static let remoteDevice = "remote"

    /// Tabs per device at the last poll.
    private var lastTabs: [String: Set<String>] = [:]
    /// URLs that appeared in a device's tab set, with the poll time.
    private(set) var additions: [(time: Date, device: String, url: String)] = []

    /// Polls `CloudTabs.db` and records which device gained which tab.
    mutating func poll(history: any BrowserHistory, now: Date) {
        guard let devices = history.cloudTabs() else {
            return
        }
        for device in devices {
            let previous = lastTabs[device.name]
            if let previous {
                for url in device.urls.subtracting(previous) {
                    additions.append((now, device.name, url))
                }
            }
            lastTabs[device.name] = device.urls
        }
        additions.removeAll { now.timeIntervalSince($0.time) > 2 * 86400 }
    }

    /// The closed blocks of `visits` (time-ordered or not).
    func blocks(visits: [HistoryVisit], context: ResolveContext, timeZone: TimeZone) -> [ClosedBlock] {
        var blockSettings = context.settings.blocks
        blockSettings.idleClose = Self.gap
        var blocker = Blocker(settings: blockSettings, timeZone: timeZone, device: Self.remoteDevice)
        blocker.creditCap = Self.gap
        let rules = BrowserItemRules(settings: context.settings.browser, exclusions: context.exclusions)
        var closed: [ClosedBlock] = []
        var urlsByTime: [(Date, String)] = []
        for visit in visits.sorted(by: { $0.time < $1.time }) {
            guard let parts = rules.parts(for: visit.url) else {
                continue
            }
            let item = parts.isExcluded
                ? SampleItem(context: "safari", subject: ExclusionRules.privateMarker, groupKey: "safari", app: "com.apple.Safari")
                : SampleItem(context: "safari", subject: parts.subject, detail: parts.detail, groupKey: parts.groupKey, app: "com.apple.Safari")
            if !parts.isExcluded {
                urlsByTime.append((visit.time, visit.url))
            }
            closed += blocker.add(Sample(time: visit.time, state: .active, primary: item, bundleID: "com.apple.Safari"))
        }
        closed += blocker.flush()
        return closed.map { attribute($0, urls: urlsByTime) }
    }

    /// Sets `dev` to the one device whose tab set gained a visited URL within the block.
    private func attribute(_ closed: ClosedBlock, urls: [(Date, String)]) -> ClosedBlock {
        let block = closed.block
        let visited = Set(urls.filter { $0.0 >= block.start && $0.0 <= block.end }.map(\.1))
        let devices = Set(additions.filter { addition in
            visited.contains(addition.url)
                && addition.time >= block.start.addingTimeInterval(-Self.gap)
                && addition.time <= block.end.addingTimeInterval(Self.gap)
        }.map(\.device))
        guard devices.count == 1, let device = devices.first else {
            return closed
        }
        var result = closed
        result.block = ActivityBlock(
            start: block.start,
            end: block.end,
            activeSeconds: block.activeSeconds,
            device: device,
            groupKey: block.groupKey,
            groupShare: block.groupShare,
            items: block.items,
            utcOffset: block.utcOffset,
            source: block.source,
            background: block.background
        )
        return result
    }
}
