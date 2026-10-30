// The agent's flags `--replay`, `--record`, and `--unregister`
// (spec_activity_tracking.md §5, spec_architecture.md ARCH-16).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct FlagTests {
    static let fixture = AgentHarness.fixtureURL("samples/2024-03-14.jsonl")

    /// What a run of the agent's executable gave.
    struct AgentRun: Sendable {
        var status: Int32
        var output: String
        var error: String
    }

    /// Runs the agent's own executable with `arguments` and a clean
    /// environment whose `HOME` is an empty temporary folder.
    private func runAgent(_ arguments: [String]) async throws -> AgentRun {
        let executable = try #require(Bundle.main.executableURL)
        let home = FileManager.default.temporaryDirectory.appending(path: "agent-home-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        return try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin", "TMPDIR": NSTemporaryDirectory()]
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            try process.run()
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return AgentRun(
                status: process.terminationStatus,
                output: String(decoding: outputData, as: UTF8.self),
                error: String(decoding: errorData, as: UTF8.self)
            )
        }.value
    }

    @Test("ARCH-16 TRK-29 --replay reproduces the expected block log byte for byte and exits 0")
    func replayMatches() async throws {
        let day = try AgentHarness.sampleDayCopy()
        let result = try await runAgent(["--replay", day.path])
        #expect(result.status == 0, "\(result.error)")
        let expected = try String(contentsOf: Replay.expectedURL(for: Self.fixture), encoding: .utf8)
        #expect(Replay.normalized(result.output) == Replay.normalized(expected))
        let outcome = try Replay.run(fixture: Self.fixture)
        #expect(outcome.matches)
        #expect(outcome.produced == expected)
    }

    @Test("TRK-29 a changed threshold makes --replay exit non-zero")
    func replayDiffers() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "replay-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appending(path: "2024-03-14.jsonl")
        try FileManager.default.copyItem(at: Self.fixture, to: copy)
        try FileManager.default.copyItem(at: Replay.expectedURL(for: Self.fixture), to: Replay.expectedURL(for: copy))
        #expect(try await runAgent(["--replay", copy.path]).status == 0)
        try "[blocks]\nidle_close = \"2m\"\n".write(
            to: folder.appending(path: "2024-03-14.settings.toml"),
            atomically: true,
            encoding: .utf8
        )
        let result = try await runAgent(["--replay", copy.path])
        #expect(result.status != 0)
        #expect(result.error.contains("differs"))
    }

    @Test("TRK-30 --record output contains no home path, host name, or URL path of the live run")
    func recordAnonymizes() async throws {
        let record = FileManager.default.temporaryDirectory.appending(path: "record-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: record) }
        let harness = try AgentHarness(recordFolder: record)
        harness.loadTerminalFixtures()
        harness.commands.set(
            ProcessTable.command,
            AgentHarness.fixture("ps/terminals.txt") + "  999     1 ??       S    /Users/alex/bin/alex-mbp-sync\n"
        )
        harness.wezterm()
        await harness.run(for: 60)
        harness.frontmost("com.apple.Safari", name: "Safari")
        harness.scripts.results["com.apple.Safari"] = .value(AgentHarness.fixture("applescript/safari-pull-request.txt"))
        harness.history.safari = [(HistoryVisit(time: harness.clock.now, browser: "safari", url: BrowserTests.pullRequest, title: ""), 0)]
        await harness.run(for: 60)
        #expect(harness.samples().contains { $0.primary?.subject == "github.com/owner/repo" })

        let manager = FileManager.default
        let files = try #require(manager.enumerator(atPath: record.path)?.allObjects as? [String]).filter { !$0.hasSuffix("/") }
        #expect(files.contains("samples/2024-03-14.jsonl"))
        #expect(files.contains { $0.hasPrefix("tmux/") })
        #expect(files.contains { $0.hasPrefix("applescript/") })
        var text = ""
        for file in files {
            var isFolder: ObjCBool = false
            if manager.fileExists(atPath: record.appending(path: file).path, isDirectory: &isFolder), !isFolder.boolValue {
                text += try String(contentsOf: record.appending(path: file), encoding: .utf8)
            }
        }
        #expect(!text.isEmpty)
        for secret in ["/Users/alex", "alex-mbp", "Documents/Papers", "2026_Noise", "owner/repo", "pull/123", "diff=split"] {
            #expect(!text.contains(secret), "\(secret)")
        }
        #expect(text.contains("github.com"))
    }

    @MainActor
    private final class FakeService: LoginItemService {
        var isRegistered: Bool
        var fails = false
        private(set) var calls = 0

        init(registered: Bool) {
            self.isRegistered = registered
        }

        func unregister() throws {
            calls += 1
            guard !fails else {
                throw CocoaError(.featureUnsupported)
            }
            isRegistered = false
        }
    }

    @Test("--unregister removes the registration; not being registered is success")
    func unregister() {
        let registered = FakeService(registered: true)
        #expect(Unregistration.run(registered) == 0)
        #expect(!registered.isRegistered)
        let absent = FakeService(registered: false)
        #expect(Unregistration.run(absent) == 0)
        #expect(absent.calls == 0)
        let stuck = FakeService(registered: true)
        stuck.fails = true
        #expect(Unregistration.run(stuck) == 1)
    }
}
