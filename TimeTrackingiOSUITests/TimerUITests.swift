// What only the real iPhone and iPad screens show (ios.md §2, §6.4,
// §11; architecture.md §3.3).

import XCTest

final class TimerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        continueAfterFailure = true
    }

    @MainActor
    func testARCH17_fixtureShowsDataWithoutDiskOrCloudKit() {
        let app = XCUIApplication.timeTracking(fixture: "running")
        app.launch()
        XCTAssertTrue(app.buttons["timer.stopButton"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["timer.time"].label, "0:25:00")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'timer.row.continue.'"))
            .firstMatch
            .exists)
    }

    @MainActor
    func testIOS49_settingsShowMidnight() {
        let app = XCUIApplication.timeTracking(fixture: "small")
        app.launch()
        let settings = app.buttons["timer.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.midnight"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testIOS1_startWithEmptyFieldRunsAnEntry() {
        let app = XCUIApplication.timeTracking(fixture: "empty")
        app.launch()
        let start = app.buttons["timer.startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(app.buttons["timer.stopButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["timer.discardButton"].exists)
    }

    @MainActor
    func testIOS2_returnInTaskFieldStarts() {
        let app = XCUIApplication.timeTracking(fixture: "empty")
        app.launch()
        let field = app.textFields["timer.taskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Write the intro\n")
        XCTAssertTrue(app.buttons["timer.stopButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testIOS3_atTriggerOpensPickerAndAssigns() {
        let app = XCUIApplication.timeTracking(fixture: "small")
        app.launch()
        let field = app.textFields["timer.taskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Draft @")
        // The shared picker's container identifier also names its search field.
        let search = app.textFields.matching(NSPredicate(format: "identifier IN {'picker', 'picker.search'}")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        // The sheet takes the focus; the rest of the search goes into its field.
        search.typeText("noi")
        XCTAssertEqual(search.value as? String, "noi")
        let project = app.scrollViews["picker"].buttons.matching(NSPredicate(format: "label CONTAINS 'Noise'"))
            .firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        project.tap()
        XCTAssertFalse(search.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["timer.projectChip"].label.contains("Noise"))
        XCTAssertEqual(app.textFields["timer.taskField"].value as? String, "Draft")
    }

    @MainActor
    func testIOS6_fullLeadingSwipeContinues() {
        let app = XCUIApplication.timeTracking(fixture: "small")
        app.launch()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'timer.row.' AND NOT (identifier BEGINSWITH 'timer.row.continue.')"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["timer.startButton"].exists)
        // A full swipe: from the leading edge past the trailing edge.
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 1.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["timer.stopButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testIOS37_noAccountShowsOnlyTheBlockingScreen() {
        let app = XCUIApplication.timeTracking(fixture: "small", extra: ["-iCloudAccount", "none", "-Onboarding", "YES"])
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.noAccount"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["onboarding.tryAgain"].exists)
        XCTAssertFalse(app.buttons["timer.startButton"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    @MainActor
    func testIOS38_startURLRunsTheProject() throws {
        let app = XCUIApplication.timeTracking(fixture: "small")
        app.launch()
        XCTAssertTrue(app.buttons["timer.startButton"].waitForExistence(timeout: 10))
        let url = try XCTUnwrap(URL(string: "timetracking-debug://start?project=Noise%20paper"))
        app.open(url)
        XCTAssertTrue(app.buttons["timer.stopButton"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["timer.projectChip"].label.contains("Noise paper"))
    }
}
