// The settings window's size: each pane's width and height, the window
// following the pane (timer.md §8, TM-39).

import XCTest

final class SettingsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }

    /// The settings window's frame once two polls (about a second apart)
    /// agree: the window animates to a pane's measured height.
    @MainActor
    private func settledFrame(_ window: XCUIElement) -> CGRect {
        let last = FrameBox()
        let predicate = NSPredicate { _, _ in
            MainActor.assumeIsolated {
                let frame = window.frame
                defer { last.frame = frame }
                return frame == last.frame
            }
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 10), .completed)
        return window.frame
    }

    /// The settings window's frame on `pane`.
    @MainActor
    private func settingsFrame(_ app: XCUIApplication, pane: String) -> CGRect {
        let tab = app.toolbars.buttons[pane]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()
        let window = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(window.descendants(matching: .any)["settings.pane.\(pane.lowercased())"].waitForExistence(timeout: 5))
        return settledFrame(window)
    }

    @MainActor
    func testTM46_startOfDayMovesTheCalendarsHours() {
        let app = XCUIApplication.timeTracking(fixture: "small")
        app.launchPastOnboarding()
        app.typeKey("2", modifierFlags: .command)
        let label = app.descendants(matching: .any)["calendar.hourLabel.60"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertTrue([label.label, label.value as? String].contains("01:00"))
        app.typeKey(",", modifierFlags: .command)
        _ = settingsFrame(app, pane: "General")
        let picker = app.descendants(matching: .any)["settings.startOfDay"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()
        app.menuItems["04:00"].click()
        app.typeKey("w", modifierFlags: .command)
        let moved = NSPredicate(format: "label == %@ OR value == %@", "05:00", "05:00")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: label)], timeout: 10), .completed)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()
        app.menuItems["00:00"].click()
        app.typeKey("w", modifierFlags: .command)
        let restored = NSPredicate(format: "label == %@ OR value == %@", "01:00", "01:00")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: restored, object: label)], timeout: 10), .completed)
    }

    @MainActor
    func testTM56_foregroundTogglePersists() {
        let app = XCUIApplication.timeTracking()
        app.launchPastOnboarding()
        app.typeKey(",", modifierFlags: .command)
        _ = settingsFrame(app, pane: "Pomodoro")
        // A switch-style toggle: by identifier, whatever type XCUITest gives it.
        let toggle = app.descendants(matching: .any)["settings.pomodoroForeground"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value.map { "\($0)" }, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertEqual(toggle.value.map { "\($0)" }, "1")
        app.typeKey("w", modifierFlags: .command)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value.map { "\($0)" }, "1")
    }

    @MainActor
    func testTM39_settingsWindowFollowsThePane() {
        let app = XCUIApplication.timeTracking()
        app.launchPastOnboarding()
        app.typeKey(",", modifierFlags: .command)
        let general = settingsFrame(app, pane: "General")
        let pomodoro = settingsFrame(app, pane: "Pomodoro")
        XCTAssertEqual(pomodoro.width, general.width, accuracy: 1)
        XCTAssertLessThan(pomodoro.height, general.height - 100, "General \(general), Pomodoro \(pomodoro)")
        XCTAssertEqual(settingsFrame(app, pane: "General").height, general.height, accuracy: 1)
        // Just inside the bottom-right corner: a drag leaves the size alone.
        let window = app.windows["com_apple_SwiftUI_Settings_window"]
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        corner.click(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: 120, dy: 80)))
        XCTAssertEqual(window.frame.size.width, general.width, accuracy: 1)
        XCTAssertEqual(window.frame.size.height, general.height, accuracy: 1)
        app.terminate()
    }
}

/// The last frame `settledFrame` read.
private final class FrameBox {
    var frame = CGRect.null
}
