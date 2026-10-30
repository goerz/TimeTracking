// TrackerSocketClient: sending one command to the agent's socket and reading
// the reply (spec_activity_tracking.md §7.3).

public import Foundation

/// Sends one command to the agent and reads its reply (the Mac app's
/// rewrite commands, tests).
public struct TrackerSocketClient: Sendable {
    public let socketURL: URL
    /// Seconds to wait for the reply; rewrites of long ranges take a while.
    public var timeout: Double

    public init(socketURL: URL, timeout: Double = 30) {
        self.socketURL = socketURL
        self.timeout = timeout
    }

    /// Sends `command` and returns the reply; `.error` when the agent is
    /// not running or does not answer.
    public func send(_ command: TrackerCommand) -> TrackerReply {
        send(line: command.line)
    }

    /// Sends a raw line (tests send malformed ones).
    public func send(line: String) -> TrackerReply {
        let descriptor: Int32
        do {
            descriptor = try UnixSocket.connect(to: socketURL)
        } catch {
            return .error("the tracker is not running")
        }
        defer { close(descriptor) }
        UnixSocket.setTimeout(descriptor, seconds: timeout)
        guard UnixSocket.write(line + "\n", to: descriptor) else {
            return .error("the tracker did not accept the command")
        }
        guard let reply = UnixSocket.readLine(from: descriptor) else {
            return .error("the tracker did not answer")
        }
        return TrackerReply(line: reply)
    }
}
