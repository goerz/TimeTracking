// A Sample store in memory, a block log in a temporary folder, and the
// rebuild loop between them (activity_tracking.md §2.7, §4.1).

import Foundation
@testable import TimeTrackingCore

final class RebuildRig {
    let folder: TemporaryFolder
    let store: SampleStore
    let log: BlockLogFolder
    var zone = SampleTimeline.zone
    var exclusions = ExclusionRules.empty

    init() throws {
        self.folder = try TemporaryFolder()
        self.store = try SampleStore(url: nil)
        self.log = BlockLogFolder(url: folder.url.appending(path: "blocks", directoryHint: .isDirectory))
        // The remote activity loop keeps the iOS devices' latest names.
        try store.setMeta(.deviceNames, [SampleTimeline.iPhone: "iPhone", SampleTimeline.iPad: "iPad"])
    }

    deinit {
        folder.remove()
    }

    var rules: SampleRules {
        SampleRules(exclusions: exclusions, zone: zone, maxPassiveBlock: TrackerBlockSettings().maxPassiveBlock)
    }

    var context: RebuildContext {
        RebuildContext(
            settings: TrackerBlockSettings(),
            rules: rules,
            macDeviceID: SampleTimeline.mac,
            macName: "MacBook",
            redactor: Redactor(privacy: TrackerPrivacySettings())
        )
    }

    var loop: RebuildLoop {
        RebuildLoop(store: store, log: log)
    }

    /// Inserts the timeline's Samples, those before `until` only when given.
    func insert(_ timeline: SampleTimeline, until: String? = nil) throws {
        let limit = until.map(timeline.time) ?? .distantFuture
        try store.insert(timeline.sorted.filter { $0.time < limit }, rules: rules)
    }

    /// Runs passes until no date waits; returns what each did.
    @discardableResult
    func run(now: Date) throws -> [PassResult] {
        var results: [PassResult] = []
        while let result = try loop.runOnePass(now: now, context: context) {
            results.append(result)
            if results.count > 100 {
                break
            }
        }
        return results
    }

    func day(_ text: String) -> TrackingDay {
        TrackingDay(text) ?? TrackingDay(year: 1970, month: 1, day: 1)
    }

    /// The blocks of the date's file; empty without one.
    func blocks(_ day: String) -> [ActivityBlock] {
        guard case let .text(text) = log.content(for: self.day(day)) else {
            return []
        }
        return BlockLogFile.parse(text).blocks
    }

    func changedDays() throws -> Set<TrackingDay> {
        try store.meta(.changedDays) ?? []
    }

    /// The open block the last pass that reached now handed to current.json.
    static func open(in results: [PassResult]) -> ActivityBlock? {
        for result in results.reversed() {
            if case let .formed(_, _, .set(open)) = result {
                return open
            }
        }
        return nil
    }
}
