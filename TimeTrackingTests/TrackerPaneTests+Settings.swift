// The Tracker pane's settings file and the tmux and coding agent
// snippets (activity_tracking.md §7.4).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

extension TrackerPaneTests {
    @Test("TRK-50 the pane writes settings.toml only to create the default file and to add a drafted exclusion, keeping every other byte")
    func settingsFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TrackerPaneTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "settings.toml")
        let model = TrackerSettingsModel(settingsURL: url)
        #expect(model.entries(.excludeDomains).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        // Opening the file creates the commented defaults.
        #expect(model.ensureFile())
        #expect(try String(contentsOf: url, encoding: .utf8) == TrackerSettings.defaultFileContents)
        // A hand edit is never overwritten.
        let handEdited = TrackerSettings.defaultFileContents + "\n# My own note\n"
        try Data(handEdited.utf8).write(to: url)
        #expect(model.ensureFile())
        #expect(try String(contentsOf: url, encoding: .utf8) == handEdited)
        // An exclusion from Activity is inserted, and nothing else changes.
        model.prepare(.domain("example.com"))
        model.addPendingExclusion()
        #expect(model.pendingExclusion == nil)
        #expect(model.lastAdded == PendingExclusion(list: .excludeDomains, value: "example.com"))
        #expect(model.entries(.excludeDomains) == ["example.com"])
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved.replacingOccurrences(of: "\"example.com\"", with: "") == handEdited)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["settings.toml"])
    }

    @Test("TRK-50 a settings file still in iCloud Drive is downloaded, never replaced by the defaults")
    func settingsFilePlaceholder() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TrackerPaneTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appending(path: ".settings.toml.icloud"))
        let model = TrackerSettingsModel(settingsURL: folder.appending(path: "settings.toml"))
        #expect(!model.ensureFile())
        #expect(model.message != nil)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "settings.toml").path))
    }

    @Test("TRK-54 each hook of the snippets names its event, so the tracker accepts it, runs in the background, and stays silent on errors")
    func snippets() throws {
        let lines = TrackerSnippets.tmux.split(separator: "\n").map(String.init)
        #expect(lines.first == "set -g focus-events on")
        #expect(lines.count == TrackerSnippets.tmuxHooks.count + 1)
        #expect(!TrackerSnippets.tmux.contains("pane-focus-in"))
        for hook in TrackerSnippets.tmuxHooks {
            let line = try #require(lines.first { $0.hasPrefix("set-hook -g \(hook) ") })
            #expect(line.contains("'run-shell -b \""))
            let command = try #require(line.split(separator: "\"").dropFirst().first)
            #expect(command.hasSuffix(" >/dev/null 2>&1 || true"))
            let event = command.replacingOccurrences(of: "tracker-event ", with: "").replacingOccurrences(
                of: " >/dev/null 2>&1 || true",
                with: ""
            )
            #expect(try TrackerCommand.parse(event + "\n") == .tmuxEvent(hook: hook, arguments: []))
        }
        let json = try JSONSerialization.jsonObject(with: Data(TrackerSnippets.agentHooks.utf8)) as? [String: Any]
        let hooks = try #require(json?["hooks"] as? [String: [[String: Any]]])
        #expect(Set(hooks.keys) == ["UserPromptSubmit", "Stop", "SessionEnd"])
        for (name, entries) in hooks {
            let inner = try #require(entries.first?["hooks"] as? [[String: String]])
            let command = try #require(inner.first?["command"])
            #expect(command.hasSuffix(" >/dev/null 2>&1 &"))
            let event = command.replacingOccurrences(of: "tracker-event ", with: "").replacingOccurrences(
                of: " >/dev/null 2>&1 &",
                with: ""
            )
            #expect(try TrackerCommand.parse(event + "\n") == .agentEvent(hook: name, arguments: []))
        }
    }
}
