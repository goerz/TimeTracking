// What only the iPad's real screens show: the tabs, the hardware keyboard,
// drawing in the Calendar by touch, and Planner URLs (spec_ios.md §6.4,
// §10). Skipped on the iPhone.

import XCTest

final class PadUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        continueAfterFailure = true
    }

    @MainActor
    private func launch(fixture: String = "small") throws -> XCUIApplication {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = XCUIApplication.timeTracking(fixture: fixture)
        app.launch()
        XCTAssertTrue(app.buttons["timer.startButton"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    func testIOS34_keyboardSelectsTabs() throws {
        let app = try launch()
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(element(app, "planner.calendar").waitForExistence(timeout: 5), "planner.calendar")
        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(element(app, "planner.activity").waitForExistence(timeout: 5), "planner.activity")
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(element(app, "reports.card").waitForExistence(timeout: 5), "reports.card")
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(element(app, "projects.status").waitForExistence(timeout: 5), "projects.status")
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["timer.startButton"].waitForExistence(timeout: 5))
        // ⌘T in the Timer tab does nothing: still the Timer, no Planner tab.
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(app.buttons["timer.startButton"].exists)
        XCTAssertFalse(element(app, "planner.calendar").isHittable)
    }

    @MainActor
    func testIOS35_drawingInTheTrackedColumnCreatesAnEntry() throws {
        let app = try launch(fixture: "empty")
        app.typeKey("2", modifierFlags: .command)
        let column = element(app, "calendar.tracked.2024-03-14")
        if !column.waitForExistence(timeout: 5) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("tracked column")
        }
        let now = element(app, "calendar.nowLine")
        XCTAssertTrue(now.waitForExistence(timeout: 5), "now line")
        // From 90 to 30 points above the now line (10:00): a past slot.
        let origin = column.coordinate(withNormalizedOffset: .zero)
        let nowY = now.frame.midY - column.frame.minY
        let x = column.frame.width / 2
        let from = origin.withOffset(CGVector(dx: x, dy: nowY - 90))
        let to = origin.withOffset(CGVector(dx: x, dy: nowY - 30))
        from.press(forDuration: 0.8, thenDragTo: to)
        let task = app.textFields["calendar.draft.task"]
        XCTAssertTrue(task.waitForExistence(timeout: 5), "draft editor")
        task.typeText("Drawn by touch\n")
        if !element(app, "calendar.entry").waitForExistence(timeout: 5) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("calendar.entry")
        }

        // Past now: refused with the notice.
        let late = origin.withOffset(CGVector(dx: x, dy: nowY + 30))
        let later = origin.withOffset(CGVector(dx: x, dy: nowY + 90))
        late.press(forDuration: 0.8, thenDragTo: later)
        XCTAssertTrue(element(app, "calendar.notice").waitForExistence(timeout: 5), "calendar.notice")
        XCTAssertFalse(task.exists)
    }

    @MainActor
    func testIOS38_reportsURLSelectsTheReportsTab() throws {
        let app = try launch()
        let url = try XCTUnwrap(URL(string: "timetracking-debug://planner/reports"))
        app.open(url)
        XCTAssertTrue(element(app, "reports.card").waitForExistence(timeout: 20), "reports.card")
    }
}
