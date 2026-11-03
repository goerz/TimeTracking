// The settings window's size: each pane's width and height, the window
// following the pane (spec_timer.md §8, TM-39).

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
