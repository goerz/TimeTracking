// What only the real main window shows: its sidebar, the sections,
// and the frame across launches (projects.md §1,
// reports.md §8).

import XCTest

final class SectionsUITests: XCTestCase {
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
        let app = XCUIApplication.timeTracking(reset: reset)
        app.launchPastOnboarding()
        return app
    }

    @MainActor
    func testPP2_launchOpensTheMainWindowOnTheTimer() {
        var app = launch()
        let window = app.mainWindow
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["timer.list"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.windows["timer"].waitForExistence(timeout: 2))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["reports.chart"].waitForExistence(timeout: 5))
        // Move the window by its title bar; the frame is the one to come back.
        let original = window.frame
        let titleBar = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 12))
        titleBar.click(forDuration: 0.2, thenDragTo: titleBar.withOffset(CGVector(dx: -60, dy: 40)))
        let moved = window.frame
        XCTAssertNotEqual(moved, original)
        app.terminate()
        app = launch(reset: false)
        XCTAssertTrue(app.descendants(matching: .any)["timer.list"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.mainWindow.frame, moved)
    }

    @MainActor
    func testPP1_sectionShortcutsSelectSidebarItems() {
        let app = launch()
        XCTAssertTrue(app.mainWindow.waitForExistence(timeout: 5))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["reports.chart"].waitForExistence(timeout: 5))
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["projects.table"].waitForExistence(timeout: 5))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["timer.list"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPR20_reportCardShortcuts() {
        let app = launch()
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
        app.typeKey("2", modifierFlags: .command)
        let tracked = app.descendants(matching: .any)["calendar.tracked.2024-03-14"]
        XCTAssertTrue(tracked.waitForExistence(timeout: 5))
        let start = tracked.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = tracked.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.click(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.textFields["calendar.draft.task"].waitForExistence(timeout: 5))
        // The popover keeps the Calendar shown.
        XCTAssertTrue(app.descendants(matching: .any)["calendar.view"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.descendants(matching: .any)["calendar.draft"].exists)
    }

    @MainActor
    func testPC21_calendarMenuItemsAndToday() {
        let app = launch()
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["calendar.view"].waitForExistence(timeout: 5))
        // Day headers in view, by the day at the left edge of the days.
        let edge = app.descendants(matching: .any)["calendar.timeAxis"].frame.maxX
        let headers = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'calendar.header.'"))
        let first = { () -> String? in
            headers.allElementsBoundByIndex.first { abs($0.frame.minX - edge) < 1.5 }
                .map { String($0.identifier.dropFirst("calendar.header.".count)) }
        }
        let firstIs = { (day: String) in
            let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { first() == day } }
            return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5) == .completed
        }
        // ⌘T: today at position ⌈n / 2⌉ of the n whole days in view (3 in
        // the 1100 point window at 260 points per day).
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(firstIs("2024-03-13"), "\(first() ?? "none") at \(edge)")
        XCTAssertTrue(app.menuBars.menuItems["Duplicate to Next Day"].exists)
        // The navigation keys are the view's, not menu items: → one day,
        // ⇧→ the whole days in view; View › Previous Period (⌥⌘←) goes back as far.
        XCTAssertFalse(app.menuBars.menuItems["Next Day"].exists)
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(firstIs("2024-03-14"), "\(first() ?? "none")")
        app.typeKey(.rightArrow, modifierFlags: .shift)
        XCTAssertTrue(firstIs("2024-03-17"), "\(first() ?? "none")")
        // Chosen from the menu: a window manager on the test Mac may hold ⌥⌘←.
        app.menuBars.firstMatch.menuBarItems["View"].click()
        app.menuBars.firstMatch.menuItems["Previous Period"].click()
        XCTAssertTrue(firstIs("2024-03-14"), "\(first() ?? "none")")
    }

    @MainActor
    func testPA17_activityCellOpensCalendar() {
        let app = launch()
        app.typeKey("5", modifierFlags: .command)
        // The week of 2024-03-14; under -UITesting the block log comes from the fixture.
        let cell = app.descendants(matching: .any)["activity.cell.day:2024-03-13.10"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.click()
        XCTAssertTrue(app.descendants(matching: .any)["calendar.header.2024-03-13"].waitForExistence(timeout: 5))
        app.typeKey("5", modifierFlags: .command)
        // The same range again.
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["activity.footer"].exists)
    }
}
