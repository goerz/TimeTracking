// Fakes for the agent's system seams (architecture.md §3.1: resolvers
// against fixtures, no TCC grant needed).

// Fakes conform to the agent seams: async and throwing signatures, optional answers.
// swiftlint:disable discouraged_optional_collection discouraged_optional_boolean async_without_await unneeded_throws_rethrows

import Foundation
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
final class FakePresence: PresenceProbe {
    var reading = PresenceReading()

    func read() -> PresenceReading {
        reading
    }
}

@MainActor
final class FakeFocus: FocusProbe {
    var isTrusted = true
    var app: FrontApp? = FrontApp(bundleID: "com.apple.TextEdit", name: "TextEdit", pid: 900)
    var window: WindowInfo? = WindowInfo(title: "Untitled")

    func frontmostApp() -> FrontApp? {
        app
    }

    func focusedWindow(of _: FrontApp) -> WindowInfo? {
        window
    }
}

/// Answers commands by their full command line.
@MainActor
final class FakeCommands: CommandRunning {
    var outputs: [String: String] = [:]
    private(set) var calls: [[String]] = []

    /// Awaited by every run before it answers (a test holds a tick there).
    var beforeAnswer: (@MainActor () async -> Void)?

    func run(_ arguments: [String]) async -> String? {
        calls.append(arguments)
        await beforeAnswer?()
        return outputs[arguments.joined(separator: " ")]
    }

    func set(_ arguments: [String], _ output: String) {
        outputs[arguments.joined(separator: " ")] = output
    }
}

/// Answers AppleScripts by the bundle identifier they address.
@MainActor
final class FakeScripts: AppleScripting {
    var results: [String: ScriptResult] = [:]
    private(set) var calls: [String] = []

    func run(_ source: String) -> ScriptResult {
        calls.append(source)
        for (bundleID, result) in results where source.contains("\"\(bundleID)\"") {
            return result
        }
        return .failed
    }
}

@MainActor
final class FakeFiles: FileProbe {
    var existing: Set<String> = []
    var contents: [String: Data] = [:]
    var folders: [String: [String]] = [:]

    func exists(_ path: String) -> Bool {
        existing.contains(path) || contents[path] != nil || folders[path] != nil
    }

    func contents(_ path: String) -> Data? {
        contents[path]
    }

    func list(_ path: String) -> [String]? {
        folders[path]
    }

    var modified: [String: Date] = [:]

    func modificationDate(_ path: String) -> Date? {
        modified[path]
    }
}

@MainActor
final class FakeProcesses: ProcessProbe {
    var cwd: [Int32: String] = [:]
    var arguments: [Int32: [String]] = [:]
    var ttyInput: [String: Date] = [:]
    var alive: Set<Int32> = []

    func workingDirectory(of pid: Int32) -> String? {
        cwd[pid]
    }

    func arguments(of pid: Int32) -> [String]? {
        arguments[pid]
    }

    func lastInput(onTTY tty: String) -> Date? {
        ttyInput[ProcessTable.shortTTY(tty)]
    }

    func isAlive(_ pid: Int32) -> Bool {
        alive.contains(pid)
    }
}

@MainActor
final class FakeRPC: EditorRPC {
    var answer: String?
    private(set) var calls = 0

    func currentFile(socket _: String, timeout _: Double) async -> String? {
        calls += 1
        return answer
    }
}

@MainActor
final class FakeHistory: BrowserHistory {
    var canReadSafari = true
    /// Safari visits with their origin.
    var safari: [(visit: HistoryVisit, origin: Int)] = []
    var chromium: [HistoryVisit] = []
    var tabs: [CloudTabDevice]?
    private(set) var cloudTabsReads = 0

    func safariVisits(from: Date, to: Date, origin: Int) -> [HistoryVisit]? {
        guard canReadSafari else {
            return nil
        }
        return safari.filter { $0.origin == origin && $0.visit.time >= from && $0.visit.time <= to }.map(\.visit)
    }

    func hasSafariVisit(url: String, since: Date) -> Bool? {
        guard canReadSafari else {
            return nil
        }
        return safari.contains { $0.origin == 0 && $0.visit.url == url && $0.visit.time >= since }
    }

    func chromiumVisits(from: Date, to: Date) -> [HistoryVisit] {
        chromium.filter { $0.time >= from && $0.time <= to }
    }

    func cloudTabs() -> [CloudTabDevice]? {
        cloudTabsReads += 1
        return tabs
    }
}

@MainActor
final class FakeKnowledge: KnowledgeSource {
    var result = KnowledgeRead.unavailable("Full Disk Access is off; macOS app usage history can't be read")

    func read(from _: Date, to _: Date) -> KnowledgeRead {
        result
    }
}

actor FakeDeviceEvents: DeviceEventSource {
    private(set) var purges: [Date] = []

    nonisolated func events(since _: ChangeToken?) async throws -> ([DeviceEvent], ChangeToken) {
        ([], ChangeToken(data: Data()))
    }

    func purge(before date: Date) async throws {
        purges.append(date)
    }

    nonisolated var changes: AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}

// swiftlint:enable discouraged_optional_collection discouraged_optional_boolean async_without_await unneeded_throws_rethrows
