// Smoke test: the Debug iOS app launches in UI-testing mode
// (architecture.md §3.1, §3.3).

import XCTest

final class LaunchUITests: XCTestCase {
    @MainActor
    func testLaunchesInUITestingMode() {
        let app = XCUIApplication.timeTracking(fixture: "empty")
        app.launch()
        XCTAssertTrue(app.buttons["timer.startButton"].waitForExistence(timeout: 10))
    }
}

extension XCUIApplication {
    /// The Debug app with `-UITesting YES`, a fixture, a fixed clock, and reset state.
    static func timeTracking(fixture: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "YES", "-Fixture", fixture, "-ResetState", "YES"] + extra
        app.launchEnvironment["TIMETRACKING_NOW"] = "2024-03-14T10:00:00"
        return app
    }
}
