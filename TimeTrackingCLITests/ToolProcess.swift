// ToolProcess: runs a built tool as a subprocess (spec_architecture.md §3.1).

import Foundation

/// The result of running a tool.
struct ToolResult {
    var status: Int32
    var standardOutput: String
    var standardError: String
    var duration: Duration
}

/// Runs the tools built next to this test bundle.
enum ToolProcess {
    private final class Token {}

    /// The products folder that holds the test bundle and the tools.
    static var productsDirectory: URL {
        Bundle(for: Token.self).bundleURL.deletingLastPathComponent()
    }

    /// Runs `tool` with `arguments` and `environment` added to the inherited one.
    static func run(_ tool: String, _ arguments: [String] = [], environment: [String: String] = [:]) throws -> ToolResult {
        let process = Process()
        process.executableURL = productsDirectory.appending(path: tool)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        let clock = ContinuousClock()
        let start = clock.now
        try process.run()
        let outData = output.fileHandleForReading.readDataToEndOfFile()
        let errData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ToolResult(
            status: process.terminationStatus,
            standardOutput: String(decoding: outData, as: UTF8.self),
            standardError: String(decoding: errData, as: UTF8.self),
            duration: clock.now - start
        )
    }
}
