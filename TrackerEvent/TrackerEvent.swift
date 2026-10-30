// TrackerEvent: `tracker-event`, which writes one line to the tracker
// agent's socket and exits (spec_activity_tracking.md §3.1, §7.3).
//
// Links only Foundation. The socket is
// `<Mac group container>/Library/Application Support/TimeTracking/tracker.sock`;
// `TIMETRACKING_SOCKET` overrides the path (tests). The full path exceeds
// the 104-byte `sun_path` limit, so the tool connects relative to the
// socket's folder.

import Foundation

@main
enum TrackerEvent {
    static func main() {
        let words = Array(CommandLine.arguments.dropFirst())
        guard !words.isEmpty else {
            fail("usage: tracker-event <event> [<argument>...]", status: 64)
        }
        guard let socket = socketURL() else {
            fail("tracker-event: no App Group in the Info.plist", status: 78)
        }
        let line = words.joined(separator: " ") + "\n"
        guard send(line, to: socket) else {
            fail("tracker-event: the tracker is not running (\(socket.path))", status: 69)
        }
        exit(0)
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

    /// Connects to the socket and writes `line`; false if nothing listens.
    private static func send(_ line: String, to socket: URL) -> Bool {
        guard chdir(socket.deletingLastPathComponent().path) == 0 else {
            return false
        }
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return false
        }
        defer { close(descriptor) }
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let name = Array(socket.lastPathComponent.utf8CString)
        guard name.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            return false
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
            return false
        }
        let bytes = Array(line.utf8)
        return bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) } == bytes.count
    }

    private static func fail(_ message: String, status: Int32) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(status)
    }
}
