// AgentRunner: assembles the live agent and drives it with timers and
// system events (activity_tracking.md §2.4, §2.5, §5).

import AppKit
import os
import TimeTrackingCore

/// The live agent wired to the system: the socket, the presence observer,
/// and a timer that once a second lets the agent queue what is due.
@MainActor
final class AgentRunner {
    let agent: Agent
    private let socket: SocketServer
    private let observer = PresenceObserver()
    private var loop: Task<Void, Never>?

    init(agent: Agent) {
        self.agent = agent
        self.socket = SocketServer(url: agent.configuration.socketURL) { [weak agent] line in
            guard let agent else {
                return TrackerReply.error(TrackerReply.stoppingReason).line
            }
            return await agent.handle(line: line)
        }
    }

    /// The live agent of `identity` with `configuration`, or `nil` when it can't start.
    static func live(identity: AppIdentity, configuration: AgentConfiguration, clock: any Clock, recordFolder: URL?) -> AgentRunner? {
        let home = NSHomeDirectory()
        let tmuxBase = ProcessInfo.processInfo.environment["TMUX_TMPDIR"] ?? "/private/tmp"
        let hostNames = LocalHost.names
        var environment = AgentEnvironment(
            clock: clock,
            // Follows a time-zone change while the agent runs (after travel).
            timeZone: .autoupdatingCurrent,
            homeDirectory: home,
            localHostNames: hostNames,
            tmuxSocketFolder: "\(tmuxBase)/tmux-\(getuid())",
            neovimSocketFolder: FileManager.default.temporaryDirectory.path + "/nvim.\(NSUserName())",
            presence: LivePresenceProbe(),
            focus: LiveFocusProbe(),
            commands: LiveCommandRunner(),
            scripts: LiveAppleScripting(),
            files: LiveFileProbe(),
            processes: LiveProcessProbe(),
            editorRPC: NeovimRPCClient(),
            history: HistoryDatabases.live(home: home),
            knowledge: KnowledgeStoreReader(databasePath: KnowledgeStoreReader.defaultPath(home: home))
        )
        environment.appName = { bundleID in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { FileManager.default.displayName(atPath: $0.path) }
                .map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 } ?? bundleID
        }
        var recorder: Recorder?
        if let recordFolder {
            let created = Recorder(
                folder: recordFolder,
                homeDirectory: home,
                userName: NSUserName(),
                hostNames: hostNames.sorted(),
                zone: .current,
                macName: configuration.macName
            )
            environment = environment.recording(with: created)
            recorder = created
        }
        do {
            let agent = try Agent(environment: environment, configuration: configuration)
            agent.recorder = recorder
            // CloudKit stops a process without the container entitlement (ad-hoc builds).
            if CloudKitAvailability.check(containerIdentifier: identity.cloudKitContainer) {
                agent.deviceEvents = CloudKitDeviceEventSource(containerIdentifier: identity.cloudKitContainer)
            }
            try agent.start()
            return AgentRunner(agent: agent)
        } catch {
            Logging.logger(category: "Agent").error("cannot start: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func start() {
        do {
            try socket.start()
        } catch {
            agent.logger.error("socket: \(error.localizedDescription, privacy: .public)")
        }
        observer.start(
            event: { [weak self] event in
                guard let self else {
                    return
                }
                agent.taker.handle(event, at: agent.environment.clock.now)
                agent.queue.requestTick()
            },
            activation: { [weak self] in
                self?.agent.queue.requestTick()
            }
        )
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.agent.runDueWork()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// SIGTERM (logout, shutdown, unregistration): waiting requests answer
    /// that the tracker is stopping; returns once the running step is done.
    func stop() async {
        loop?.cancel()
        observer.stop()
        await agent.queue.stop()
        socket.stop()
    }
}
