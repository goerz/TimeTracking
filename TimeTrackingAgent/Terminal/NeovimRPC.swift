// NeovimRPC: asking a Neovim instance for its current file over msgpack-RPC
// (spec_activity_tracking.md §3.1, editor chain step 2).

import Foundation
import TimeTrackingCore

/// Asks an editor for the file in its current buffer.
protocol EditorRPC {
    /// The absolute path of the current buffer, or `nil` on silence, error,
    /// or an unnamed buffer within `timeout` seconds.
    func currentFile(socket: String, timeout: Double) async -> String?
}

/// Neovim's msgpack-RPC: `nvim_eval("expand('%:p')")` on its server socket.
struct NeovimRPCClient: EditorRPC {
    func currentFile(socket: String, timeout: Double) async -> String? {
        await Task.detached { Self.request(socket: socket, timeout: timeout) }.value
    }

    private nonisolated static func request(socket: String, timeout: Double) -> String? {
        guard let descriptor = try? UnixSocket.connect(to: URL(filePath: socket)) else {
            return nil
        }
        defer { close(descriptor) }
        UnixSocket.setTimeout(descriptor, seconds: timeout)
        let message = MessagePack.request(id: 1, method: "nvim_eval", arguments: ["expand('%:p')"])
        guard message.withUnsafeBytes({ write(descriptor, $0.baseAddress, $0.count) }) == message.count else {
            return nil
        }
        let deadline = ContinuousClock.now + .milliseconds(Int(timeout * 1000))
        var buffer: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        while ContinuousClock.now < deadline {
            let count = read(descriptor, &chunk, chunk.count)
            guard count > 0 else {
                return nil
            }
            buffer += chunk[..<count]
            if let reply = MessagePack.response(buffer, id: 1) {
                return reply.isEmpty ? nil : reply
            }
        }
        return nil
    }
}

/// The few msgpack forms the RPC exchange needs.
nonisolated enum MessagePack {
    /// `[0, id, method, [arguments...]]` with string arguments.
    static func request(id: UInt8, method: String, arguments: [String]) -> [UInt8] {
        var bytes: [UInt8] = [0x94, 0x00, id & 0x7F]
        bytes += string(method)
        bytes.append(0x90 | UInt8(min(arguments.count, 15)))
        for argument in arguments.prefix(15) {
            bytes += string(argument)
        }
        return bytes
    }

    /// The string result of `[1, id, nil, result]`, `""` for a nil or
    /// non-string result or an error, `nil` while incomplete.
    static func response(_ bytes: [UInt8], id: UInt8) -> String? {
        var reader = Reader(bytes: bytes)
        guard let header = reader.next(), header == 0x94 else {
            return reader.complete ? "" : nil
        }
        guard let kind = reader.next(), let messageID = reader.next() else {
            return nil
        }
        guard kind == 0x01, messageID == id else {
            return ""
        }
        guard let error = reader.peek() else {
            return nil
        }
        if error != 0xC0 {
            return ""
        }
        _ = reader.next()
        guard let value = reader.string() else {
            return reader.complete ? "" : nil
        }
        return value
    }

    static func string(_ text: String) -> [UInt8] {
        let utf8 = Array(text.utf8)
        switch utf8.count {
        case 0 ..< 32:
            return [0xA0 | UInt8(utf8.count)] + utf8
        case 32 ..< 256:
            return [0xD9, UInt8(utf8.count)] + utf8
        default:
            let count = UInt16(min(utf8.count, Int(UInt16.max)))
            return [0xDA, UInt8(count >> 8), UInt8(count & 0xFF)] + utf8.prefix(Int(count))
        }
    }

    private struct Reader {
        var bytes: [UInt8]
        var index = 0
        /// Whether the input ended cleanly (no partial value pending).
        var complete = true

        mutating func next() -> UInt8? {
            guard index < bytes.count else {
                complete = false
                return nil
            }
            defer { index += 1 }
            return bytes[index]
        }

        func peek() -> UInt8? {
            index < bytes.count ? bytes[index] : nil
        }

        /// A str value; `nil` when not a string or incomplete.
        mutating func string() -> String? {
            guard let marker = next() else {
                return nil
            }
            let length: Int
            switch marker {
            case 0xA0 ... 0xBF:
                length = Int(marker & 0x1F)
            case 0xD9:
                guard let size = next() else {
                    return nil
                }
                length = Int(size)
            case 0xDA:
                guard let high = next(), let low = next() else {
                    return nil
                }
                length = Int(high) << 8 | Int(low)
            case 0xDB:
                var size = 0
                for _ in 0 ..< 4 {
                    guard let byte = next() else {
                        return nil
                    }
                    size = size << 8 | Int(byte)
                }
                length = size
            default:
                return nil
            }
            guard index + length <= bytes.count else {
                complete = false
                return nil
            }
            defer { index += length }
            return String(decoding: bytes[index ..< index + length], as: UTF8.self)
        }
    }
}
