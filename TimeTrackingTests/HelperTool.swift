// HelperTool: the Debug app's bundled `timetracking` run against a store
// file, and an event-driven wait for the models (spec_automation.md §1,
// spec_architecture.md §3).

import Foundation
import Observation
import TimeTrackingCore

/// What a tool run printed.
struct HelperToolResult {
    var status: Int32
    var output: String
    var error: String
}

/// Runs `Contents/Helpers/timetracking` of the host app.
enum HelperTool {
    static var url: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/timetracking")
    }

    /// Runs the tool on `store` with "now" fixed at `now`, in this
    /// process's zone and with an empty temporary `HOME`.
    static func run(_ arguments: [String], store: URL, now: Date) throws -> HelperToolResult {
        let home = FileManager.default.temporaryDirectory.appending(path: "helper-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "TIMETRACKING_STORE": store.path,
            "TIMETRACKING_NOW": now.formatted(.iso8601),
            "TZ": TimeZone.current.identifier,
            "NO_COLOR": "1",
            "HOME": home.path,
        ]) { $1 }
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let outData = output.fileHandleForReading.readDataToEndOfFile()
        let errData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return HelperToolResult(
            status: process.terminationStatus,
            output: String(decoding: outData, as: UTF8.self),
            error: String(decoding: errData, as: UTF8.self)
        )
    }
}

/// Waits until `condition` holds, re-checking whenever an observed value
/// it reads changes. The watchdog ends a broken run after `timeout`; on
/// success nothing sleeps.
@MainActor
func eventually(timeout: Duration = .seconds(30), _ condition: @escaping @MainActor () -> Bool) async -> Bool {
    let watchdog = Watchdog()
    let timer = Task {
        try await Task.sleep(for: timeout)
        watchdog.fire()
    }
    defer { timer.cancel() }
    while !condition() {
        guard !watchdog.fired else {
            return false
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            watchdog.waiting = continuation
            withObservationTracking {
                _ = condition()
            } onChange: {
                Task { @MainActor in watchdog.resume() }
            }
        }
    }
    return true
}

/// Resumes the pending wait once, on a change or when the timeout fires.
@MainActor
private final class Watchdog {
    var waiting: CheckedContinuation<Void, Never>?
    private(set) var fired = false

    func resume() {
        waiting?.resume()
        waiting = nil
    }

    func fire() {
        fired = true
        resume()
    }
}
