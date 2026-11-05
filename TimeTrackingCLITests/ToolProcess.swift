// ToolProcess: runs a built tool as a subprocess (architecture.md §3.1).

import Darwin
import Foundation

/// The result of running a tool.
struct ToolResult {
    var status: Int32
    var standardOutput: String
    var standardError: String
    var duration: Duration

    /// stdout parsed as a JSON object.
    var json: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(standardOutput.utf8))) as? [String: Any] ?? [:]
    }

    /// stderr parsed as a JSON object.
    var errorJSON: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(standardError.utf8))) as? [String: Any] ?? [:]
    }

    /// stdout split into lines, without the final empty one.
    var lines: [String] {
        standardOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
    }
}

/// A started tool with its output pipes.
struct RunningTool {
    var process: Process
    var output: Pipe
    var error: Pipe
    var start: ContinuousClock.Instant
}

/// Runs the tools built next to this test bundle.
enum ToolProcess {
    private final class Token {}

    /// The products folder that holds the test bundle and the tools.
    static var productsDirectory: URL {
        Bundle(for: Token.self).bundleURL.deletingLastPathComponent()
    }

    /// The app id of this build: the test bundle's id without `.cli-tests`.
    static var appID: String {
        let identifier = Bundle(for: Token.self).bundleIdentifier ?? ""
        return identifier.hasSuffix(".cli-tests") ? String(identifier.dropLast(".cli-tests".count)) : identifier
    }

    /// The `HOME` of every tool run: an empty folder of this test process,
    /// so a tool never reads or writes the user's home.
    static let home: URL = {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cli-home-\(getpid())", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    /// Starts `tool` with `arguments`, `environment` added to the inherited
    /// one (with `HOME` set to `home`) and `removing` taken out; returns the
    /// running process and pipes.
    static func start(
        _ tool: String,
        _ arguments: [String],
        environment: [String: String] = [:],
        removing: [String] = []
    ) throws -> RunningTool {
        let process = Process()
        process.executableURL = productsDirectory.appending(path: tool)
        process.arguments = arguments
        var merged = ProcessInfo.processInfo.environment.merging(["HOME": home.path]) { $1 }.merging(environment) { $1 }
        for key in removing {
            merged[key] = nil
        }
        process.environment = merged
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice
        let start = ContinuousClock.now
        try process.run()
        return RunningTool(process: process, output: output, error: error, start: start)
    }

    /// Waits for a process from `start` and collects its output.
    static func finish(_ tool: RunningTool) -> ToolResult {
        let outData = tool.output.fileHandleForReading.readDataToEndOfFile()
        let errData = tool.error.fileHandleForReading.readDataToEndOfFile()
        tool.process.waitUntilExit()
        return ToolResult(
            status: tool.process.terminationStatus,
            standardOutput: String(decoding: outData, as: UTF8.self),
            standardError: String(decoding: errData, as: UTF8.self),
            duration: ContinuousClock.now - tool.start
        )
    }

    /// Waits until the running `tool` has `file` open, or it exits, or 30
    /// seconds pass (a generous bound; this returns within milliseconds on
    /// success). Polls the process's descriptors every millisecond.
    static func waitUntilOpen(_ tool: RunningTool, file: URL) -> Bool {
        // realpath, not resolvingSymlinksInPath, which strips /private.
        var path = file.path
        if let resolved = realpath(file.path, nil) {
            path = String(cString: resolved)
            free(resolved)
        }
        let deadline = ContinuousClock.now + .seconds(30)
        while tool.process.isRunning, ContinuousClock.now < deadline {
            if openFiles(of: tool.process.processIdentifier).contains(where: { $0.hasPrefix(path) }) {
                return true
            }
            usleep(1000)
        }
        return false
    }

    /// Waits until `file` exists, or `tool` exits, or 30 seconds pass.
    static func waitUntilExists(_ file: URL, while tool: RunningTool) -> Bool {
        let deadline = ContinuousClock.now + .seconds(30)
        while tool.process.isRunning, ContinuousClock.now < deadline {
            if FileManager.default.fileExists(atPath: file.path) {
                return true
            }
            usleep(1000)
        }
        return FileManager.default.fileExists(atPath: file.path)
    }

    /// The paths of the vnodes process `pid` has open.
    static func openFiles(of pid: pid_t) -> [String] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else {
            return []
        }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride)
        let filled = descriptors.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, size) }
        return descriptors.prefix(Int(max(filled, 0)) / stride).compactMap { descriptor in
            guard descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) else {
                return nil
            }
            var info = vnode_fdinfowithpath()
            let length = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, length) == length else {
                return nil
            }
            return withUnsafeBytes(of: info.pvip.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        }
    }

    /// Runs `tool` with `arguments` and `environment` added to the inherited one.
    static func run(
        _ tool: String,
        _ arguments: [String] = [],
        environment: [String: String] = [:],
        removing: [String] = []
    ) throws -> ToolResult {
        try finish(start(tool, arguments, environment: environment, removing: removing))
    }
}
