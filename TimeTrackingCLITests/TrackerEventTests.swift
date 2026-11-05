// tracker-event against a stand-in for the agent's socket
// (activity_tracking.md §3.1, §7.3).

import Darwin
import Foundation
import Testing

struct TrackerEventTests {
    /// A one-connection socket server that records the line and answers `reply`.
    private final class OneShotServer: Sendable {
        let path: String
        private let descriptor: Int32

        init(folder: URL) throws {
            self.path = folder.appending(path: "tracker.sock").path
            self.descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let name = Array("tracker.sock".utf8CString)
            withUnsafeMutableBytes(of: &address.sun_path) { buffer in name.withUnsafeBytes { buffer.copyMemory(from: $0) } }
            let previous = FileManager.default.currentDirectoryPath
            chdir(folder.path)
            defer { chdir(previous) }
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer
                    .withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard bound == 0, listen(descriptor, 1) == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
        }

        /// Accepts one connection, reads its line, writes `reply`, and returns the line.
        func serve(reply: String) -> String {
            defer { close(descriptor) }
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else {
                return ""
            }
            defer { close(client) }
            var bytes: [UInt8] = []
            var byte: UInt8 = 0
            while read(client, &byte, 1) == 1, byte != UInt8(ascii: "\n") {
                bytes.append(byte)
            }
            let answer = Array((reply + "\n").utf8)
            _ = answer.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    private func exchange(_ arguments: [String], reply: String) async throws -> (line: String, result: ToolResult) {
        let folder = try TemporaryFolder("tracker-event")
        let server = try OneShotServer(folder: folder.url)
        let line = Task.detached { server.serve(reply: reply) }
        let result = try ToolProcess.run("tracker-event", arguments, environment: ["TIMETRACKING_SOCKET": server.path])
        return await (line.value, result)
    }

    @Test("TRK-21 tracker-event writes its arguments as one line and exits 0 on ok")
    func sendsOneLine() async throws {
        let (line, result) = try await exchange(["tmux", "after-select-pane"], reply: "ok")
        #expect(line == "tmux after-select-pane")
        #expect(result.status == 0)
        #expect(result.standardError.isEmpty)
    }

    @Test("TRK-21 tracker-event quotes words with spaces and reports an error reply with exit 1")
    func reportsErrors() async throws {
        let (line, result) = try await exchange(["tmux", "client-session-changed", "Alex's session"], reply: "error no block")
        #expect(line == #"tmux client-session-changed "Alex's session""#)
        #expect(result.status == 1)
        #expect(result.standardError.contains("error no block"))
    }
}
