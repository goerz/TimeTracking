// XCUIApplication+TimeTracking: the Debug Mac app as the UI tests launch it
// (architecture.md §3.3).

import XCTest

@MainActor
extension XCUIApplication {
    /// The Debug app with `-UITesting YES`, a fixture, and a fixed clock;
    /// `reset` adds `-ResetState YES`.
    static func timeTracking(fixture: String = "small", reset: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "YES", "-Fixture", fixture] + (reset ? ["-ResetState", "YES"] : []) + extra
        app.launchEnvironment["TIMETRACKING_NOW"] = "2024-03-14T10:00:00"
        return app
    }

    /// Launches, answers the first-launch alert with Later if it shows, and
    /// waits for the main window's Timer task field.
    func launchPastOnboarding() {
        launch()
        let later = buttons["onboarding.later"]
        if later.waitForExistence(timeout: 5) {
            later.click()
        }
        XCTAssertTrue(textFields["timer.taskField"].waitForExistence(timeout: 10))
    }

    /// The main window, by its identifier (`MainWindowSetup.sceneID` in the
    /// app, kept as "planner" so saved window state carries over).
    var mainWindow: XCUIElement {
        windows["planner"]
    }

    /// Window › Mini Timer, chosen from the menu (another app on the test
    /// Mac may hold ⌥⌘R); returns the Mini Timer window once it is key.
    /// Opens the status item's menu with `open` until `showing` holds, at
    /// most three times. While a status menu is open the accessibility tree
    /// sometimes leaves it out for as long as it stays open, though it is on
    /// screen; closing and opening it again brings it back. A menu that
    /// never opens still fails. `showing` waits by itself, with
    /// `waitForExistence` rather than `exists`: a query of the open menu can
    /// time out, which `exists` records as a failure of the test.
    func opensStatusMenu(_ open: () -> Void, showing: () -> Bool) -> Bool {
        for _ in 0 ..< 3 {
            open()
            if showing() {
                return true
            }
            typeKey(.escape, modifierFlags: [])
        }
        return false
    }

    func openMiniTimer() -> XCUIElement {
        let window = menuBars.firstMatch.menuBarItems["Window"]
        window.click()
        window.menus.firstMatch.menuItems["Mini Timer"].click()
        let mini = windows["timer"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        return mini
    }
}
