// UnixSocket: binding and connecting the agent's socket relative to its
// folder (spec_architecture.md §1.5, spec_activity_tracking.md §7.3).

public import Foundation
import Synchronization

/// Stream sockets at a path that may exceed the 104 bytes of `sun_path`.
///
/// The socket `tracker.sock` lives in the group container's support folder,
/// whose full path is too long for `sun_path`, so both ends change into the
/// folder and use the file name. Changing directory is process-wide; the
/// calls hold one lock and restore the previous directory.
public enum UnixSocket {
    /// Errors of the socket calls, with `errno`.
    public enum Failure: Error, Hashable {
        case socket(Int32)
        case folder(Int32)
        case nameTooLong
        case bind(Int32)
        case listen(Int32)
        case connect(Int32)
    }

    private static let directoryLock = Mutex(())

    /// Creates a listening socket at `url`, replacing a stale socket file.
    /// Returns the descriptor; the caller closes it.
    public static func listen(at url: URL, backlog: Int32 = 16) throws(Failure) -> Int32 {
        let descriptor = try makeSocket()
        do throws(Failure) {
            try inFolder(of: url) { name throws(Failure) in
                unlink(name)
                var address = try address(name)
                let result = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                        bind(descriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                guard result == 0 else {
                    throw .bind(errno)
                }
            }
            guard Darwin.listen(descriptor, backlog) == 0 else {
                throw Failure.listen(errno)
            }
        } catch {
            close(descriptor)
            throw error
        }
        return descriptor
    }

    /// Connects to the socket at `url`. Returns the descriptor; the caller closes it.
    public static func connect(to url: URL) throws(Failure) -> Int32 {
        let descriptor = try makeSocket()
        do throws(Failure) {
            try inFolder(of: url) { name throws(Failure) in
                var address = try address(name)
                let result = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                        Darwin.connect(descriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                guard result == 0 else {
                    throw .connect(errno)
                }
            }
        } catch {
            close(descriptor)
            throw error
        }
        return descriptor
    }

    /// Sets the receive and send timeouts of `descriptor`.
    public static func setTimeout(_ descriptor: Int32, seconds: Double) {
        var value = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - seconds.rounded(.down)) * 1_000_000))
        let size = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &value, size)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &value, size)
    }

    /// Writes all of `text`; false on failure.
    public static func write(_ text: String, to descriptor: Int32) -> Bool {
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            guard written > 0 else {
                return false
            }
            offset += written
        }
        return true
    }

    /// Reads up to the first newline (excluded) or the end of the stream,
    /// at most `limit` bytes; `nil` if nothing arrived.
    public static func readLine(from descriptor: Int32, limit: Int = 65_536) -> String? {
        var bytes: [UInt8] = []
        var byte: UInt8 = 0
        while bytes.count < limit {
            let count = read(descriptor, &byte, 1)
            guard count == 1 else {
                break
            }
            if byte == UInt8(ascii: "\n") {
                return String(decoding: bytes, as: UTF8.self)
            }
            bytes.append(byte)
        }
        return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
    }

    // MARK: Helpers

    private static func makeSocket() throws(Failure) -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw .socket(errno)
        }
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        return descriptor
    }

    private static func address(_ name: String) throws(Failure) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(name.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw .nameTooLong
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            bytes.withUnsafeBytes { buffer.copyMemory(from: $0) }
        }
        return address
    }

    private static func inFolder(of url: URL, _ body: (String) throws(Failure) -> Void) throws(Failure) {
        try directoryLock.withLock { _ throws(Failure) in
            let previous = FileManager.default.currentDirectoryPath
            guard chdir(url.deletingLastPathComponent().path) == 0 else {
                throw .folder(errno)
            }
            defer { chdir(previous) }
            try body(url.lastPathComponent)
        }
    }
}
