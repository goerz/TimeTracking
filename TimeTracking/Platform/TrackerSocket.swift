// TrackerSocket: rewrite commands to the agent over its Unix socket
// (spec_activity_tracking.md §7.3).

import Darwin
import Foundation

/// Sends one command line and returns the agent's answer (`ok` or
/// `error <reason>`).
protocol TrackerCommandSending: Sendable {
    func send(_ command: String) async -> TrackerCommandResult
}

/// The agent's answer.
enum TrackerCommandResult: Equatable, Sendable {
    case accepted
    case rejected(String)
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
            return .rejected("The tracker's folder does not exist.")
        }
        defer { try? FileManager.default.removeItem(at: link) }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return .rejected("No socket.")
        }
        defer { close(descriptor) }
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let name = Array(link.path.utf8CString)
        guard name.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            return .rejected("The socket path is too long.")
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
            return .rejected("The tracker is not running.")
        }
        let bytes = Array((command + "\n").utf8)
        guard bytes.withUnsafeBytes({ write(descriptor, $0.baseAddress, $0.count) }) == bytes.count else {
            return .rejected("The tracker did not accept the command.")
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
        return .rejected(text.hasPrefix("error ") ? String(text.dropFirst(6)) : text)
    }
}
