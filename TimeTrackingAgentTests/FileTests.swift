// The agent's flags and the files it shares with other processes:
// `--replay`, `--record`, database copies, `agent.lock`, hung commands, and
// a settings file evicted by iCloud Drive (activity_tracking.md §3.3, §5, §7).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct FileTests {
    /// What a run of the agent's executable gave.
    struct AgentRun: Sendable {
        var status: Int32
        var error: String
    }

    /// Runs the agent's own executable with `arguments` and a clean
    /// environment whose `HOME` is an empty temporary folder.
    private func runAgent(_ arguments: [String]) async throws -> AgentRun {
        let executable = try #require(Bundle.main.executableURL)
        let home = try TemporaryFolder.make("agent-home")
        defer { try? FileManager.default.removeItem(at: home) }
        return try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin", "TMPDIR": NSTemporaryDirectory()]
            let error = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = error
            try process.run()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return AgentRun(status: process.terminationStatus, error: String(decoding: errorData, as: UTF8.self))
        }.value
    }

    /// The fixture of `Fixtures/Agent/replay/` as a folder: the test bundle
    /// holds its files flat.
    private func replayFixture() throws -> URL {
        let folder = try TemporaryFolder.make("replay")
        let blocks = folder.appending(path: "blocks", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: blocks, withIntermediateDirectories: true)
        for (file, target) in [
            ("replay/samples.jsonl", folder.appending(path: "samples.jsonl")),
            ("replay/fixture.json", folder.appending(path: "fixture.json")),
            ("replay/blocks/2024-03-12.jsonl", blocks.appending(path: "2024-03-12.jsonl")),
        ] {
            try FileManager.default.copyItem(at: AgentHarness.fixtureURL(file), to: target)
        }
        return folder
    }

    @Test(
        "ARCH-16 TRK-40 --replay reproduces the expected date files byte for byte and exits 0; a changed threshold makes it exit non-zero"
    )
    func replay() async throws {
        let folder = try replayFixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let expected = try String(contentsOf: folder.appending(path: "blocks/2024-03-12.jsonl"), encoding: .utf8)
        #expect(BlockLogFile.parse(expected).blocks.count >= 2)
        #expect(AgentMain.replayFixture(at: folder) == 0)
        let run = try await runAgent(["--replay", folder.path])
        #expect(run.status == 0, "\(run.error)")

        var settings = TrackerSettings.defaults
        // Blocks of at most 15 minutes cut the fixture's 25 and 30 minute blocks.
        settings.blocks.maxBlock = 900
        #expect(try SampleFixture.replay(folder: folder, settings: settings) == ["2024-03-12"])

        // Expected files formed under another threshold.
        try expected.replacing("\"r\":\"locked\"", with: "\"r\":\"idle\"")
            .write(to: folder.appending(path: "blocks/2024-03-12.jsonl"), atomically: true, encoding: .utf8)
        #expect(AgentMain.replayFixture(at: folder) == 1)
        let differs = try await runAgent(["--replay", folder.path])
        #expect(differs.status == 1)
        #expect(differs.error.contains("differs: 2024-03-12"))
    }

    @Test("TRK-41 the --record output contains no home path, host name, or URL path of the live run")
    func recordAnonymizes() async throws {
        let record = try TemporaryFolder.make("record")
        defer { try? FileManager.default.removeItem(at: record) }
        let harness = try AgentHarness(recordFolder: record)
        harness.loadTerminalFixtures()
        harness.commands.set(
            ProcessTable.command,
            AgentHarness.fixture("ps/terminals.txt") + "  999     1 ??       S    /Users/alex/bin/alex-mbp-sync\n"
        )
        harness.wezterm()
        await harness.run(for: 60)
        harness.safari(BrowserTests.pullRequest, title: "Fix the parser by owner · Pull Request #123")
        await harness.run(for: 60)
        #expect(harness.samples.contains { $0.foreground?.location == BrowserTests.pullRequest })
        #expect(harness.samples.contains { $0.foreground?.documents == ["~/Documents/Papers/2026_Noise/notes.tex"] })

        let manager = FileManager.default
        let files = try #require(manager.enumerator(atPath: record.path)?.allObjects as? [String])
        #expect(files.contains("samples.jsonl"))
        #expect(files.contains("fixture.json"))
        #expect(files.contains { $0.hasPrefix("tmux/") })
        #expect(files.contains { $0.hasPrefix("applescript/") })
        var text = ""
        for file in files {
            var isFolder: ObjCBool = false
            if manager.fileExists(atPath: record.appending(path: file).path, isDirectory: &isFolder), !isFolder.boolValue {
                text += try String(contentsOf: record.appending(path: file), encoding: .utf8)
            }
        }
        #expect(text.contains("github.com"))
        for secret in [
            "/Users/alex",
            "alex",
            "alex-mbp",
            "Documents/Papers",
            "2026_Noise",
            "notes.tex",
            "owner/repo",
            "pull/123",
            "diff=split",
            AgentHarness.macName,
        ] {
            #expect(!text.contains(secret), "\(secret)")
        }
    }

    @Test("TRK-43 a copy of another app's database during which its WAL changed is made again and matches the files as they are afterwards")
    func snapshotRetriesAfterAWrite() throws {
        let folder = try TemporaryFolder.make("snapshot")
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "History.db")
        try Data("database".utf8).write(to: source)
        try Data("wal one".utf8).write(to: URL(filePath: source.path + "-wal"))
        let target = folder.appending(path: "copy/History.db")
        var copies = 0
        try SQLiteSnapshot.copy(path: source.path, to: target) { from, to in
            copies += 1
            try FileManager.default.copyItem(atPath: from, toPath: to)
            if copies == 1 {
                // The owner writes its WAL between the copies of the database and the WAL.
                try Data("wal two, longer".utf8).write(to: URL(filePath: source.path + "-wal"))
            }
        }
        #expect(copies == 4)
        #expect(try Data(contentsOf: URL(filePath: target.path + "-wal")) == Data("wal two, longer".utf8))
        #expect(try Data(contentsOf: target) == Data("database".utf8))
    }

    @Test("TRK-44 a second agent finds agent.lock taken and does not start")
    func secondInstanceIsRefused() throws {
        let folder = try TemporaryFolder.make("lock")
        defer { try? FileManager.default.removeItem(at: folder) }
        let lock = folder.appending(path: "agent.lock")
        #expect(InstanceLock.acquire(at: lock))
        // flock locks belong to an open file, so a second open in this
        // process stands for a second agent.
        #expect(!InstanceLock.acquire(at: lock))
    }

    /// Commands that hang until the live runner's deadline stops them.
    @MainActor
    struct HungCommands: CommandRunning {
        let runner = LiveCommandRunner(timeout: .milliseconds(200))

        func run(_: [String]) async -> String? {
            await runner.run(["/bin/sleep", "30"])
        }
    }

    @Test("TRK-45 a command still running at its deadline is stopped and answers nothing; the tick goes on")
    func hungCommandIsStopped() async throws {
        let folder = try TemporaryFolder.make("hung")
        defer { try? FileManager.default.removeItem(at: folder) }
        let pidFile = folder.appending(path: "pid").path
        let runner = LiveCommandRunner(timeout: .milliseconds(200))
        let clock = ContinuousClock()
        let start = clock.now
        #expect(await runner.run(["/bin/sh", "-c", "echo $$ > '\(pidFile)'; exec /bin/sleep 30"]) == nil)
        #expect(clock.now - start < .seconds(10))
        let pid = try #require(Int32(String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
        #expect(await runner.run(["/bin/echo", "ok"]) == "ok\n")

        // An agent whose every command hangs still takes its Sample.
        let harness = try AgentHarness()
        harness.textEdit()
        var environment = harness.agent.environment
        environment.commands = HungCommands()
        let agent = try Agent(environment: environment, configuration: harness.agent.configuration, store: harness.agent.store)
        try agent.start()
        let tick = clock.now
        agent.queue.requestTick()
        await agent.queue.drain()
        #expect(clock.now - tick < .seconds(10))
        #expect(harness.latest?.foreground?.app == "TextEdit")
        #expect(harness.latest?.time == harness.time(0))
    }

    @Test("TRK-46 with settings.toml replaced by an iCloud Drive placeholder, the agent and the readers keep the exclusions they had")
    func evictedSettingsKeepExclusions() async throws {
        let harness = try AgentHarness(settings: "[privacy]\nexclude_apps = [\"com.apple.mail\"]\n")
        let reader = FileActivityStore(folders: harness.folders, homeDirectory: AgentHarness.home)
        #expect(reader.exclusions.excludesApp("com.apple.mail"))
        let settings = harness.agent.choice.settingsURL
        try FileManager.default.removeItem(at: settings)
        try Data().write(to: settings.deletingLastPathComponent().appending(path: ".settings.toml.icloud"))
        harness.frontmost("com.apple.mail", name: "Mail", title: "Inbox")
        await harness.workThenLock(for: 720)
        #expect(harness.agent.settings.exclusions(homeDirectory: AgentHarness.home).excludesApp("com.apple.mail"))
        #expect(harness.liveSamples().allSatisfy { $0.foreground == nil })
        #expect(!harness.allOutput.contains("Inbox"))
        await reader.refresh()
        #expect(reader.exclusions.excludesApp("com.apple.mail"))
    }
}
