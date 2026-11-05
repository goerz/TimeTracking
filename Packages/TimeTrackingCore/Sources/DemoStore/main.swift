// DemoStore: the seeding step of `make demo` (architecture.md §2.5).
// Development only; not linked by any app.
//
//   swift run --package-path Packages/TimeTrackingCore DemoStore <fixture> <store.sqlite> [<Activity folder>]
//
// Replaces the store with Fixtures/Store/<fixture>.json moved to today
// (DemoSeed, FixtureShift) and, with an Activity folder, its blocks/ with
// the fixture's block log. Refuses a store outside a Debug or simulator
// container.

import Foundation
import TimeTrackingCore

let arguments = CommandLine.arguments

guard (3 ... 4).contains(arguments.count) else {
    FileHandle.standardError.write(Data("usage: DemoStore <fixture> <store.sqlite> [<Activity folder>]\n".utf8))
    exit(64)
}

let name = arguments[1]
let store = URL(filePath: arguments[2], directoryHint: .notDirectory)
let activity = arguments.count == 4 ? URL(filePath: arguments[3], directoryHint: .isDirectory) : nil

guard let fixture = StoreFixture.url(named: name) else {
    let names = SyntheticDataset.fixtureNames.joined(separator: ", ")
    FileHandle.standardError.write(Data("DemoStore: no fixture named \(name) (known: \(names))\n".utf8))
    exit(64)
}

do {
    let report = try await DemoSeed.seed(
        document: Data(contentsOf: fixture),
        dataset: SyntheticDataset.fixture(named: name),
        store: store,
        activity: activity,
        now: SystemClock().now
    )
    let blocks = activity == nil ? "" : ", \(report.blocks) blocks"
    let counts = "\(report.entries) entries (\(report.clipped) cut at now, \(report.dropped) dropped)\(blocks)"
    FileHandle.standardError.write(Data("Seeded \(store.path) with \(name) moved by \(report.days) days: \(counts)\n".utf8))
} catch {
    FileHandle.standardError.write(Data("DemoStore: \(error.localizedDescription)\n".utf8))
    exit(1)
}
