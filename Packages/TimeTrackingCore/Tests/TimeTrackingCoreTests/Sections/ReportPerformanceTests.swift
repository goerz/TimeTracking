// The report targets of spec_data_and_sync.md §7.5 on the large dataset
// (§9.1: ten years, about 24,000 entries). Slow: only with
// TIMETRACKING_TEST_SLOW=1 (make test).

import Foundation
import Testing
import TimeTrackingCore

extension Tag {
    @Tag static var slow: Self
}

@Suite(.tags(.slow), .enabled(if: ProcessInfo.processInfo.environment["TIMETRACKING_TEST_SLOW"] == "1"))
struct ReportPerformanceTests {
    /// The best of `runs` timings, in milliseconds.
    static func milliseconds(runs: Int = 3, _ body: () async throws -> Void) async rethrows -> Double {
        var best = Double.infinity
        for _ in 0 ..< runs {
            let start = ContinuousClock.now
            try await body()
            let elapsed = ContinuousClock.now - start
            best = min(best, Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
        }
        return best
    }

    @Test("Reports over one year by day under 100 ms and ten years by month under 300 ms, four levels, on the large dataset")
    func reportTargets() async throws {
        let dataset = SyntheticDataset.large()
        let store = try await dataset.populatedStore(withTombstones: false)
        let last = dataset.days.upperBound
        let levels: [GroupKey] = [.client, .area, .project, .task]
        let year = ReportQuery(days: last.adding(days: -364) ... last, groupBy: levels, granularity: .day)
        let decade = ReportQuery(days: dataset.days, groupBy: levels, granularity: .month)
        let yearTree = try await store.report(year)
        #expect(yearTree.entryCount > 2000)
        let yearTime = try await Self.milliseconds { _ = try await store.report(year) }
        let decadeTime = try await Self.milliseconds { _ = try await store.report(decade) }
        let snapshotTime = try await Self.milliseconds {
            _ = try await store.reportSnapshot(ReportRequest(
                days: year.days,
                today: last,
                levels: levels,
                granularity: .day,
                includeEntries: false
            ))
        }
        #expect(yearTime < 100, "report over one year by day: \(yearTime) ms")
        #expect(decadeTime < 300, "report over ten years by month: \(decadeTime) ms")
        #expect(snapshotTime < 100, "Reports snapshot over one year: \(snapshotTime) ms")
    }
}
