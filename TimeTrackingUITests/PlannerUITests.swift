// What only the real Planner window shows (spec_planner_projects.md §1,
// spec_planner_reports.md §8).

import XCTest

final class PlannerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }

    /// The app on the fixture at the fixed test time, onboarding answered.
    @MainActor
    private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "YES", "-Fixture", "small"] + (reset ? ["-ResetState", "YES"] : [])
        app.launchEnvironment["TIMETRACKING_NOW"] = "2024-03-14T10:00:00"
        app.launch()
        let later = app.buttons["onboarding.later"]
        if later.waitForExistence(timeout: 5) {
            later.click()
        }
        XCTAssertTrue(app.textFields["timer.taskField"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func openPlanner(_ app: XCUIApplication) -> XCUIElement {
        app.typeKey("p", modifierFlags: [.command, .option])
        let sidebar = app.descendants(matching: .any)["planner.sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        return sidebar
    }

    @MainActor
    func testPP2_launchNeverOpensPlanner() {
        var app = launch()
        _ = openPlanner(app)
        app.descendants(matching: .any)["planner.sidebar.reports"].click()
        app.terminate()
        app = launch(reset: false)
        XCTAssertFalse(app.descendants(matching: .any)["planner.sidebar"].exists)
        _ = openPlanner(app)
        XCTAssertTrue(app.descendants(matching: .any)["reports.chart"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPP1_sectionShortcutsOnlyInPlanner() {
        let app = launch()
        // Timer key: ⌘3 does nothing.
        app.typeKey("3", modifierFlags: .command)
        XCTAssertFalse(app.descendants(matching: .any)["planner.sidebar"].exists)
        _ = openPlanner(app)
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["reports.chart"].waitForExistence(timeout: 5))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["projects.table"].waitForExistence(timeout: 5))
        app.typeKey("1", modifierFlags: [.command, .option])
        XCTAssertTrue(app.descendants(matching: .any)["clientsAreas.list"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPR20_reportCardShortcuts() {
        let app = launch()
        _ = openPlanner(app)
        app.typeKey("3", modifierFlags: .command)
        app.typeKey("2", modifierFlags: [.command, .control])
        XCTAssertTrue(app.descendants(matching: .any)["reports.entries"].waitForExistence(timeout: 5))
        app.typeKey("1", modifierFlags: [.command, .control])
        XCTAssertTrue(app.descendants(matching: .any)["reports.breakdown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.chart"].exists)
    }
}
