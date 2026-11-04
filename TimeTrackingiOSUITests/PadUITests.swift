// What only the iPad's real screens show: the tabs, the hardware keyboard,
// drawing and scrolling in the Calendar by touch, and section URLs
// (spec_ios.md §6.4, §10). Skipped on the iPhone.

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
        XCTAssertTrue(element(app, "calendar.view").waitForExistence(timeout: 5), "calendar.view")
        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(element(app, "activity.view").waitForExistence(timeout: 5), "activity.view")
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(element(app, "reports.card").waitForExistence(timeout: 5), "reports.card")
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(element(app, "projects.status").waitForExistence(timeout: 5), "projects.status")
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["timer.startButton"].waitForExistence(timeout: 5))
        // ⌘T in the Timer tab does nothing: still the Timer, no section tab.
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(app.buttons["timer.startButton"].exists)
        XCTAssertFalse(element(app, "calendar.view").isHittable)
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
    func testIOS43_calendarScrollsAndZoomsByTouch() throws {
        let app = try launch()
        app.typeKey("2", modifierFlags: .command)
        let column = element(app, "calendar.tracked.2024-03-14")
        XCTAssertTrue(column.waitForExistence(timeout: 5), "tracked column")
        let now = element(app, "calendar.nowLine")
        XCTAssertTrue(now.waitForExistence(timeout: 5), "now line")
        // A swipe up scrolls the hours (a long press would draw).
        let lineY = now.frame.minY
        column.swipeUp()
        XCTAssertLessThan(now.frame.minY, lineY - 100, "the hours did not scroll")
        // A sideways swipe on the day headers moves through time.
        let header = element(app, "calendar.header.2024-03-14")
        let headerX = header.frame.minX
        header.swipeLeft()
        XCTAssertLessThan(header.frame.minX, headerX - 75, "the days did not scroll")
        // A pinch zooms: the hours or the day width, by the fingers' axis.
        let height = column.frame.height
        let width = header.frame.width
        // On the visible hours (the column itself reaches far off screen).
        app.scrollViews.firstMatch.pinch(withScale: 2, velocity: 1)
        XCTAssertTrue(
            column.frame.height > height * 1.2 || header.frame.width > width * 1.2,
            "a pinch zoomed nothing (\(column.frame.height), \(header.frame.width))"
        )
    }

    @MainActor
    func testIOS38_reportsURLSelectsTheReportsTab() throws {
        let app = try launch()
        let url = try XCTUnwrap(URL(string: "timetracking-debug://planner/reports"))
        app.open(url)
        XCTAssertTrue(element(app, "reports.card").waitForExistence(timeout: 20), "reports.card")
    }
}
