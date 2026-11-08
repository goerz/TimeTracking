// AgentHarness: an agent over fakes, folders in a temporary directory, and
// a ManualClock at the fixture time (architecture.md §3.3: tests drive the
// tick, never sleep).

import Foundation
import TimeTrackingCore
@testable import TimeTrackingAgent

/// Finds the test bundle.
final class FixtureBundleToken {}

@MainActor
final class AgentHarness {
    static let home = "/Users/alex"
    static let zone = TimeZone(identifier: "America/New_York") ?? .gmt
    static let macID = "mac-uuid"
    static let macName = "MacBook"

    let root: URL
    let clock = ManualClock.fixture(in: AgentHarness.zone)
    /// The agent's clock: `clock`, moved forward on each read while its step is set.
    let stepping: SteppingClock
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
    private(set) var agent: Agent!

    /// An agent whose `settings.toml` holds `settings` (none: the defaults).
    init(settings: String? = nil, canWriteShared: Bool = true, recordFolder: URL? = nil, editorRPC: (any EditorRPC)? = nil) throws {
        self.root = try TemporaryFolder.make("agent-tests")
        self.stepping = SteppingClock(base: clock)
        let shared = root.appending(path: "iCloud/Activity", directoryHint: .isDirectory)
        let local = root.appending(path: "Group/Activity", directoryHint: .isDirectory)
        self.folders = ActivityFolders(shared: shared, local: local)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        if let settings {
            let folder = canWriteShared ? shared : local
            try settings.write(to: folder.appending(path: "settings.toml", directoryHint: .notDirectory), atomically: true, encoding: .utf8)
        }
        var configuration = AgentConfiguration(
            agentFolder: root.appending(path: "Group", directoryHint: .isDirectory),
            folders: folders,
            macName: Self.macName,
            macDeviceID: Self.macID,
            version: "1.0 (1)"
        )
        configuration.canWriteShared = { _ in canWriteShared }
        var environment = AgentEnvironment(
            clock: stepping,
            timeZone: Self.zone,
            homeDirectory: Self.home,
            localHostNames: ["alex-mbp.local"],
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
        environment.appName = { $0 == "com.apple.mail" ? "Mail" : $0 }
        var recorder: Recorder?
        if let recordFolder {
            let created = Recorder(
                folder: recordFolder,
                homeDirectory: Self.home,
                userName: "alex",
                hostNames: ["alex-mbp.local", "alex-mbp"],
                zone: Self.zone,
                macName: Self.macName
            )
            environment = environment.recording(with: created)
            recorder = created
        }
        self.agent = try Agent(environment: environment, configuration: configuration, store: SampleStore(url: nil))
        agent.recorder = recorder
        try agent.start()
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// A new agent over the same store, folders, and fakes, as when the agent starts again.
    func restart() throws {
        let recorder = agent.recorder
        agent = try Agent(environment: agent.environment, configuration: agent.configuration, store: agent.store)
        agent.recorder = recorder
        try agent.start()
    }

    // MARK: Driving

    /// Lets the queue run what is due at the current time: a due tick, queued steps, rebuild passes.
    func drain() async {
        await agent.queue.drain()
    }

    /// Runs the next `duration` seconds: the clock moves in 30-second
    /// steps, and the queue runs the tick due at each.
    func run(for duration: TimeInterval) async {
        let end = clock.now + duration
        while clock.now < end {
            await drain()
            clock.set(min(end, clock.now + Agent.tickInterval))
        }
        await drain()
    }

    func advance(_ seconds: TimeInterval) {
        clock.advance(by: seconds)
    }

    /// The fixture time plus `seconds`.
    func time(_ seconds: TimeInterval) -> Date {
        ManualClock.fixtureNow(in: Self.zone) + seconds
    }

    // MARK: Fixtures

    /// `Fixtures/Agent/` is a resource folder of the test bundle (its files
    /// land flat in the bundle, so their names are unique).
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

    /// The terminal fixtures: `ps`, one tmux server, its clients and panes,
    /// WezTerm, and a Claude Code session.
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

    var samples: [Sample] {
        (try? agent.store.samples(SampleSelection(range: DateInterval(start: .distantPast, end: .distantFuture)))) ?? []
    }

    /// The blocks of the date file of `day` (`YYYY-MM-DD`).
    func blocks(_ day: String) -> [ActivityBlock] {
        guard let date = TrackingDay(day), case let .text(text) = agent.choice.log.content(for: date) else {
            return []
        }
        return BlockLogFile.parse(text).blocks
    }

    var currentState: TrackerState? {
        (try? Data(contentsOf: folders.currentStateURL)).flatMap { try? TrackerState.parse($0) }
    }

    func health(_ id: SourceID) -> TrackerSourceHealth? {
        currentState?.health.sources.first { $0.id == id.rawValue }
    }
}
