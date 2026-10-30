// The two tools as subprocesses (spec_architecture.md §8, spec_automation.md §1).

import Foundation
import Testing

struct ToolSkeletonTests {
    @Test func versionPrintsTheBundleVersion() throws {
        let result = try ToolProcess.run("timetracking", ["--version"])
        #expect(result.status == 0)
        #expect(result.standardOutput.wholeMatch(of: /\d+\.\d+ \(\d+\)\n/) != nil)
    }

    @Test("ARCH-21 tracker-event exits non-zero within 100 ms when the agent is not running")
    func trackerEventWithoutAgent() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "tracker-event-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let environment = ["TIMETRACKING_SOCKET": folder.appending(path: "tracker.sock").path]
        // The first launch pays for loading the binary; the second is measured.
        _ = try ToolProcess.run("tracker-event", ["tmux", "pane-focus-in"], environment: environment)
        let result = try ToolProcess.run("tracker-event", ["tmux", "pane-focus-in"], environment: environment)
        #expect(result.status != 0)
        #expect(result.standardError.contains("not running"))
        #expect(result.duration < .milliseconds(100))
    }
}
