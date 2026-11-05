// The edit popover on the running entry, opened from the bar and from the
// list (spec_timer.md §4).

import XCTest

final class EntryEditorUITests: XCTestCase {
    /// The running fixture's entry: 09:35 to now (10:00), "Prepare methods 6".
    private static let runningTask = "Prepare methods 6"

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.timeTracking(fixture: "running")
        app.launchPastOnboarding()
        XCTAssertEqual(app.textFields["timer.taskField"].value as? String, Self.runningTask)
        return app
    }

    /// The popover's Start field, after the editor loaded the entry.
    @MainActor
    private func startField(in app: XCUIApplication) -> XCUIElement {
        let start = app.textFields["editor.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["editor.task"].value as? String, Self.runningTask)
        return start
    }

    /// Replaces the Start field's text and commits it with Return.
    @MainActor
    private func setStart(_ text: String, in app: XCUIApplication) {
        let start = startField(in: app)
        start.click()
        start.typeKey("a", modifierFlags: .command)
        start.typeText(text + "\r")
    }

    /// The bar's task field and the running row still carry the task.
    @MainActor
    private func assertTaskKept(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let field = app.textFields["timer.taskField"]
        let kept = NSPredicate(format: "value == %@", Self.runningTask)
        let expectation = XCTNSPredicateExpectation(predicate: kept, object: field)
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: 5),
            .completed,
            "task field: \(field.value ?? "nil")",
            file: file,
            line: line
        )
        let row = app.descendants(matching: .any)["timer.runningRow"]
        XCTAssertTrue(row.label.contains(Self.runningTask), "running row: \(row.label)", file: file, line: line)
    }

    @MainActor
    func testTM51_projectShortcutInPopoverOpensItsPicker() {
        let app = launch()
        app.buttons["timer.time"].click()
        _ = startField(in: app)
        app.typeKey("j", modifierFlags: .command)
        let picker = app.descendants(matching: .any)["picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        // The picker is the popover's: closing it leaves the popover open.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.textFields["editor.start"].exists)
        // ⌘P is no shortcut of the popover.
        app.typeKey("p", modifierFlags: .command)
        XCTAssertFalse(picker.waitForExistence(timeout: 2))
    }

    @MainActor
    func testTM37_editRunningStartFromTimerLabelKeepsTask() {
        let app = launch()
        app.buttons["timer.time"].click()
        setStart("9:20", in: app)
        // The elapsed time counts from the new start; the task stays.
        let time = app.buttons["timer.time"]
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '0:40:00'"), object: time)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed, "time: \(time.label)")
        XCTAssertEqual(app.textFields["editor.task"].value as? String, Self.runningTask)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.textFields["editor.start"].waitForExistence(timeout: 2))
        assertTaskKept(in: app)
    }

    @MainActor
    func testTM37_editRunningStartFromRunningRowKeepsTask() {
        let app = launch()
        let row = app.descendants(matching: .any)["timer.runningRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        setStart("9:20", in: app)
        // Tab on to Stop and Duration, then click outside: nothing else changes.
        app.typeKey("\t", modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.textFields["editor.start"].waitForExistence(timeout: 2))
        assertTaskKept(in: app)
        XCTAssertEqual(app.buttons["timer.time"].label, "0:40:00")
    }

    @MainActor
    func testTM37_editRunningTaskInPopoverUpdatesBar() {
        let app = launch()
        app.buttons["timer.time"].click()
        _ = startField(in: app)
        let task = app.textFields["editor.task"]
        task.click()
        task.typeKey("a", modifierFlags: .command)
        task.typeText("Unit title\r")
        let field = app.textFields["timer.taskField"]
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Unit title'"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 5), .completed, "task field: \(field.value ?? "nil")")
        app.typeKey(.escape, modifierFlags: [])
        // Reopening shows the new task, and a Start edit keeps it.
        app.buttons["timer.time"].click()
        let start = app.textFields["editor.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["editor.task"].value as? String, "Unit title")
        start.click()
        start.typeKey("a", modifierFlags: .command)
        start.typeText("9:30\r")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(field.value as? String, "Unit title")
    }

    @MainActor
    func testTM37_editRunningStartAfterTypingInBarKeepsNewTask() {
        let app = launch()
        // A task typed in the bar, its last keys not yet committed (500 ms).
        let field = app.textFields["timer.taskField"]
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Outline title")
        app.buttons["timer.time"].click()
        let start = app.textFields["editor.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["editor.task"].value as? String, "Outline title")
        start.click()
        start.typeKey("a", modifierFlags: .command)
        start.typeText("9:20\r")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.textFields["editor.start"].waitForExistence(timeout: 2))
        XCTAssertEqual(field.value as? String, "Outline title")
        let row = app.descendants(matching: .any)["timer.runningRow"]
        XCTAssertTrue(row.label.contains("Outline title"), "running row: \(row.label)")
    }
}
