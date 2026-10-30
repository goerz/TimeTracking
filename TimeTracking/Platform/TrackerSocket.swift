// TrackerSocket: rewrite commands to the agent over its Unix socket
// (spec_activity_tracking.md §7.3).

import Darwin
import Foundation
import os
import TimeTrackingCore

/// Sends one command line and returns the agent's answer (`ok` or
/// `error <reason>`).
protocol TrackerCommandSending: Sendable {
    func send(_ command: String) async -> TrackerCommandResult
}

/// The agent's answer; a rejection carries the sentence the user reads
/// (spec_design.md §12), the raw reply goes to the log.
nonisolated enum TrackerCommandResult: Equatable, Sendable {
    case accepted
    case rejected(String)

    /// The socket could not be opened or written.
    static let unreachable = rejected("The tracker could not be reached.")
    /// Nothing listens on the socket.
    static let notRunning = rejected("The tracker is not running.")

    /// The rejection for the agent's reason of an `error <reason>` reply.
    static func rejection(reason: String) -> Self {
        if reason.hasPrefix(TrackerReply.noBlockReason) {
            return .rejected("This activity is no longer in the logs.")
        }
        if reason == TrackerReply.stoppingReason {
            return .rejected("The tracker is restarting. Try again in a moment.")
        }
        Logging.logger(category: "Tracker").error("tracker reply: \(reason, privacy: .public)")
        return .rejected("The tracker could not change the logs.")
    }
}

/// Records commands (tests, UI testing).
final class RecordingTrackerCommands: TrackerCommandSending, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var commands: [String] {
        lock.withLock { storage }
    }

    func send(_ command: String) -> TrackerCommandResult {
        lock.withLock { storage.append(command) }
        return .accepted
    }
}

/// The agent's socket `tracker.sock`. Its full path exceeds `sun_path`, so it
/// connects through a short symbolic link in the temporary folder.
struct TrackerSocket: TrackerCommandSending {
    let url: URL

    func send(_ command: String) async -> TrackerCommandResult {
        let url = url
        return await Task.detached { Self.exchange(command, at: url) }.value
    }

    private nonisolated static func exchange(_ command: String, at url: URL) -> TrackerCommandResult {
        let link = URL(filePath: NSTemporaryDirectory()).appending(path: "tt-\(UUID().uuidString.prefix(8)).sock")
        guard (try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)) != nil else {
            return .unreachable
        }
        defer { try? FileManager.default.removeItem(at: link) }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return .unreachable
        }
        defer { close(descriptor) }
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let name = Array(link.path.utf8CString)
        guard name.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            return .unreachable
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            name.withUnsafeBytes { buffer.copyMemory(from: $0) }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                connect(descriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            return .notRunning
        }
        let bytes = Array((command + "\n").utf8)
        guard bytes.withUnsafeBytes({ write(descriptor, $0.baseAddress, $0.count) }) == bytes.count else {
            return .unreachable
        }
        var reply = [UInt8]()
        var byte: UInt8 = 0
        while read(descriptor, &byte, 1) == 1, byte != UInt8(ascii: "\n") {
            reply.append(byte)
        }
        let text = String(decoding: reply, as: UTF8.self)
        if text == "ok" {
            return .accepted
        }
        guard case let .error(reason) = TrackerReply(line: text) else {
            return .accepted
        }
        return .rejection(reason: reason)
    }
}
