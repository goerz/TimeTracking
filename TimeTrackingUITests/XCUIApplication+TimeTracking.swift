// XCUIApplication+TimeTracking: the Debug Mac app as the UI tests launch it
// (spec_architecture.md §3.3).

import XCTest

@MainActor
extension XCUIApplication {
    /// The Debug app with `-UITesting YES`, a fixture, and a fixed clock;
    /// `reset` adds `-ResetState YES`.
    static func timeTracking(fixture: String = "small", reset: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "YES", "-Fixture", fixture] + (reset ? ["-ResetState", "YES"] : []) + extra
        app.launchEnvironment["TIMETRACKING_NOW"] = "2024-03-14T10:00:00"
        return app
    }

    /// Launches, answers the first-launch alert with Later if it shows, and
    /// waits for the Timer window's task field.
    func launchPastOnboarding() {
        launch()
        let later = buttons["onboarding.later"]
        if later.waitForExistence(timeout: 5) {
            later.click()
        }
        XCTAssertTrue(textFields["timer.taskField"].waitForExistence(timeout: 10))
    }
}
