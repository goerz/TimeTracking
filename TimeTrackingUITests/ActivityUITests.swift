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

    /// The chart, scrolled into the window.
    @MainActor
    private func chart(_ app: XCUIApplication) -> XCUIElement {
        let chart = element(app, "activity.bars.chart")
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        for _ in 0 ..< 5 where chart.frame.maxY > app.mainWindow.frame.maxY - 40 {
            element(app, "activity.heatmap").scroll(byDeltaX: 0, deltaY: -150)
        }
        return chart
    }

    /// A point in the column of weekday `index` (Monday 0) of the chart's
    /// seven columns, at the height `dy` of the chart. The y axis takes
    /// about 5% of the chart's width.
    @MainActor
    private func point(_ chart: XCUIElement, weekday index: Int, dy: CGFloat) -> XCUICoordinate {
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.05 + 0.95 * (CGFloat(index) + 0.5) / 7, dy: dy))
    }

    @MainActor
    private func text(_ element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    @MainActor
    func testPA26_clickingABarOpensItsDayInTheCalendar() {
        let app = launch()
        point(chart(app), weekday: 1, dy: 0.8).click()
        XCTAssertTrue(element(app, "calendar.header.2024-03-12").waitForExistence(timeout: 5))
    }

    @MainActor
    func testPA25_hoveringABarShowsItsTooltip() {
        let app = launch()
        let chart = chart(app)
        let tooltip = element(app, "activity.bars.tooltip")
        XCTAssertFalse(tooltip.exists)
        point(chart, weekday: 0, dy: 0.3).hover()
        XCTAssertTrue(tooltip.waitForExistence(timeout: 5))
        XCTAssertTrue(text(tooltip).hasPrefix("Mon Mar 11 · "), text(tooltip))
        // The next column, by the bar under the pointer and not the one a
        // y axis' width to the left.
        point(chart, weekday: 1, dy: 0.3).hover()
        let tuesday = NSPredicate { _, _ in MainActor.assumeIsolated { self.text(tooltip).hasPrefix("Tue Mar 12 · ") } }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: tuesday, object: nil)], timeout: 5), .completed)
        // Saturday lies in the future.
        point(chart, weekday: 5, dy: 0.3).hover()
        XCTAssertTrue(tooltip.waitForNonExistence(timeout: 5))
    }
}
