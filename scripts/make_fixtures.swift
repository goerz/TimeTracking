#!/usr/bin/env swift
// make_fixtures.swift: writes the store fixtures of spec_architecture.md §3.4
// (Fixtures/Store/empty.json, small.json, large.json, running.json) in the
// JSON export format of spec_data_and_sync.md §5.1, and the block-log
// fixture Fixtures/Activity/blocks/, by running the package's MakeFixtures
// tool over TimeTrackingCore's SyntheticDataset. Deterministic: running it
// twice gives identical files (TimeTrackingCoreTests checks the committed ones).

import Foundation

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let process = Process()

process.executableURL = URL(filePath: "/usr/bin/env")
process.arguments = [
    "swift", "run", "--quiet", "--package-path", root.appending(path: "Packages/TimeTrackingCore").path,
    "MakeFixtures", root.appending(path: "Fixtures").path,
]

var environment = ProcessInfo.processInfo.environment

environment["DEVELOPER_DIR"] = environment["DEVELOPER_DIR"] ?? "/Applications/Xcode.app/Contents/Developer"
process.environment = environment
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
