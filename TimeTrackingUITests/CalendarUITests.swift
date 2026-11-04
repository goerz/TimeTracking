// The Calendar's strip of days, zoom, column toggles, and toolbar as the
// real main window shows them (spec_calendar.md §1).

import XCTest

final class CalendarUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }

    // MARK: Helpers

    /// The app on the fixture at 2024-03-14T10:00, showing the Calendar.
    @MainActor
    private func openCalendar() -> XCUIApplication {
        let app = XCUIApplication.timeTracking()
        app.launchPastOnboarding()
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(element(app, "calendar.view").waitForExistence(timeout: 5))
        XCTAssertTrue(header(app, "2024-03-14").waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func header(_ app: XCUIApplication, _ day: String) -> XCUIElement {
        element(app, "calendar.header.\(day)")
    }

    /// The headers of the days in view, left to right, as (day, frame).
    @MainActor
    private func headers(_ app: XCUIApplication) -> [(day: String, frame: CGRect)] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'calendar.header.'"))
            .allElementsBoundByIndex
            .map { (String($0.identifier.dropFirst("calendar.header.".count)), $0.frame) }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// The days' left edge: the time axis's trailing edge (the content may
    /// extend under the sidebar).
    @MainActor
    private func leftEdge(_ app: XCUIApplication) -> CGFloat {
        element(app, "calendar.timeAxis").frame.maxX
    }

    /// The tracked total of the summary strip ("7h 10m").
    @MainActor
    private func trackedTotal(_ app: XCUIApplication) -> String {
        let text = element(app, "calendar.summary.tracked")
        return (text.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? text.label
    }

    /// The day whose header starts at the left edge, if one does.
    @MainActor
    private func dayAtLeftEdge(_ app: XCUIApplication) -> String? {
        let edge = leftEdge(app)
        return headers(app).first { abs($0.frame.minX - edge) < 1.5 }?.day
    }

    /// The middle of `element`, clicked there rather than where XCUITest's
    /// own hit point lands (it chose the edge of a small header button).
    @MainActor
    private func center(of element: XCUIElement) -> XCUICoordinate {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    /// Waits (polling about once a second) until `condition` holds.
    @MainActor
    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: @escaping @MainActor () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout) == .completed
    }

    // MARK: Tests

    @MainActor
    func testPC1_zoomKeepsTheNowLineInPlace() {
        let app = openCalendar()
        let now = element(app, "calendar.nowLine")
        XCTAssertTrue(now.waitForExistence(timeout: 5))
        let tracked = element(app, "calendar.tracked.2024-03-14")
        let lineY = now.frame.minY
        let zoomIn = element(app, "calendar.zoomIn")
        let zoomOut = element(app, "calendar.zoomOut")
        XCTAssertTrue(zoomIn.isHittable)
        // 72 → 90 → 72 → 57.6 → 46.08 points per hour.
        for (button, pointsPerHour) in [(zoomIn, 90.0), (zoomOut, 72), (zoomOut, 57.6), (zoomOut, 46.08)] {
            button.click()
            XCTAssertTrue(waitUntil { abs(tracked.frame.height - 24 * pointsPerHour) < 1 }, "\(pointsPerHour) pt per hour")
            XCTAssertTrue(waitUntil { abs(now.frame.minY - lineY) < 2 }, "the now-line moved from \(lineY) to \(now.frame.minY)")
        }
        // ⌘0 too.
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(waitUntil { abs(tracked.frame.height - 24 * 72) < 1 })
        XCTAssertTrue(waitUntil { abs(now.frame.minY - lineY) < 2 }, "the now-line moved from \(lineY) to \(now.frame.minY)")
    }

    @MainActor
    func testPC27_headersLineUpWithTheirColumns() {
        let app = openCalendar()
        let check = {
            let shown = self.headers(app)
            XCTAssertGreaterThanOrEqual(shown.count, 2)
            for (day, frame) in shown {
                let activity = self.element(app, "calendar.activity.\(day)")
                XCTAssertTrue(activity.exists, day)
                XCTAssertEqual(activity.frame.minX, frame.minX, accuracy: 1, "\(day) header and columns")
                XCTAssertGreaterThanOrEqual(frame.width, 200, day)
            }
        }
        check()
        // Mid-day, after a sideways scroll, too.
        element(app, "calendar.tracked.2024-03-14").scroll(byDeltaX: -70, deltaY: 0)
        XCTAssertTrue(waitUntil { self.dayAtLeftEdge(app) == nil })
        check()
    }

    @MainActor
    func testPC3_sidewaysScrollingMovesThroughTimeAndTheArrowsSnap() {
        let app = openCalendar()
        let today = header(app, "2024-03-14")
        let start = today.frame.minX
        XCTAssertNotNil(dayAtLeftEdge(app), "Today puts a day start at the left edge \(leftEdge(app)): \(headers(app))")
        // Up and down scrolls the hours, and only the hours.
        let now = element(app, "calendar.nowLine")
        let lineY = now.frame.minY
        element(app, "calendar.tracked.2024-03-14").scroll(byDeltaX: 0, deltaY: -150)
        XCTAssertTrue(waitUntil { abs(now.frame.minY - lineY) > 50 }, "the hours did not scroll")
        XCTAssertEqual(today.frame.minX, start, accuracy: 0.5)
        // Sideways moves through time, without snapping to a day.
        element(app, "calendar.tracked.2024-03-14").scroll(byDeltaX: -70, deltaY: 0)
        XCTAssertTrue(waitUntil { abs(today.frame.minX - start) > 10 }, "a sideways scroll moved nothing")
        let moved = today.frame.minX
        XCTAssertTrue(waitUntil { today.frame.minX == moved && self.dayAtLeftEdge(app) == nil }, "the scroll snapped")
        // → goes to the next day start at the left edge.
        let firstShown = headers(app).first { $0.frame.maxX > leftEdge(app) + 1 }?.day
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil { self.dayAtLeftEdge(app) != nil }, "→ did not snap")
        XCTAssertNotEqual(dayAtLeftEdge(app), firstShown)
        // ← from a day start goes one day back.
        let snapped = dayAtLeftEdge(app)
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil { self.dayAtLeftEdge(app) != nil && self.dayAtLeftEdge(app) != snapped })
        // A drag on the headers scrolls too.
        let before = today.frame.minX
        let from = today.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // On the Mac only `click(forDuration:thenDragTo:)` drags; `press` does not.
        from.click(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: -120, dy: 0)))
        XCTAssertTrue(waitUntil { abs(today.frame.minX - before) > 60 }, "dragging the headers moved nothing")
        // The drag is no click: the days were not moved to a header.
        XCTAssertNil(dayAtLeftEdge(app), "the drag ended as a click on a header")
    }

    @MainActor
    func testPC27_dayWidthDecidesHowManyDaysShow() {
        let app = openCalendar()
        let slider = app.sliders["calendar.dayWidth"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let today = header(app, "2024-03-14")
        let width = today.frame.width
        let count = headers(app).count
        // ⌥⌘] and ⌥⌘[ by 1.25.
        app.typeKey("]", modifierFlags: [.command, .option])
        XCTAssertTrue(waitUntil { abs(today.frame.width - width * 1.25) < 1 }, "\(today.frame.width)")
        app.typeKey("[", modifierFlags: [.command, .option])
        XCTAssertTrue(waitUntil { abs(today.frame.width - width) < 1 }, "\(today.frame.width)")
        // The narrowest days: more of them.
        slider.adjust(toNormalizedSliderPosition: 0)
        XCTAssertTrue(waitUntil { today.frame.width < 110 }, "\(today.frame.width)")
        XCTAssertGreaterThan(headers(app).count, count + 3)
        XCTAssertTrue(today.exists, "the center day stays in view")
        // The widest: one day, cut off.
        slider.adjust(toNormalizedSliderPosition: 1)
        // The slider's knob lands a little short of the end (1600).
        XCTAssertTrue(waitUntil { today.frame.width > 1200 }, "\(today.frame.width)")
        XCTAssertLessThanOrEqual(headers(app).count, 2)
        // ⌥-click on a header: that day alone, as wide as the viewport.
        slider.adjust(toNormalizedSliderPosition: 0.3)
        let day = headers(app)[1]
        XCUIElement.perform(withKeyModifiers: .option) {
            self.header(app, day.day).coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)).click()
        }
        // The days reach the window's trailing edge ("calendar.view" also
        // spans the days drawn just outside it).
        let viewport = app.mainWindow.frame.maxX - leftEdge(app)
        XCTAssertTrue(waitUntil { abs(self.header(app, day.day).frame.width - viewport) < 2 }, "⌥-click")
        XCTAssertEqual(dayAtLeftEdge(app), day.day)
    }

    @MainActor
    func testPC27_columnTogglesInTheDayHeaders() {
        let app = openCalendar()
        let today = header(app, "2024-03-14")
        let start = today.frame.minX
        for (column, identifier) in [("activity", "calendar.activity.2024-03-14"), ("calendar", "calendar.events.2024-03-14")] {
            let toggle = today.descendants(matching: .any)["calendar.columnToggle.\(column)"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), column)
            XCTAssertTrue(element(app, identifier).exists, column)
            XCTAssertTrue(toggle.label.hasPrefix("Hide"), toggle.label)
            XCTAssertTrue(toggle.isHittable, "\(column) toggle not hittable")
            center(of: toggle).click()
            XCTAssertTrue(element(app, identifier).waitForNonExistence(timeout: 5), "\(column) still shown")
            // The struck-through glyph stays as the button that shows it again.
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            XCTAssertTrue(toggle.label.hasPrefix("Show"), toggle.label)
            // The click on the toggle is not a click on the header.
            XCTAssertEqual(today.frame.minX, start, accuracy: 1)
            XCTAssertTrue(toggle.isHittable, "hidden \(column) toggle not hittable at \(toggle.frame)")
            center(of: toggle).click()
            XCTAssertTrue(element(app, identifier).waitForExistence(timeout: 5), "\(column) not shown again")
        }
        // The menu items agree.
        app.typeKey("a", modifierFlags: [.command, .option])
        XCTAssertTrue(element(app, "calendar.activity.2024-03-14").waitForNonExistence(timeout: 5))
        XCTAssertTrue(today.descendants(matching: .any)["calendar.columnToggle.activity"].label.hasPrefix("Show"))
    }

    @MainActor
    func testPC28_filtersAndSearchInTheToolbar() {
        let app = openCalendar()
        XCTAssertTrue(element(app, "calendar.filters").exists)
        XCTAssertFalse(element(app, "calendar.days").exists)
        XCTAssertFalse(element(app, "calendar.columns").exists)
        XCTAssertTrue(element(app, "calendar.summary.tracked").waitForExistence(timeout: 5))
        let total = trackedTotal(app)
        XCTAssertFalse(total.isEmpty)
        let entries = app.descendants(matching: .any).matching(identifier: "calendar.entry")
        let count = entries.count
        XCTAssertGreaterThan(count, 2)
        // Select an entry; ⌫ in the search field must not delete it.
        entries.element(boundBy: 0).click()
        app.typeKey("f", modifierFlags: .command)
        app.typeText("appendixx")
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(entries.count, count, "⌫ in the search field deleted an entry")
        // The search narrows the tracked total and fades, but keeps, the others.
        XCTAssertTrue(waitUntil { self.trackedTotal(app) != total }, "the search left the total at \(total)")
        XCTAssertEqual(entries.count, count)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil { self.trackedTotal(app) == total }, "clearing the search left \(trackedTotal(app))")
        // Filters opens its popover.
        element(app, "calendar.filters").click()
        XCTAssertTrue(element(app, "calendar.filter.includeArchived").waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
    }
}
