// The first-launch alert's "Open at login" checkbox and the Tracker pane's
// setup rows in real windows (spec_timer_window.md §8.2,
// spec_activity_tracking.md §7.4).

import XCTest

final class SetupUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }

    /// A screenshot kept in the result bundle.
    @MainActor
    private func keep(_ screenshot: XCUIScreenshot, _ name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testTW34_firstLaunchAlertOpensAtLoginByDefault() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "YES", "-Fixture", "small", "-ResetState", "YES"]
        app.launchEnvironment["TIMETRACKING_NOW"] = "2024-03-14T10:00:00"
        app.launch()
        let later = app.buttons["onboarding.later"]
        XCTAssertTrue(later.waitForExistence(timeout: 10))
        let checkbox = app.checkBoxes["onboarding.openAtLogin"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        XCTAssertEqual(checkbox.value as? Int, 1)
        XCTAssertTrue(checkbox.title.hasSuffix(" at login"))
        keep(app.windows.firstMatch.screenshot(), "first-launch-alert")
        later.click()
        // Under -UITesting the login item is the in-memory one: General shows it on.
        app.typeKey(",", modifierFlags: .command)
        let general = app.toolbars.buttons["General"]
        XCTAssertTrue(general.waitForExistence(timeout: 5))
        general.click()
        let toggle = app.descendants(matching: .any)["settings.openAtLogin"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? Int, 1)
        app.terminate()
    }

    @MainActor
    func testTRK33_setupRowsNameTheBundles() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "YES", "-Fixture", "small", "-ResetState", "YES"]
        app.launchEnvironment["TIMETRACKING_NOW"] = "2024-03-14T10:00:00"
        app.launch()
        let later = app.buttons["onboarding.later"]
        XCTAssertTrue(later.waitForExistence(timeout: 10))
        // Unchecked: the Tracker pane offers Open at Login.
        let checkbox = app.checkBoxes["onboarding.openAtLogin"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        checkbox.click()
        XCTAssertEqual(checkbox.value as? Int, 0)
        later.click()
        app.typeKey(",", modifierFlags: .command)
        let trackerTab = app.toolbars.buttons["Tracker"]
        XCTAssertTrue(trackerTab.waitForExistence(timeout: 5))
        trackerTab.click()
        let openAtLogin = app.buttons["tracker.action.openAtLogin.openAtLogin"]
        XCTAssertTrue(openAtLogin.waitForExistence(timeout: 5))
        let accessibility = app.buttons["tracker.action.accessibility.finder"]
        XCTAssertTrue(accessibility.exists)
        XCTAssertEqual(accessibility.label, "Show TimeTrackingAgent Debug in Finder")
        let settings = app.windows.containing(.button, identifier: "tracker.button").firstMatch
        keep(settings.screenshot(), "tracker-pane-setup-top")
        let fullDisk = app.buttons["tracker.action.fullDisk.finder"]
        XCTAssertTrue(fullDisk.exists)
        XCTAssertTrue(fullDisk.label.hasSuffix(" Debug in Finder"))
        XCTAssertFalse(fullDisk.label.contains("Agent"))
        openAtLogin.click()
        let mark = app.staticTexts["tracker.mark.openAtLogin"]
        XCTAssertTrue(mark.waitForExistence(timeout: 5))
        let done = expectation(for: NSPredicate(format: "label == %@ OR value == %@", "Done", "Done"), evaluatedWith: mark)
        wait(for: [done], timeout: 5)
        let pane = app.scrollViews["settings.pane.tracker"]
        pane.scroll(byDeltaX: 0, deltaY: -500)
        keep(settings.screenshot(), "tracker-pane-setup-full-disk")
        app.terminate()
    }
}
