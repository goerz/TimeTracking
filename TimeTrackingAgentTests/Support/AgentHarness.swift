// AgentHarness: an engine over fakes, folders in a temporary directory, and
// a ManualClock at the fixture time (spec_architecture.md §3.3: tests drive
// the tick, never sleep).

import Foundation
import TimeTrackingCore
@testable import TimeTrackingAgent

/// Finds the test bundle.
final class FixtureBundleToken {}

@MainActor
final class AgentHarness {
    static let home = "/Users/alex"
    static let zone = TimeZone(identifier: "America/New_York") ?? .gmt
    static let device = "macbook"

    let root: URL
    let clock = ManualClock.fixture(in: AgentHarness.zone)
    let presence = FakePresence()
    let focus = FakeFocus()
    let commands = FakeCommands()
    let scripts = FakeScripts()
    let files = FakeFiles()
    let processes = FakeProcesses()
    let rpc = FakeRPC()
    let history = FakeHistory()
    let knowledge = FakeKnowledge()
    let folders: ActivityFolders
    // Set last in init, after the fakes it is built from.
    // swiftlint:disable:next implicitly_unwrapped_optional
    private(set) var engine: AgentEngine!
    var schedule: TickSchedule

    /// A harness whose `settings.toml` holds `settings` (the defaults when
    /// `nil`) with `min_block` set to `minBlock`: `"0s"` unless a test
    /// covers short blocks, so tests of other rules keep their short blocks;
    /// `nil` keeps the file's value or the default.
    init(
        settings: String? = nil,
        minBlock: String? = "0s",
        canWriteShared: Bool = true,
        recordFolder: URL? = nil,
        editorRPC: (any EditorRPC)? = nil
    ) throws {
        let settings = Self.settings(settings, minBlock: minBlock)
        self.root = try TemporaryFolder.make("agent-tests")
        let shared = root.appending(path: "iCloud/Activity", directoryHint: .isDirectory)
        let local = root.appending(path: "Group/Activity", directoryHint: .isDirectory)
        self.folders = ActivityFolders(shared: shared, local: local)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        self.schedule = TickSchedule(start: clock.now)
        if let settings {
            let folder = canWriteShared ? shared : local
            try settings.write(to: folder.appending(path: "settings.toml", directoryHint: .notDirectory), atomically: true, encoding: .utf8)
        }
        files.existing.insert(Self.home + "/Documents")
        var configuration = AgentConfiguration(
            agentFolder: root.appending(path: "Group", directoryHint: .isDirectory),
            folders: folders,
            device: Self.device,
            version: "1.0 (1)"
        )
        configuration.canWriteShared = { _ in canWriteShared }
        var environment = AgentEnvironment(
            clock: clock,
            timeZone: Self.zone,
            homeDirectory: Self.home,
            tmuxSocketFolder: "/private/tmp/tmux-501",
            neovimSocketFolder: root.appending(path: "nvim.alex").path,
            presence: presence,
            focus: focus,
            commands: commands,
            scripts: scripts,
            files: files,
            processes: processes,
            editorRPC: editorRPC ?? rpc,
            history: history,
            knowledge: knowledge
        )
        var recorder: Recorder?
        if let recordFolder {
            let created = Recorder(
                folder: recordFolder,
                homeDirectory: Self.home,
                userName: "alex",
                hostNames: ["alex-mbp.local", "alex-mbp"]
            )
            environment = environment.recording(with: created)
            recorder = created
        }
        self.engine = try AgentEngine(environment: environment, configuration: configuration, store: SampleStore(url: nil))
        engine.recorder = recorder
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// `settings` with `min_block = minBlock` in its `[blocks]` table.
    static func settings(_ settings: String?, minBlock: String?) -> String? {
        guard let minBlock else {
            return settings
        }
        let line = "min_block = \"\(minBlock)\""
        let text = settings ?? ""
        guard let range = text.range(of: "[blocks]\n") else {
            return text + "\n[blocks]\n\(line)\n"
        }
        return text.replacingCharacters(in: range, with: "[blocks]\n\(line)\n")
    }

    // MARK: Driving

    /// Runs the regular ticks of the next `duration` seconds, moving the clock.
    func run(for duration: TimeInterval) async {
        let end = clock.now.addingTimeInterval(duration)
        while schedule.next < end {
            clock.set(max(clock.now, schedule.next))
            schedule.fired(at: clock.now)
            await engine.tick()
        }
        clock.set(end)
        schedule = TickSchedule(start: end)
    }

    /// Moves the clock by `seconds`.
    func advance(_ seconds: TimeInterval) {
        clock.advance(by: seconds)
    }

    /// The fixture time plus `seconds`.
    func time(_ seconds: TimeInterval) -> Date {
        ManualClock.fixtureNow(in: Self.zone).addingTimeInterval(seconds)
    }

    // MARK: Fixtures

    /// `Fixtures/Agent/` is a resource folder of the test bundle (its files
    /// land flat in the bundle, so their names are unique). The source tree
    /// itself is not read: it may sit in a TCC-protected folder.
    static func fixtureURL(_ path: String) -> URL {
        let name = PathText.lastComponent(path)
        let ext = PathText.pathExtension(name)
        let bundle = Bundle(for: FixtureBundleToken.self)
        return bundle.url(forResource: String(name.dropLast(ext.count + 1)), withExtension: ext)
            ?? bundle.bundleURL.appending(path: "Contents/Resources/\(name)", directoryHint: .notDirectory)
    }

    static func fixture(_ path: String) -> String {
        (try? String(contentsOf: fixtureURL(path), encoding: .utf8)) ?? ""
    }

    /// A temporary folder with copies of the sample day and its expected blocks; returns the day's file.
    static func sampleDayCopy() throws -> URL {
        let folder = try TemporaryFolder.make("samples")
        for name in ["2024-03-14.jsonl", "2024-03-14.expected.jsonl"] {
            try FileManager.default.copyItem(at: fixtureURL(name), to: folder.appending(path: name, directoryHint: .notDirectory))
        }
        return folder.appending(path: "2024-03-14.jsonl", directoryHint: .notDirectory)
    }

    /// The terminal fixtures: `ps`, one tmux server, and its clients and panes.
    func loadTerminalFixtures() {
        commands.set(ProcessTable.command, Self.fixture("ps/terminals.txt"))
        let tmux = "/opt/homebrew/bin/tmux"
        files.existing.insert(tmux)
        files.folders["/private/tmp/tmux-501"] = ["default"]
        let socket = "/private/tmp/tmux-501/default"
        commands.set([tmux, "-S", socket, "list-clients", "-F", TmuxSnapshot.clientFormat], Self.fixture("tmux/list-clients.txt"))
        commands.set([tmux, "-S", socket, "list-panes", "-a", "-F", TmuxSnapshot.paneFormat], Self.fixture("tmux/list-panes.txt"))
        let wezterm = "/opt/homebrew/bin/wezterm"
        files.existing.insert(wezterm)
        commands.set([wezterm, "cli", "list-clients", "--format", "json"], Self.fixture("wezterm/list-clients.json"))
        commands.set([wezterm, "cli", "list", "--format", "json"], Self.fixture("wezterm/list.json"))
        let sessions = Self.home + "/.claude/sessions"
        files.folders[sessions] = ["712.json"]
        files.contents[sessions + "/712.json"] = Data(Self.fixture("claude/712.json").utf8)
        processes.alive = [712]
    }

    func frontmost(_ bundleID: String, name: String, pid: Int32 = 900, title: String = "", document: String? = nil, url: String? = nil) {
        focus.app = FrontApp(bundleID: bundleID, name: name, pid: pid)
        focus.window = WindowInfo(title: title, document: document, url: url)
    }

    func wezterm() {
        frontmost("com.github.wez.wezterm", name: "WezTerm", pid: 500, title: "tmux")
    }

    // MARK: Output

    func samples() -> [Sample] {
        ((try? engine.store.allRows()) ?? []).map(\.sample)
    }

    func sampleLines() -> [String] {
        (try? engine.store.lines()) ?? []
    }

    var blockLogText: String {
        (try? Replay.monthFilesText(in: engine.logs.blocksFolder)) ?? ""
    }

    var detailLogText: String {
        (try? Replay.monthFilesText(in: engine.logs.detailFolder)) ?? ""
    }

    var blocks: [ActivityBlock] {
        BlockLogFile(data: Data(blockLogText.utf8)).blocks
    }

    var details: [ActivityBlockDetail] {
        BlockLogFile(data: Data(detailLogText.utf8)).entries.compactMap(\.detail)
    }

    var currentStateText: String {
        (try? String(contentsOf: engine.logs.currentStateURL, encoding: .utf8)) ?? ""
    }

    var currentState: TrackerState? {
        try? TrackerState.parse(Data(currentStateText.utf8), timeZone: Self.zone)
    }

    /// Everything the agent wrote, for leak checks.
    var allOutput: String {
        sampleLines().joined(separator: "\n") + blockLogText + detailLogText + currentStateText
    }

    func health(_ id: String) -> TrackerSourceHealth? {
        engine.health.all.first { $0.id == id }
    }
}
