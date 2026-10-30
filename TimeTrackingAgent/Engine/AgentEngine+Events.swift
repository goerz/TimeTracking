// AgentEngine+Events: presence events and socket commands
// (spec_activity_tracking.md §2.6, §3.1, §3.4, §7.3).

import Foundation
import TimeTrackingCore

extension AgentEngine {
    /// The meta keys holding the time of the last pushed tmux and agent event.
    static let tmuxEventKey = "event.tmux"
    static let agentEventKey = "event.agent"

    /// A presence event at `time` (lock, sleep, display sleep, user switch,
    /// and their ends): records an event sample, closes the open block at
    /// the event time where §2.6 says so, and rewrites `current.json`.
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
