// The bundled tool writing while the app runs (spec_automation.md §9 item 40).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct ToolIntegrationTests {
    /// The change reaches the app through `<APP_ID>.changed` alone: no
    /// clock advance, no tick, and no poll, so the menu bar follows as soon
    /// as the notification is delivered.
    @Test("AUTO-40 a start by the bundled tool reaches the running app's menu bar through the change notification")
    func toolStartReachesMenuBar() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "auto40-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "store.sqlite")
        let test = try await TestApp(storeFile: url, observing: true)
        defer { test.app.stop() }
        _ = try await test.projects(["Noise paper"])
        let now = test.clock.now
        #expect(StatusItemPresenter.content(test.app.statusState, at: now).dial == nil)
        let result = try HelperTool.run(["start", "Hello", "--project", "Noise paper"], store: url, now: now)
        #expect(result.status == 0, "\(result.error)")
        #expect(await eventually { test.app.timer.running?.task == "Hello" })
        #expect(test.clock.now == now)
        let content = StatusItemPresenter.content(test.app.statusState, at: now)
        #expect(content.dial != nil)
        #expect(content.title.hasPrefix("0:00"))
        #expect(StatusItemPresenter.header(test.app.statusState, at: now).prefix(2) == ["Hello", "Noise paper · University"])
        await test.store.close()
    }
}
