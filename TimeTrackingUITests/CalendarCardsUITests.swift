// Clicking, dragging, and resizing the Calendar's cards in the real main
// window (calendar.md §2.4, §2.5, §4.2, §4.4). A drag cannot be held
// open from a test, so its time label and Escape are the view model tests'
// (PC-38).

import XCTest

final class CalendarCardsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }

    // MARK: Helpers

    private static let today = "2024-03-14"
    private static let tomorrow = "2024-03-15"
    private static let yesterday = "2024-03-13"
    /// Points per hour at the default zoom.
    private static let hour: CGFloat = 72

    /// The app at 2024-03-14T10:00 showing the Calendar, with yesterday in view.
    @MainActor
    private func openCalendar(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.timeTracking(extra: extra)
        app.launchPastOnboarding()
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(element(app, "calendar.view").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "calendar.header.\(Self.yesterday)").waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// The title of the card with `identifier` showing `label`.
    @MainActor
    private func card(_ app: XCUIApplication, _ label: String, identifier: String = "calendar.entry") -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label == %@", identifier, label))
            .firstMatch
    }

    /// A point `hours` below the top of `column`, at `x` of its width.
    @MainActor
    private func point(in column: XCUIElement, hours: Double, x: CGFloat = 0.5) -> XCUICoordinate {
        column.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: column.frame.width * x, dy: CGFloat(hours) * Self.hour))
    }

    /// Drags from `from` by `offset`. On the Mac only
    /// `click(forDuration:thenDragTo:)` drags.
    @MainActor
    private func drag(_ from: XCUICoordinate, by offset: CGVector) {
        from.click(forDuration: 0.1, thenDragTo: from.withOffset(offset))
    }

    /// Waits (polling about once a second) until `condition` holds.
    @MainActor
    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: @escaping @MainActor () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout) == .completed
    }

    /// Draws a time block from `from` to `to` hours of `day`, titled `title`.
    @MainActor
    private func drawBlock(_ app: XCUIApplication, _ title: String, day: String, from: Double, to: Double) -> XCUIElement {
        let column = element(app, "calendar.events.\(day)")
        XCTAssertTrue(column.waitForExistence(timeout: 5))
        drag(point(in: column, hours: from), by: CGVector(dx: 0, dy: CGFloat(to - from) * Self.hour))
        let field = element(app, "calendar.block.title")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        app.typeText(title)
        app.typeKey(.return, modifierFlags: [])
        let block = card(app, title, identifier: "calendar.timeBlock")
        XCTAssertTrue(block.waitForExistence(timeout: 5), title)
        return block
    }

    // MARK: Tests

    @MainActor
    func testPC37_shiftAndCommandClickExtendTheSelection() {
        let app = openCalendar()
        let first = card(app, "Plan appendix 5")
        let second = card(app, "Prepare slides 2")
        let third = card(app, "Clarify intro")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.click()
        XCUIElement.perform(withKeyModifiers: .shift) { second.click() }
        XCUIElement.perform(withKeyModifiers: .command) { third.click() }
        // ⌘-click takes a selected card out again.
        XCUIElement.perform(withKeyModifiers: .command) { second.click() }
        app.typeKey(.delete, modifierFlags: [])
        let notice = element(app, "calendar.notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(first.waitForNonExistence(timeout: 5), "the first card stayed")
        XCTAssertTrue(third.waitForNonExistence(timeout: 5), "the ⌘-clicked card stayed")
        XCTAssertTrue(second.exists, "the card taken out of the selection went too")
    }

    @MainActor
    func testPC37_optionClickSelectsAlone() {
        let app = openCalendar()
        let first = card(app, "Plan appendix 5")
        let second = card(app, "Prepare slides 2")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.click()
        XCUIElement.perform(withKeyModifiers: .option) { second.click() }
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(second.waitForNonExistence(timeout: 5), "the ⌥-clicked card stayed")
        XCTAssertTrue(first.exists, "⌥-click extended the selection")
    }

    @MainActor
    func testPC38_optionSnapsAMoveToTheMinute() {
        let app = openCalendar()
        // Starts at xx:29:46. Nine points (7:30) down lands on xx:37:16: plain
        // snapping gives xx:35, ⌥ xx:37, 7:14 (8.7 points) later. There is
        // room before the next entry, so no overlap asks.
        let title = card(app, "Prepare slides 2")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let top = title.frame.minY
        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        XCUIElement.perform(withKeyModifiers: .option) {
            self.drag(start, by: CGVector(dx: 0, dy: 9))
        }
        let expected = top + 8.7
        XCTAssertTrue(waitUntil { abs(title.frame.minY - expected) < 1.1 }, "\(title.frame.minY), not \(expected)")
    }

    @MainActor
    func testPC38_aDropOutsideTrackedChangesNothing() {
        let app = openCalendar()
        let title = card(app, "Check tests 2")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let frame = title.frame
        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let activity = element(app, "calendar.activity.\(Self.yesterday)").frame
        let events = element(app, "calendar.events.\(Self.yesterday)").frame
        let axis = element(app, "calendar.timeAxis").frame
        let header = element(app, "calendar.header.\(Self.yesterday)").frame
        for (name, offset) in [
            ("Activity", CGVector(dx: activity.midX - frame.midX, dy: 0)),
            ("Calendar", CGVector(dx: events.midX - frame.midX, dy: 0)),
            ("the time axis", CGVector(dx: axis.midX - frame.midX, dy: 0)),
            ("the headers", CGVector(dx: 0, dy: header.midY - frame.midY)),
        ] {
            drag(start, by: offset)
            // Give a wrong drop the time to arrive.
            XCTAssertFalse(waitUntil(2) { title.frame != frame }, "a drop on \(name) moved the entry")
        }
    }

    @MainActor
    func testPC38_aDropOnTheNextDayMovesTheEntryThere() {
        let app = openCalendar()
        let title = card(app, "Check tests 2")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let tracked = element(app, "calendar.tracked.\(Self.today)")
        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        drag(start, by: CGVector(dx: tracked.frame.midX - title.frame.midX, dy: 0))
        XCTAssertTrue(waitUntil { tracked.frame.contains(CGPoint(x: title.frame.midX, y: title.frame.midY)) }, "\(title.frame)")
    }

    @MainActor
    func testPC40_aTimeBlockMovesAcrossDaysAndResizes() {
        let app = openCalendar(extra: ["-CalendarAccess", "YES"])
        let block = drawBlock(app, "Plan", day: Self.today, from: 11, to: 12)
        // One day on and one hour down, past the now-line.
        let next = element(app, "calendar.events.\(Self.tomorrow)")
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        let start = block.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        drag(start, by: CGVector(dx: next.frame.midX - block.frame.midX, dy: Self.hour))
        XCTAssertTrue(waitUntil { next.frame.minX <= block.frame.minX && block.frame.minX < next.frame.maxX }, "\(block.frame)")
        XCTAssertEqual(block.frame.minY - next.frame.minY, 12 * Self.hour, accuracy: 8)
        // The bottom edge, one hour down: the duration says 2h.
        drag(point(in: next, hours: 13 - 2 / Double(Self.hour)), by: CGVector(dx: 0, dy: Self.hour))
        XCTAssertTrue(card(app, "2h", identifier: "calendar.timeBlock").waitForExistence(timeout: 5), "the bottom edge did not resize")
        // The top edge, one hour down: 1h again.
        drag(point(in: next, hours: 12 + 2 / Double(Self.hour)), by: CGVector(dx: 0, dy: Self.hour))
        XCTAssertTrue(card(app, "1h", identifier: "calendar.timeBlock").waitForExistence(timeout: 5), "the top edge did not resize")
        // A drop on the time axis leaves it.
        let frame = block.frame
        let axis = element(app, "calendar.timeAxis").frame
        drag(block.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), by: CGVector(dx: axis.midX - frame.midX, dy: 0))
        XCTAssertFalse(waitUntil(2) { block.frame != frame }, "a drop on the time axis moved the block")
    }

    @MainActor
    func testPC41_aTimeBlockMakesAnEntryByItsPlusAndByADrop() {
        let app = openCalendar(extra: ["-CalendarAccess", "YES"])
        let task = element(app, "calendar.draft.task")
        // The hover "+", on a block saved by a click: after a synthesized
        // Return in the editor the app reports no more hover, with a test or
        // with scripts/drive_mac_app.py alike.
        let column = element(app, "calendar.events.\(Self.today)")
        XCTAssertTrue(column.waitForExistence(timeout: 5))
        drag(point(in: column, hours: 8), by: CGVector(dx: 0, dy: Self.hour))
        let save = element(app, "calendar.block.save")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.click()
        let untitled = card(app, "1h", identifier: "calendar.timeBlock")
        XCTAssertTrue(untitled.waitForExistence(timeout: 5))
        untitled.hover()
        let plus = element(app, "calendar.createEntry")
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.click()
        XCTAssertTrue(task.waitForExistence(timeout: 5), "the + opened no popover")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(task.waitForNonExistence(timeout: 5))
        // A drop on the Tracked column.
        let block = drawBlock(app, "Plan", day: Self.today, from: 9, to: 9.75)
        let tracked = element(app, "calendar.tracked.\(Self.today)")
        let center = block.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        drag(center, by: CGVector(dx: tracked.frame.midX - block.frame.midX, dy: 0))
        XCTAssertTrue(task.waitForExistence(timeout: 5), "the drop opened no popover")
        XCTAssertEqual(task.value as? String, "Plan")
    }
}
