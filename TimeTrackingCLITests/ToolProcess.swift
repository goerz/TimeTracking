// ToolProcess: runs a built tool as a subprocess (spec_architecture.md §3.1).

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

    /// Starts `tool` with `arguments`, `environment` added to the inherited
    /// one and `removing` taken out; returns the running process and pipes.
    static func start(
        _ tool: String,
        _ arguments: [String],
        environment: [String: String] = [:],
        removing: [String] = []
    ) throws -> RunningTool {
        let process = Process()
        process.executableURL = productsDirectory.appending(path: tool)
        process.arguments = arguments
        var merged = ProcessInfo.processInfo.environment.merging(environment) { $1 }
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
