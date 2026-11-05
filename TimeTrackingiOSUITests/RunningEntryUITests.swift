// Editing the running entry from the Timer: the card's elapsed time, the
// running row, and its context menu (spec_ios.md §2.2, §2.6, §2.7).

import XCTest

final class RunningEntryUITests: XCTestCase {
    /// The running fixture's entry: 09:35 to now (10:00).
    private static let runningTask = "Prepare methods 6"

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        continueAfterFailure = true
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.timeTracking(fixture: "running")
        app.launch()
        XCTAssertTrue(app.buttons["timer.stopButton"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["timer.taskField"].value as? String, Self.runningTask)
        return app
    }

    /// The sheet is open on the running entry with `task`.
    @MainActor
    private func assertSheet(in app: XCUIApplication, task: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = app.textFields["editor.task"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(field.value as? String, task, file: file, line: line)
        XCTAssertTrue(app.descendants(matching: .any)["editor.start"].exists, file: file, line: line)
        XCTAssertFalse(app.descendants(matching: .any)["editor.end"].exists, "a running entry has no End picker", file: file, line: line)
        XCTAssertFalse(app.buttons["editor.continue"].exists, file: file, line: line)
    }

    /// The card and the running row show `task`.
    @MainActor
    private func assertTimer(in app: XCUIApplication, task: String, time: String, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.buttons["timer.time"]
        let shows = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", time), object: label)
        XCTAssertEqual(XCTWaiter().wait(for: [shows], timeout: 5), .completed, "time: \(label.label)", file: file, line: line)
        XCTAssertEqual(app.textFields["timer.taskField"].value as? String, task, file: file, line: line)
        let row = app.descendants(matching: .any)["timer.runningRow"]
        XCTAssertTrue(row.label.contains(task), "running row: \(row.label)", file: file, line: line)
    }

    /// Sets the Start picker's minutes, then closes the picker.
    @MainActor
    private func setStartMinutes(_ minutes: String, in app: XCUIApplication) {
        let picker = app.datePickers["editor.start"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        // The compact picker: a date button, then a time button.
        let time = picker.buttons.element(boundBy: picker.buttons.count - 1)
        time.tap()
        let wheel = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        wheel.adjust(toPickerWheelValue: minutes)
        // Close the picker's popover without leaving the sheet.
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(wheel.waitForExistence(timeout: 2))
    }

    @MainActor
    func testIOS51_editSheetSuggestsTasks() {
        let app = launch()
        app.buttons["timer.time"].tap()
        assertSheet(in: app, task: Self.runningTask)
        let field = app.textFields["editor.task"]
        field.tap()
        // Leaves "Prepare methods", which other entries of the fixture contain.
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        let suggestion = app.buttons["editor.suggestion.0"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        XCTAssertFalse(suggestion.waitForExistence(timeout: 2))
        // Only Done stores the draft.
        app.buttons["editor.cancel"].tap()
        XCTAssertFalse(field.waitForExistence(timeout: 3))
        assertTimer(in: app, task: Self.runningTask, time: "0:25:00")
    }

    @MainActor
    func testIOS42_cardTimeEditsTheRunningStart() {
        let app = launch()
        app.buttons["timer.time"].tap()
        assertSheet(in: app, task: Self.runningTask)
        setStartMinutes("20", in: app)
        XCTAssertEqual(app.textFields["editor.task"].value as? String, Self.runningTask)
        app.buttons["editor.done"].tap()
        XCTAssertFalse(app.textFields["editor.task"].waitForExistence(timeout: 3))
        assertTimer(in: app, task: Self.runningTask, time: "0:40:00")
    }

    @MainActor
    func testIOS42_runningRowTapAndMenuOpenTheSheet() {
        let app = launch()
        let row = app.descendants(matching: .any)["timer.runningRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        assertSheet(in: app, task: Self.runningTask)
        app.buttons["editor.cancel"].tap()
        XCTAssertFalse(app.textFields["editor.task"].waitForExistence(timeout: 3))
        // Long press: Edit, Copy Task, and Discard.
        row.press(forDuration: 1.0)
        let edit = app.buttons["timer.runningRow.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["timer.runningRow.copyTask"].exists)
        XCTAssertTrue(app.buttons["timer.runningRow.discard"].exists)
        edit.tap()
        assertSheet(in: app, task: Self.runningTask)
        setStartMinutes("30", in: app)
        app.buttons["editor.done"].tap()
        XCTAssertFalse(app.textFields["editor.task"].waitForExistence(timeout: 3))
        assertTimer(in: app, task: Self.runningTask, time: "0:30:00")
    }

    @MainActor
    func testIOS42_taskTypedOnTheCardReachesTheSheet() {
        let app = launch()
        let field = app.textFields["timer.taskField"]
        // Past the text's end, so the insertion point is after it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(" title")
        // Straight to the editor, before the field's debounce.
        app.buttons["timer.time"].tap()
        let task = Self.runningTask + " title"
        assertSheet(in: app, task: task)
        setStartMinutes("20", in: app)
        app.buttons["editor.done"].tap()
        XCTAssertFalse(app.textFields["editor.task"].waitForExistence(timeout: 3))
        assertTimer(in: app, task: task, time: "0:40:00")
    }
}
