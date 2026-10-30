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
        // Move the window by its title bar; the frame is the one to come back.
        let window = app.windows["planner"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let original = window.frame
        let titleBar = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 12))
        titleBar.click(forDuration: 0.2, thenDragTo: titleBar.withOffset(CGVector(dx: -60, dy: 40)))
        let moved = window.frame
        XCTAssertNotEqual(moved, original)
        app.terminate()
        app = launch(reset: false)
        XCTAssertFalse(app.descendants(matching: .any)["planner.sidebar"].exists)
        _ = openPlanner(app)
        XCTAssertTrue(app.descendants(matching: .any)["reports.chart"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows["planner"].frame, moved)
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

    @MainActor
    func testPC6_drawingInTrackedOpensThePopover() {
        let app = launch()
        _ = openPlanner(app)
        app.typeKey("2", modifierFlags: .command)
        let tracked = app.descendants(matching: .any)["calendar.tracked.2024-03-14"]
        XCTAssertTrue(tracked.waitForExistence(timeout: 5))
        let start = tracked.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = tracked.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.click(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.textFields["calendar.draft.task"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.descendants(matching: .any)["calendar.draft"].exists)
    }

    @MainActor
    func testPC24_calendarMenuItemsAndToday() {
        let app = launch()
        _ = openPlanner(app)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["planner.calendar"].waitForExistence(timeout: 5))
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["calendar.header.2024-03-12"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuBars.menuItems["Fill Day…"].exists)
    }

    @MainActor
    func testPA17_activityCellOpensCalendar() {
        let app = launch()
        _ = openPlanner(app)
        app.typeKey("4", modifierFlags: .command)
        // The week of 2024-03-14; under -UITesting the block log comes from the fixture.
        let cell = app.descendants(matching: .any)["activity.cell.day:2024-03-13.10"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.click()
        XCTAssertTrue(app.descendants(matching: .any)["calendar.header.2024-03-13"].waitForExistence(timeout: 5))
        app.typeKey("4", modifierFlags: .command)
        // The same range again.
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["activity.footer"].exists)
    }
}
