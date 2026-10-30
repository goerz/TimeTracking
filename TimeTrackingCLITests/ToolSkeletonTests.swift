// The two tools as subprocesses (spec_architecture.md §8, spec_automation.md §1).

import Foundation
import Testing

struct ToolSkeletonTests {
    @Test("ARCH-21 tracker-event exits non-zero within 100 ms when the agent is not running")
    func trackerEventWithoutAgent() throws {
        let folder = try TemporaryFolder("tracker-event")
        let environment = ["TIMETRACKING_SOCKET": folder.url.appending(path: "tracker.sock").path]
        // The first launch pays for loading the binary. Process launch time
        // varies with load, so the bound must hold for the fastest of five
        // runs; a tool that waits or retries misses it on every run.
        _ = try ToolProcess.run("tracker-event", ["tmux", "pane-focus-in"], environment: environment)
        var durations: [Duration] = []
        for _ in 0 ..< 5 {
            let result = try ToolProcess.run("tracker-event", ["tmux", "pane-focus-in"], environment: environment)
            #expect(result.status != 0)
            #expect(result.standardError.contains("not running"))
            durations.append(result.duration)
        }
        #expect(try #require(durations.min()) < .milliseconds(100), "\(durations)")
    }
}
