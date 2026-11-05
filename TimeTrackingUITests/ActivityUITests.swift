// The pointer and the keyboard on the Activity section's panels, in the
// week of 2024-03-14 with the fixture's block log (spec_activity.md §1.5,
// §2, §3).

import XCTest

final class ActivityUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.timeTracking()
        app.launchPastOnboarding()
        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(element(app, "activity.cell.day:2024-03-13.10").waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// `target`, scrolled into the window.
    @MainActor
    @discardableResult
    private func reveal(_ app: XCUIApplication, _ target: XCUIElement) -> XCUIElement {
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        for _ in 0 ..< 8 where target.frame.maxY > app.mainWindow.frame.maxY - 40 {
            element(app, "activity.heatmap").scroll(byDeltaX: 0, deltaY: -150)
        }
        return target
    }

    /// The chart, scrolled into the window.
    @MainActor
    private func chart(_ app: XCUIApplication) -> XCUIElement {
        reveal(app, element(app, "activity.bars.chart"))
    }

    /// Whether `condition` comes true within 5 seconds.
    @MainActor
    private func eventually(_ condition: @escaping @MainActor () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5) == .completed
    }

    /// A point in the column of weekday `index` (Monday 0) of the chart's
    /// seven columns, at the fraction `height` of the chart, from its top.
    /// The y axis takes about 5% of the chart's width.
    @MainActor
    private func point(_ chart: XCUIElement, weekday index: Int, height: CGFloat) -> XCUICoordinate {
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.05 + 0.95 * (CGFloat(index) + 0.5) / 7, dy: height))
    }

    @MainActor
    private func text(_ element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    @MainActor
    func testPA26_clickingABarOpensItsDayInTheCalendar() {
        let app = launch()
        point(chart(app), weekday: 1, height: 0.8).click()
        XCTAssertTrue(element(app, "calendar.header.2024-03-12").waitForExistence(timeout: 5))
    }

    @MainActor
    func testPA25_hoveringABarShowsItsTooltip() {
        let app = launch()
        let chart = chart(app)
        let tooltip = element(app, "activity.bars.tooltip")
        XCTAssertFalse(tooltip.exists)
        point(chart, weekday: 0, height: 0.3).hover()
        XCTAssertTrue(tooltip.waitForExistence(timeout: 5))
        XCTAssertTrue(text(tooltip).hasPrefix("Mon Mar 11 · "), text(tooltip))
        // The next column, by the bar under the pointer and not the one a
        // y axis' width to the left.
        point(chart, weekday: 1, height: 0.3).hover()
        XCTAssertTrue(eventually { self.text(tooltip).hasPrefix("Tue Mar 12 · ") }, text(tooltip))
        // Saturday lies in the future.
        point(chart, weekday: 5, height: 0.3).hover()
        XCTAssertTrue(tooltip.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testPA27_heatmapKeys() {
        let app = launch()
        let first = element(app, "activity.cell.day:2024-03-11.0")
        // The row's label, left of its first cell, takes the focus.
        first.coordinate(withNormalizedOffset: CGVector(dx: -1.5, dy: 0.5)).click()
        XCTAssertTrue(eventually { first.value as? String == "focused" })
        app.typeKey(.rightArrow, modifierFlags: [])
        let next = element(app, "activity.cell.day:2024-03-11.1")
        XCTAssertTrue(eventually { next.value as? String == "focused" })
        app.typeKey(.downArrow, modifierFlags: [])
        let below = element(app, "activity.cell.day:2024-03-12.1")
        XCTAssertTrue(eventually { below.value as? String == "focused" })
        let details = element(app, "activity.cell.details")
        XCTAssertFalse(details.exists)
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(text(details).hasPrefix("Tue Mar 12 · 01:00"), text(details))
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(details.waitForNonExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element(app, "calendar.header.2024-03-12").waitForExistence(timeout: 5))
    }

    @MainActor
    func testPA28_barKeys() {
        let app = launch()
        // The y axis takes the focus; a click on a bar would drill down.
        chart(app).coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).click()
        app.typeKey(.space, modifierFlags: [])
        let tooltip = element(app, "activity.bars.tooltip")
        XCTAssertTrue(tooltip.waitForExistence(timeout: 5))
        XCTAssertTrue(text(tooltip).hasPrefix("Mon Mar 11 · "), text(tooltip))
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(eventually { self.text(tooltip).hasPrefix("Tue Mar 12 · ") }, text(tooltip))
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(tooltip.waitForNonExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element(app, "calendar.header.2024-03-12").waitForExistence(timeout: 5))
    }

    @MainActor
    func testPA29_spaceTogglesAFocusedAppsRow() {
        let app = launch()
        let total = element(app, "activity.total")
        let unfiltered = text(total)
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'activity.context.'"))
        reveal(app, rows.firstMatch).click()
        XCTAssertTrue(eventually { self.text(total) != unfiltered }, text(total))
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(eventually { self.text(total) == unfiltered }, text(total))
    }
}
