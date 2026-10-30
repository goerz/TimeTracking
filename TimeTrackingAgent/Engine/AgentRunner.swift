// AgentRunner: assembles the live agent and runs its tick loop
// (spec_activity_tracking.md §5).

import AppKit
import os
import TimeTrackingCore

/// The live agent: the engine over the real system, the socket, the
/// presence and file observers, and the 30-second loop.
@MainActor
final class AgentRunner {
    let engine: AgentEngine
    private let socket: SocketServer
    private let observer = PresenceObserver()
    private var fileStream: FileEventStream?
    private var loop: Task<Void, Never>?
    private var deviceLoop: Task<Void, Never>?
    private var schedule: TickSchedule
    private var watchedRoots: [String] = []

    init(engine: AgentEngine) {
        self.engine = engine
        self.schedule = TickSchedule(start: engine.environment.clock.now, interval: AgentEngine.tickInterval)
        self.socket = SocketServer(url: engine.configuration.socketURL) { [weak engine] line in
            guard let engine else {
                return TrackerReply.error("the tracker is stopping").line
            }
            return await engine.handle(line: line)
        }
    }

    /// The live agent of `identity`, or `nil` without a group container.
    static func live(identity: AppIdentity, clock: any Clock, recordFolder: URL?) -> AgentRunner? {
        guard let configuration = AgentConfiguration.live(identity: identity) else {
            return nil
        }
        let home = NSHomeDirectory()
        let tmuxBase = ProcessInfo.processInfo.environment["TMUX_TMPDIR"].map(\.self) ?? "/private/tmp"
        var environment = AgentEnvironment(
            clock: clock,
            timeZone: .current,
            homeDirectory: home,
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
        var recorder: Recorder?
        if let recordFolder {
            let names = Host.current().names + [Host.current().localizedName ?? "", ProcessInfo.processInfo.hostName]
            let created = Recorder(folder: recordFolder, homeDirectory: home, userName: NSUserName(), hostNames: names)
            environment = environment.recording(with: created)
            recorder = created
        }
        do {
            let engine = try AgentEngine(environment: environment, configuration: configuration)
            engine.recorder = recorder
            // CloudKit stops a process without the container entitlement (ad-hoc builds).
            if CloudKitAvailability.check(containerIdentifier: identity.cloudKitContainer) {
                engine.deviceEvents = CloudKitDeviceEventSource(containerIdentifier: identity.cloudKitContainer)
            }
            return AgentRunner(engine: engine)
        } catch {
            Logging.logger(category: "Agent").error("cannot start: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func start() {
        do {
            try socket.start()
        } catch {
            engine.logger.error("socket: \(error.localizedDescription, privacy: .public)")
        }
        observer.start(
            event: { [weak self] event in
                guard let self else {
                    return
                }
                engine.handle(event, at: engine.environment.clock.now)
                if !event.closesBlock {
                    Task { await self.engine.tick() }
                }
            },
            activation: { [weak self] in
                Task { await self?.engine.tick() }
            }
        )
        let stream = FileEventStream { [weak self] paths in
            guard let self else {
                return
            }
            let context = engine.resolveContext()
            for path in paths {
                engine.fileChanges.record(path: path, at: engine.environment.clock.now, context: context)
            }
        }
        fileStream = stream
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                await runDueTick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        // The device events, off the tick loop: CloudKit may take seconds.
        deviceLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let engine = self?.engine else {
                    return
                }
                await engine.syncDeviceEvents(now: engine.environment.clock.now)
                try? await Task.sleep(for: .seconds(AgentEngine.deviceFetchInterval))
            }
        }
    }

    /// Takes the regular tick if due and keeps the file stream on the current roots.
    private func runDueTick() async {
        let now = engine.environment.clock.now
        guard schedule.isDue(at: now) else {
            return
        }
        schedule.fired(at: now)
        await engine.tick()
        let context = engine.resolveContext()
        let roots = engine.settings.files.roots.map(context.expand)
        if roots != watchedRoots {
            watchedRoots = roots
            fileStream?.start(roots: roots)
        }
    }

    func stop() {
        loop?.cancel()
        deviceLoop?.cancel()
        observer.stop()
        fileStream?.stop()
        socket.stop()
        for closed in engine.blocker.flush() {
            engine.write(closed)
        }
    }
}
