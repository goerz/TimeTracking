// Smoke test: the Debug Mac app launches in UI-testing mode
// (spec_architecture.md §3.1, §3.3).

import XCTest

final class LaunchUITests: XCTestCase {
    @MainActor
    func testLaunchesInUITestingMode() {
        let app = XCUIApplication.timeTracking(fixture: "empty", reset: false)
        app.launch()
        XCTAssertTrue(app.textFields["timer.taskField"].waitForExistence(timeout: 10))
        app.terminate()
    }
}
