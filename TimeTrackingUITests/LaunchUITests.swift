// The Debug Mac app's launch: UI-testing mode, the windows a launch opens,
// and opening windows with none open (architecture.md §3.1, §3.3;
// timer.md §1.3).

import XCTest

final class LaunchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }

    private static let settingsWindow = "com_apple_SwiftUI_Settings_window"

    @MainActor
    func testLaunchesInUITestingMode() {
        let app = XCUIApplication.timeTracking(fixture: "empty", reset: false)
        app.launch()
        XCTAssertTrue(app.textFields["timer.taskField"].waitForExistence(timeout: 10))
        app.terminate()
    }

    /// Killed (as by a crash or a force quit) with the main window, the Mini
    /// Timer, and Settings open, the app relaunches with the "At launch,
    /// show" window, not with no window or the restored ones.
    @MainActor
    func testTM38_launchAfterAKillShowsTheLaunchWindow() {
        var app = XCUIApplication.timeTracking()
        app.launchPastOnboarding()
        XCTAssertTrue(app.mainWindow.waitForExistence(timeout: 5))
        _ = app.openMiniTimer()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows[Self.settingsWindow].waitForExistence(timeout: 5))
        app.terminate()

        app = XCUIApplication.timeTracking(reset: false)
        app.launch()
        XCTAssertTrue(app.mainWindow.waitForExistence(timeout: 10))
        XCTAssertFalse(app.windows["timer"].waitForExistence(timeout: 2), "a window shown late must fail too")
        XCTAssertFalse(app.windows[Self.settingsWindow].exists)
        // At launch, show: Mini Timer.
        app.typeKey(",", modifierFlags: .command)
        let general = app.toolbars.buttons["General"]
        XCTAssertTrue(general.waitForExistence(timeout: 5))
        general.click()
        let picker = app.popUpButtons["settings.launchWindow"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()
        picker.menuItems["Mini Timer"].click()
        XCTAssertEqual(picker.value as? String, "Mini Timer")
        app.terminate()

        app = XCUIApplication.timeTracking(reset: false)
        app.launch()
        XCTAssertTrue(app.windows["timer"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.mainWindow.waitForExistence(timeout: 2), "a window shown late must fail too")
        XCTAssertFalse(app.windows[Self.settingsWindow].exists)
        app.terminate()
    }

    /// A login-item launch reopens what was open at the last quit; with
    /// nothing open it shows no window, and the menu bar item's commands
    /// still open every window.
    @MainActor
    func testTM5_TM40_loginItemLaunchReopensTheWindowsOpenAtQuit() {
        var app = XCUIApplication.timeTracking()
        app.launchPastOnboarding()
        XCTAssertTrue(app.mainWindow.waitForExistence(timeout: 5))
        let appName = app.menuBars.firstMatch.menuBarItems.element(boundBy: 1).title
        _ = app.openMiniTimer()
        quit(app)

        // Both windows were open at quit (their closes while quitting don't count).
        app = XCUIApplication.timeTracking(reset: false, extra: Self.loginItem)
        app.launch()
        XCTAssertTrue(app.mainWindow.waitForExistence(timeout: 10))
        XCTAssertTrue(app.windows["timer"].waitForExistence(timeout: 5))
        // Close both, then quit from the menu bar item.
        app.windows["timer"].typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.windows["timer"].waitForNonExistence(timeout: 5))
        app.mainWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.mainWindow.waitForNonExistence(timeout: 5))
        quit(app)

        // Nothing was open: only the menu bar item.
        app = XCUIApplication.timeTracking(reset: false, extra: Self.loginItem)
        app.launch()
        XCTAssertTrue(app.statusItems["statusItem"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.mainWindow.waitForExistence(timeout: 3))
        XCTAssertFalse(app.windows["timer"].exists)

        // TM-40: the menu bar item opens each window with none open.
        statusMenuItem(app, "Open \(appName)").click()
        XCTAssertTrue(app.mainWindow.waitForExistence(timeout: 5))
        app.mainWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.mainWindow.waitForNonExistence(timeout: 5))
        statusMenuItem(app, "Show Mini Timer").click()
        XCTAssertTrue(app.windows["timer"].waitForExistence(timeout: 5))
        app.windows["timer"].typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.windows["timer"].waitForNonExistence(timeout: 5))
        statusMenuItem(app, "Settings…").click()
        XCTAssertTrue(app.windows[Self.settingsWindow].waitForExistence(timeout: 5))
        app.terminate()
    }

    private static let loginItem = ["-LoginItemLaunch", "YES"]

    /// The menu bar item's menu item whose title matches `predicate`, with
    /// the menu open: the hittable one (the main menu has items of the same
    /// titles, closed).
    @MainActor
    private func statusMenuItem(_ app: XCUIApplication, _ predicate: NSPredicate) -> XCUIElement {
        let status = app.statusItems["statusItem"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let query = app.menuItems.matching(predicate)
        let found = ElementBox()
        let hittable = NSPredicate { _, _ in
            MainActor.assumeIsolated {
                found.element = query.allElementsBoundByIndex.first(where: \.isHittable)
                return found.element != nil
            }
        }
        let opened = app.opensStatusMenu { status.click() } showing: {
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: nil)], timeout: 3) == .completed
        }
        XCTAssertTrue(opened, "\(predicate)")
        return found.element ?? query.firstMatch
    }

    @MainActor
    private func statusMenuItem(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        statusMenuItem(app, NSPredicate(format: "title == %@", title))
    }

    /// Quits through the menu bar item's Quit item, a quit like a logout's.
    @MainActor
    private func quit(_ app: XCUIApplication) {
        statusMenuItem(app, NSPredicate(format: "title BEGINSWITH 'Quit'")).click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    }
}

/// The element a polling predicate found.
@MainActor
private final class ElementBox {
    var element: XCUIElement?
}
