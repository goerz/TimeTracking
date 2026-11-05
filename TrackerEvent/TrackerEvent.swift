// TrackerEvent: `tracker-event`, which writes one line to the tracker
// agent's socket, waits for its answer, and exits (activity_tracking.md
// §3.1, §7.3).
//
// Links only Foundation. The socket is
// `<Mac group container>/Library/Application Support/TimeTracking/tracker.sock`;
// `TIMETRACKING_SOCKET` overrides the path (tests). The full path exceeds
// the 104-byte `sun_path` limit, so the tool connects relative to the
// socket's folder.
//
//   tracker-event tmux after-select-pane        # from a tmux hook (the hook's name)
//   tracker-event agent Stop                    # from a Claude Code hook
//   tracker-event forget-day 2024-03-14         # a rewrite command
//
// Arguments become one line, words with spaces or quotes in double quotes.
// The agent answers `ok` (exit 0) or `error <reason>` (printed, exit 1).

import Foundation

@main
enum TrackerEvent {
    /// How long to wait for the answer; rewrite commands over long ranges take a while.
    static let replyTimeout = 120

    static func main() {
        let words = Array(CommandLine.arguments.dropFirst())
        guard !words.isEmpty else {
            fail("usage: tracker-event <event> [<argument>...]", status: 64)
        }
        guard let socket = socketURL() else {
            fail("tracker-event: no App Group in the Info.plist", status: 78)
        }
        guard let descriptor = connect(to: socket) else {
            fail("tracker-event: the tracker is not running (\(socket.path))", status: 69)
        }
        defer { close(descriptor) }
        guard write(line(words) + "\n", to: descriptor) else {
            fail("tracker-event: the tracker did not accept the event", status: 74)
        }
        let reply = readLine(from: descriptor) ?? ""
        if reply == "ok" {
            exit(0)
        }
        fail(reply.isEmpty ? "tracker-event: the tracker did not answer" : "tracker-event: \(reply)", status: 1)
    }

    /// The words as one line, quoting words that contain spaces, quotes, or backslashes.
    static func line(_ words: [String]) -> String {
        words.map { word in
            guard word.isEmpty || word.contains(where: { $0 == " " || $0 == "\"" || $0 == "\\" || $0 == "\t" }) else {
                return word
            }
            return "\"" + word.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }.joined(separator: " ")
    }

    private static func socketURL() -> URL? {
        if let path = ProcessInfo.processInfo.environment["TIMETRACKING_SOCKET"], !path.isEmpty {
            return URL(filePath: path)
        }
        guard let group = Bundle.main.infoDictionary?["TTAppGroup"] as? String, !group.isEmpty else {
            return nil
        }
        return URL(filePath: NSHomeDirectory())
            .appending(path: "Library/Group Containers/\(group)/Library/Application Support/TimeTracking/tracker.sock")
    }

    /// Connects to the socket; `nil` if nothing listens.
    private static func connect(to socket: URL) -> Int32? {
        guard chdir(socket.deletingLastPathComponent().path) == 0 else {
            return nil
        }
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return nil
        }
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: replyTimeout, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let name = Array(socket.lastPathComponent.utf8CString)
        guard name.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(descriptor)
            return nil
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            name.withUnsafeBytes { buffer.copyMemory(from: $0) }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                Darwin.connect(descriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    private static func write(_ text: String, to descriptor: Int32) -> Bool {
        let bytes = Array(text.utf8)
        return bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) } == bytes.count
    }

    /// The reply up to the newline, or `nil` if none arrived in time.
    private static func readLine(from descriptor: Int32) -> String? {
        var bytes: [UInt8] = []
        var byte: UInt8 = 0
        while read(descriptor, &byte, 1) == 1 {
            if byte == UInt8(ascii: "\n") {
                break
            }
            bytes.append(byte)
        }
        return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
    }

    private static func fail(_ message: String, status: Int32) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(status)
    }
}
