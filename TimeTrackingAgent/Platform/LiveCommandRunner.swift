// LiveCommandRunner and the other live probes: commands, AppleScript,
// files, and process facts of the real system (spec_activity_tracking.md
// §3.1, §3.3).

// nil means "cannot read", which differs from an empty answer.
// swiftlint:disable discouraged_optional_collection

import AppKit
import Darwin
import Foundation

/// Runs commands with `Process`, off the main actor.
struct LiveCommandRunner: CommandRunning {
    func run(_ arguments: [String]) async -> String? {
        guard let executable = arguments.first, FileManager.default.isExecutableFile(atPath: executable) else {
            return nil
        }
        return await Task.detached { Self.execute(arguments) }.value
    }

    private nonisolated static func execute(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Runs AppleScript with `NSAppleScript` on the main actor, compiled once per source.
final class LiveAppleScripting: AppleScripting {
    private var compiled: [String: NSAppleScript] = [:]

    func run(_ source: String) -> ScriptResult {
        guard let script = compiled[source] ?? NSAppleScript(source: source) else {
            return .failed
        }
        compiled[source] = script
        // NSAppleScript reports errors in an NSDictionary.
        // swiftlint:disable:next legacy_objc_type
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            // -1743: the user has not allowed Automation for the target.
            return error[NSAppleScript.errorNumber] as? Int == -1743 ? .denied : .failed
        }
        return .value(result.stringValue ?? "")
    }
}

/// File reads through `FileManager`.
struct LiveFileProbe: FileProbe {
    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func contents(_ path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }

    func list(_ path: String) -> [String]? {
        try? FileManager.default.contentsOfDirectory(atPath: path)
    }

    func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}

/// Process facts through `libproc` and `sysctl`.
struct LiveProcessProbe: ProcessProbe {
    func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else {
            return nil
        }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    func arguments(of pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        let count = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        // Skip the executable path and its padding.
        while index < size, buffer[index] != 0 {
            index += 1
        }
        while index < size, buffer[index] == 0 {
            index += 1
        }
        var result: [String] = []
        while index < size, result.count < Int(count) {
            let start = index
            while index < size, buffer[index] != 0 {
                index += 1
            }
            result.append(String(decoding: buffer[start ..< index], as: UTF8.self))
            index += 1
        }
        return result
    }

    func lastInput(onTTY tty: String) -> Date? {
        var info = stat()
        guard stat("/dev/" + ProcessTable.shortTTY(tty), &info) == 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(info.st_atimespec.tv_sec))
    }

    func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}

// swiftlint:enable discouraged_optional_collection
