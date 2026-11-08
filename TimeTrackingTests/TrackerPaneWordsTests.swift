// The Tracker pane's words: setup rows, marks, list names, settings errors,
// and the socket replies the Calendar shows (activity_tracking.md §7.3,
// §7.4; design.md §11).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct TrackerPaneWordsTests {
    private static func state(lastTick: Date, sources: [TrackerSourceHealth]) -> TrackerState {
        TrackerState(
            block: nil,
            foreground: nil,
            presence: TrackerPresence(state: .active, since: lastTick),
            health: TrackerHealth(lastTick: lastTick, version: "1.0 (42)", sources: sources)
        )
    }

    @Test("TRK-49 the iCloud Drive row is done while the app copies the log, and says activity stays on this Mac only when it does")
    func iCloudRow() async throws {
        let now = try TestApp.date("2024-03-14T10:00")
        func row(_ status: TrackerSourceStatus, _ reason: String) async throws -> TrackerSetupStep {
            let source = TrackerSourceHealth(id: "shared_folder", name: "iCloud Drive", status: status, reason: reason)
            let state = Self.state(lastTick: now, sources: [source])
            let tracker = TrackerStatusModel(agent: FakeAgentService(), clock: ManualClock(now), readState: { state })
            await tracker.refresh()
            return try #require(tracker.setupSteps.first { $0.id == "icloud" })
        }
        let mirrored = try await row(.fallback, ActivityFolderMirror.fallbackReason)
        #expect(mirrored.mark == .done)
        #expect(mirrored.detail?.hasPrefix("On: this Mac's activity is copied to iCloud Drive while the app is open") == true)
        let off = try await row(.off, "iCloud Drive is off; activity stays on this Mac")
        #expect(off.mark == .attention)
        #expect(off.detail == "Off: activity stays on this Mac.")
        #expect(try await row(.active, "").detail == "On: this Mac's activity shows on iPhone and iPad, and theirs here.")
    }

    @Test("TRK-49 marks, lists, paths, and settings errors read as words, not symbols, keys, or internals")
    func paneWords() throws {
        #expect(TrackerSetupStep.Mark.done.accessibilityLabel == "Done")
        #expect(TrackerSetupStep.Mark.attention.accessibilityLabel == "Needs attention")
        #expect(TrackerSetupStep.Mark.unknown.accessibilityLabel == "Not checked yet")
        #expect(ExclusionList.excludeApps.displayNameWithKey == "excluded apps (exclude_apps)")
        #expect(ExclusionList.privateAgentPaths.displayName == "private coding agent folders")
        #expect(Set(ExclusionList.allCases.map(\.displayName)).count == ExclusionList.allCases.count)
        #expect(TrackerSettingsModel.displayPath(nil) == "Not available")
        #expect(AgentServiceError.restartFailed(status: 3).localizedDescription
            == "The tracker could not be restarted. Disable and enable it to try again.")
        // A file with a syntax error: the line and what to do, from the settings model.
        let folder = FileManager.default.temporaryDirectory.appending(path: "TrackerPaneWordsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "settings.toml")
        try Data("[privacy]\nexclude_apps = [\"a\"\n".utf8).write(to: url)
        let model = TrackerSettingsModel(settingsURL: url)
        model.prepare(.app(bundleIdentifier: "com.example.app"))
        model.addPendingExclusion()
        let message = try #require(model.message)
        #expect(message.hasPrefix("The settings file has an error on line 2: "))
        #expect(message.hasSuffix(". Fix it in the editor."))
        #expect(TrackerSettingsModel.message(for: CocoaError(.fileWriteNoPermission)).hasPrefix("Couldn't write the settings file: "))
    }

    @Test("TRK-49 the agent's socket replies become sentences for the Calendar's delete alert")
    func socketReplies() {
        #expect(TrackerCommandResult.rejection(reason: "nothing at 2024-03-14T09:00:00")
            == .rejected("This activity is no longer in the logs."))
        #expect(TrackerCommandResult.rejection(reason: TrackerReply.stoppingReason)
            == .rejected("The tracker is restarting. Try again in a moment."))
        #expect(TrackerCommandResult.rejection(reason: "not a local time: x") == .rejected("The tracker could not change the logs."))
        #expect(TrackerCommandResult.unreachable == .rejected("The tracker could not be reached."))
        #expect(TrackerCommandResult.notRunning == .rejected("The tracker is not running."))
    }

    @Test("TRK-49 a socket that does not exist reads as a tracker that could not be reached or is not running")
    func socketWithoutTracker() async {
        let missing = FileManager.default.temporaryDirectory.appending(path: "tt-missing-\(UUID().uuidString)/tracker.sock")
        let result = await TrackerSocket(url: missing).send("delete-block 2024-03-14T09:00:00")
        #expect([TrackerCommandResult.unreachable, .notRunning].contains(result))
    }
}
