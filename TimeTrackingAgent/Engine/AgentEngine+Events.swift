// AgentEngine+Events: presence events and socket commands
// (activity_tracking.md §2.6, §3.1, §3.4, §7.3).

import Foundation
import TimeTrackingCore

extension AgentEngine {
    /// The meta keys holding the time of the last pushed tmux and agent event.
    static let tmuxEventKey = "event.tmux"
    static let agentEventKey = "event.agent"

    /// A presence event at `time` (lock, sleep, display sleep, user switch,
    /// and their ends): records an event sample, closes the open block at
    /// the event time where §2.6 says so, and rewrites `current.json`.
    /// How far before its delivery a file event's modification time may lie.
    static let fileEventWindow: TimeInterval = 60

    /// Records modified files from FSEvents. FSEvents reports no time, and
    /// delivers with a delay; the file's modification time, when it lies
    /// within the last minute, places the change in the right block.
    func recordFileEvents(_ paths: [String]) {
        let now = environment.clock.now
        let context = resolveContext()
        for path in paths {
            let modified = environment.files.modificationDate(path)
            let time = modified.flatMap { $0 <= now && now.timeIntervalSince($0) <= Self.fileEventWindow ? $0 : nil } ?? now
            fileChanges.record(path: path, at: time, context: context)
        }
    }

    func handle(_ event: PresenceEvent, at time: Date) {
        if presence.apply(event, at: time) {
            transitions.append(ActivityPresenceTransition(time: presence.since, state: presence.state))
        }
        process(Sample(time: time, state: presence.state, event: event))
    }

    /// Handles one socket line and returns the reply line. Events advance
    /// the tick; rewrite commands rewrite the logs; anything else is an
    /// error and changes nothing.
    func handle(line: String) async -> String {
        let command: TrackerCommand
        do {
            command = try TrackerCommand.parse(line)
        } catch {
            return TrackerReply.error(Self.describe(error)).line
        }
        return await handle(command).line
    }

    func handle(_ command: TrackerCommand) async -> TrackerReply {
        let now = environment.clock.now
        switch command {
        case .tick:
            await tick()
            return .success
        case .tmuxEvent:
            try? store.setDate(now, for: Self.tmuxEventKey)
            await tick()
            return .success
        case .agentEvent:
            try? store.setDate(now, for: Self.agentEventKey)
            await tick()
            return .success
        case .deleteBlock, .forgetDay, .reapplyExclusions:
            return rewrite(command)
        }
    }

    private static func describe(_ error: TrackerCommand.ParseError) -> String {
        switch error {
        case .empty:
            "empty command"
        case let .unknownCommand(name):
            "unknown command \(name)"
        case let .wrongArguments(name):
            "wrong arguments for \(name)"
        case .unbalancedQuote:
            "unbalanced quote"
        }
    }
}
