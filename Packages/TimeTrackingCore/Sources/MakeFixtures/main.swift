// MakeFixtures: writes the deterministic, synthetic fixtures of
// architecture.md §3.4 (dates in 2024).
//
//   swift run --package-path Packages/TimeTrackingCore MakeFixtures <Fixtures folder>
//
// Writes Store/<name>.json for every SyntheticDataset fixture and
// Activity/blocks/YYYY-MM.jsonl from the small dataset.

import Foundation
import TimeTrackingCore

let arguments = CommandLine.arguments

guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: MakeFixtures <Fixtures folder>\n".utf8))
    exit(64)
}

let root = URL(filePath: arguments[1], directoryHint: .isDirectory)
let storeFolder = root.appending(path: "Store", directoryHint: .isDirectory)

try FileManager.default.createDirectory(at: storeFolder, withIntermediateDirectories: true)
for name in SyntheticDataset.fixtureNames {
    guard let dataset = SyntheticDataset.fixture(named: name) else {
        continue
    }
    var data = try await dataset.exportDocument()
    data.append(Data("\n".utf8))
    try data.write(to: storeFolder.appending(path: "\(name).json"))
    FileHandle.standardError.write(Data("wrote Store/\(name).json\n".utf8))
}

let activity = root.appending(path: "Activity", directoryHint: .isDirectory)

try? FileManager.default.removeItem(at: activity.appending(path: "blocks"))
if let small = SyntheticDataset.fixture(named: "small") {
    try await small.activityLog(to: activity)
    FileHandle.standardError.write(Data("wrote Activity/blocks\n".utf8))
}
