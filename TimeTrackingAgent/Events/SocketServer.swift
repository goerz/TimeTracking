// SocketServer: the agent's Unix socket `tracker.sock` (spec_activity_tracking.md
// §3.1, §7.3; spec_architecture.md §1.5).

import Foundation
import os
import TimeTrackingCore

/// Accepts connections on `tracker.sock`, reads one line from each, hands
/// it to `handler` on the main actor, and writes the reply line back.
///
/// The socket is bound relative to its folder (the full path exceeds
/// `sun_path`). Accepting runs on `FileHandle`'s readability handler.
final class SocketServer {
    typealias Handler = @MainActor @Sendable (String) async -> String

    let url: URL
    private let handler: Handler
    private var descriptor: Int32 = -1
    private var handle: FileHandle?

    init(url: URL, handler: @escaping Handler) {
        self.url = url
        self.handler = handler
    }

    /// Binds and starts accepting.
    func start() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let listening = try UnixSocket.listen(at: url)
        descriptor = listening
        let handler = handler
        let fileHandle = FileHandle(fileDescriptor: listening, closeOnDealloc: false)
        fileHandle.readabilityHandler = { _ in
            let client = accept(listening, nil, nil)
            guard client >= 0 else {
                return
            }
            UnixSocket.setTimeout(client, seconds: 5)
            let line = UnixSocket.readLine(from: client) ?? ""
            Task { @MainActor in
                let reply = await handler(line)
                _ = UnixSocket.write(reply + "\n", to: client)
                close(client)
            }
        }
        handle = fileHandle
    }

    /// Stops accepting and removes the socket file.
    func stop() {
        handle?.readabilityHandler = nil
        handle = nil
        if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }
        unlink(url.path)
    }
}
