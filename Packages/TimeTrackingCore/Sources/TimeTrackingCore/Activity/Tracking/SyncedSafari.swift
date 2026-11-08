// SyncedSafari: the visits Safari synced from other devices as Samples,
// each run of visits given to the device whose open tabs gained one of its
// URLs during the run (activity_tracking.md §6.1).

public import Foundation

/// A visit Safari synced from another device (`History.db`, `origin = 1`).
public struct SyncedVisit: Sendable, Hashable {
    public var time: Date
    public var url: String
    public var title: String

    public init(time: Date, url: String, title: String = "") {
        self.time = time
        self.url = url
        self.title = title
    }
}

/// A URL that appeared among a device's open tabs in `CloudTabs.db`
/// sometime in `interval`, between two reads.
public struct CloudTabGain: Codable, Sendable, Hashable {
    public var deviceID: String
    public var url: String
    public var interval: DateInterval

    public init(deviceID: String, url: String, interval: DateInterval) {
        self.deviceID = deviceID
        self.url = url
        self.interval = interval
    }
}

/// What the agent keeps of `CloudTabs.db` between reads, in `meta`, so
/// the visits re-read after a restart go to the same devices.
public struct CloudTabMemory: Codable, Sendable, Hashable {
    public var readAt: Date?
    /// Each device's open tab URLs at `readAt`, by device id.
    public var tabs: [String: Set<String>]
    public var gains: [CloudTabGain]

    public static let empty = Self(readAt: nil, tabs: [:], gains: [])

    public init(readAt: Date?, tabs: [String: Set<String>], gains: [CloudTabGain]) {
        self.readAt = readAt
        self.tabs = tabs
        self.gains = gains
    }

    /// The memory after reading `tabs` at `now`: every URL a device didn't
    /// have open at the previous read is a gain between the two reads; a
    /// device first seen gains nothing. Gains that ended before
    /// `now - SyncedSafari.lookback` are dropped.
    public func reading(_ tabs: [String: Set<String>], at now: Date) -> Self {
        var gains = gains.filter { $0.interval.end >= now - SyncedSafari.lookback }
        if let readAt, readAt < now {
            for (deviceID, urls) in tabs {
                guard let before = self.tabs[deviceID] else {
                    continue
                }
                for url in urls.subtracting(before).sorted() {
                    gains.append(CloudTabGain(deviceID: deviceID, url: url, interval: DateInterval(start: readAt, end: now)))
                }
            }
        }
        return Self(readAt: now, tabs: tabs, gains: gains)
    }
}

/// Synced visits as `safariHistory` Samples.
public enum SyncedSafari {
    /// Each read covers this much again, since synced visits arrive late.
    public static let lookback: TimeInterval = 24 * 3600
    /// A visit lasts until the next one if that comes within this time.
    static let runGap: TimeInterval = 300
    /// What the last visit of a run counts.
    static let lastVisitLength: TimeInterval = 60
    /// Synced visits are Safari's on the Mac (§2.3), whatever device made them.
    static let appID = "com.apple.Safari"

    /// The Samples of `visits`: a visit lasts until the next within 5
    /// minutes, else a minute; such a run of visits belongs to the one
    /// device whose tabs gained one of its URLs during it, else to
    /// `remote`.
    public static func samples(visits: [SyncedVisit], gains: [CloudTabGain], urls: URLWorkspaces) -> [Sample] {
        var runs: [[SyncedVisit]] = []
        for visit in visits.sorted(by: { ($0.time, $0.url) < ($1.time, $1.url) }) {
            if let previous = runs.last?.last, visit.time.timeIntervalSince(previous.time) <= runGap {
                runs[runs.count - 1].append(visit)
            } else {
                runs.append([visit])
            }
        }
        return runs.flatMap { run in
            let ends = run.dropFirst().map(\.time) + [(run.last?.time ?? .distantPast) + lastVisitLength]
            let deviceID = device(of: run, from: run.first?.time ?? .distantPast, to: ends.last ?? .distantPast, gains: gains)
            return zip(run, ends).flatMap { visit, end in
                let item = ActivityItem(
                    app: "Safari",
                    appID: appID,
                    window: visit.title,
                    location: visit.url,
                    workspace: urls.workspace(of: visit.url) ?? "Safari"
                )
                return Sample.times(through: DateInterval(start: visit.time, end: end)).map { time in
                    Sample(time: time, deviceID: deviceID, source: .safariHistory, state: .active, foreground: item)
                }
            }
        }
    }

    /// The one device that gained a URL of the run between `start` and `end`, else `remote`.
    private static func device(of visits: [SyncedVisit], from start: Date, to end: Date, gains: [CloudTabGain]) -> String {
        let urls = Set(visits.map { key($0.url) })
        let devices = Set(gains.filter { urls.contains(key($0.url)) && $0.interval.start <= end && $0.interval.end >= start }
            .map(\.deviceID))
        return devices.count == 1 ? devices.first ?? ActivityBlockItem.remoteDevice : ActivityBlockItem.remoteDevice
    }

    /// A URL without its fragment, which tabs and history may differ in.
    private static func key(_ url: String) -> String {
        url.firstIndex(of: "#").map { String(url[..<$0]) } ?? url
    }
}
