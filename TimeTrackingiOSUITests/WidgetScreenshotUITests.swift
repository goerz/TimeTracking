// WidgetScreenshotUITests: adds the widgets to the iPhone simulator's Home
// Screen for `make screenshots` (architecture.md §2.7). No command adds a widget,
// so this drives SpringBoard. It runs only with TIMETRACKING_SCREENSHOTS set.

import XCTest

final class WidgetScreenshotUITests: XCTestCase {
    /// The widgets to add, in medium size; each new one goes to the top.
    private static let widgets = ["Pinned", "Recent", "Now"]

    @MainActor
    func testAddWidgetsToTheHomeScreen() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TIMETRACKING_SCREENSHOTS"] != nil)
        continueAfterFailure = false
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        // An earlier run's widgets stay on the Home Screen.
        let added = springboard.icons.matching(NSPredicate(format: "label == 'TimeTracking' AND value CONTAINS 'Widget'"))
        guard !added.firstMatch.exists else {
            return
        }
        for name in Self.widgets {
            add(name, on: springboard)
        }
        springboard.buttons["Done"].tap()
    }

    @MainActor
    private func add(_ name: String, on springboard: XCUIApplication) {
        let edit = springboard.buttons["Edit"]
        if !edit.exists {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).press(forDuration: 1.5)
        }
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let addWidget = springboard.buttons["Add Widget"]
        XCTAssertTrue(addWidget.waitForExistence(timeout: 5))
        addWidget.tap()
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("TimeTracking\n")
        let entry = springboard.cells["TimeTracking"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let medium = springboard.buttons
            .matching(NSPredicate(format: "label == %@ AND value CONTAINS 'Medium'", "TimeTracking, \(name)"))
            .firstMatch
        let right = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.55))
        let left = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.55))
        for _ in 0 ..< 8 where !medium.waitForExistence(timeout: 2) {
            right.press(forDuration: 0.05, thenDragTo: left)
        }
        XCTAssertTrue(medium.exists)
        springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Widget'")).firstMatch.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
    }
}
