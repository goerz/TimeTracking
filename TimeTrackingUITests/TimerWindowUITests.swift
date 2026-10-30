// What only real windows show: the Timer window, the menu bar item, the
// settings window (spec_timer_window.md, spec_menubar.md, spec_architecture.md §8).

import XCTest

final class TimerWindowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }

    /// The app on the fixture at the fixed test time, onboarding answered.
    @MainActor
    private func launch(fixture: String = "small", reset: Bool = true, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "YES", "-Fixture", fixture] + (reset ? ["-ResetState", "YES"] : []) + arguments
        app.launchEnvironment["TIMETRACKING_NOW"] = "2024-03-14T10:00:00"
        app.launch()
        let later = app.buttons["onboarding.later"]
        if later.waitForExistence(timeout: 5) {
            later.click()
        }
        XCTAssertTrue(app.textFields["timer.taskField"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func testARCH17_fixtureShowsDataWithoutDiskOrCloudKit() {
        let app = launch(fixture: "small")
        // The small fixture has entries today and on earlier days.
        XCTAssertTrue(app.descendants(matching: .any)["timer.list"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "timer.row").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["timer.placeholder"].exists)
        app.terminate()
    }

    @MainActor
    func testTW1_collapseBelowThreshold() {
        let app = launch()
        let window = app.windows.firstMatch
        // Just inside the bottom edge: the resize area, not the desktop below.
        // On the Mac only `click(forDuration:thenDragTo:)` drags; `press` does not.
        let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0)).withOffset(CGVector(dx: 0, dy: -1))
        // Drag the bottom edge up to a 190 pt tall window: it snaps to the bar.
        let height = window.frame.height
        bottom.click(forDuration: 0.2, thenDragTo: bottom.withOffset(CGVector(dx: 0, dy: -(height - 190))))
        XCTAssertEqual(window.frame.height, 106, accuracy: 2)
        XCTAssertFalse(app.descendants(matching: .any)["timer.list"].exists)
        // Dragging to 250 pt snaps to 300 pt and shows the list.
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0)).withOffset(CGVector(dx: 0, dy: -1))
        edge.click(forDuration: 0.2, thenDragTo: edge.withOffset(CGVector(dx: 0, dy: 250 - window.frame.height)))
        XCTAssertEqual(window.frame.height, 300, accuracy: 2)
        app.terminate()
    }

    @MainActor
    func testTW2_compactModeShortcut() {
        let app = launch()
        let window = app.windows.firstMatch
        let full = window.frame
        app.typeKey("m", modifierFlags: [.command, .shift])
        XCTAssertEqual(window.frame.height, 106, accuracy: 2)
        XCTAssertEqual(window.frame.minY, full.minY, accuracy: 2)
        app.typeKey("m", modifierFlags: [.command, .shift])
        XCTAssertEqual(window.frame.height, full.height, accuracy: 2)
        app.terminate()
    }

    @MainActor
    func testTW3_restoresFrameAndPin() {
        var app = launch()
        let pin = app.buttons["timer.pinButton"]
        pin.click()
        XCTAssertEqual(pin.value as? String, "pinned")
        app.typeKey("m", modifierFlags: [.command, .shift])
        let frame = app.windows.firstMatch.frame
        app.terminate()
        app = launch(reset: false)
        XCTAssertEqual(app.buttons["timer.pinButton"].value as? String, "pinned")
        // Compact mode, origin, and size all come back.
        let restored = app.windows.firstMatch.frame
        XCTAssertEqual(restored.height, frame.height, accuracy: 2)
        XCTAssertEqual(restored.width, frame.width, accuracy: 2)
        XCTAssertEqual(restored.minX, frame.minX, accuracy: 2)
        XCTAssertEqual(restored.minY, frame.minY, accuracy: 2)
        XCTAssertLessThan(restored.height, 200)
        app.terminate()
    }

    @MainActor
    func testTW4_showHideShortcut() {
        // A recorded ⌃⌥⌘R: another app on the test Mac may hold ⌥⌘R and take
        // the activation. StatusItemTests checks the ⌥⌘R default.
        let recorded = #""{\"carbonKeyCode\":15,\"carbonModifiers\":6400}""#
        let app = launch(fixture: "empty", arguments: ["-KeyboardShortcuts_showHideTimer", recorded])
        let shortcut: XCUIElement.KeyModifierFlags = [.control, .option, .command]
        // The window is key: the shortcut hides the app.
        app.typeKey("r", modifierFlags: shortcut)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        // System-wide: pressed in another app, it brings the window back.
        XCUIApplication(bundleIdentifier: "com.apple.finder").typeKey("r", modifierFlags: shortcut)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        // The task field has keyboard focus. (Synthesized typing right after
        // the shortcut loses keys under XCUITest; TW-6 and TW-9 cover typing.)
        let field = app.textFields["timer.taskField"]
        wait(for: [expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: field)], timeout: 5)
        app.terminate()
    }

    @MainActor
    func testTW6_startAndStopFromTheBar() {
        let app = launch(fixture: "empty")
        let field = app.textFields["timer.taskField"]
        field.click()
        field.typeText("Clarify noise model\r")
        XCTAssertTrue(app.buttons["timer.stopButton"].waitForExistence(timeout: 5))
        app.buttons["timer.stopButton"].click()
        XCTAssertTrue(app.buttons["timer.startButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "timer.row").firstMatch.exists)
        app.terminate()
    }

    @MainActor
    func testTW9_atTriggerOpensPicker() {
        let app = launch()
        let field = app.textFields["timer.taskField"]
        field.click()
        field.typeText("Review @no")
        XCTAssertTrue(app.descendants(matching: .any)["picker"].waitForExistence(timeout: 5))
        // Focus stays in the field: typing extends the search.
        app.typeText("i")
        XCTAssertEqual(field.value as? String, "Review @noi")
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.descendants(matching: .any)["picker"].exists)
        XCTAssertEqual(field.value as? String, "Review @noi")
        // Deleting the @ and typing it again reopens it; Return assigns the
        // highlighted project and removes "@noi".
        for _ in 0 ..< 4 {
            field.typeKey(.delete, modifierFlags: [])
        }
        field.typeText("@noi")
        XCTAssertTrue(app.descendants(matching: .any)["picker"].waitForExistence(timeout: 5))
        field.typeKey(.return, modifierFlags: [])
        XCTAssertFalse(app.descendants(matching: .any)["picker"].waitForExistence(timeout: 1))
        XCTAssertEqual(field.value as? String, "Review")
        app.terminate()
    }

    @MainActor
    func testMB13_bothClicksOpenTheMenu() {
        let app = launch()
        let item = app.statusItems["statusItem"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        XCTAssertTrue(app.menuItems["New"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        item.rightClick()
        XCTAssertTrue(app.menuItems["New"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    @MainActor
    func testMB10_dockIconSwitchKeepsWindowKey() {
        let app = launch()
        app.typeKey(",", modifierFlags: .command)
        let toggle = app.descendants(matching: .any)["settings.showDockIcon"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        // Accessory: the app stays in front and the settings window stays usable.
        XCTAssertTrue(app.windows.firstMatch.exists)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? Int, 0)
        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 1)
        app.terminate()
    }

    /// The Tracker pane's button in the open settings window.
    @MainActor
    private func trackerButton(_ app: XCUIApplication) -> XCUIElement {
        app.typeKey(",", modifierFlags: .command)
        let trackerTab = app.toolbars.buttons["Tracker"]
        XCTAssertTrue(trackerTab.waitForExistence(timeout: 5))
        trackerTab.click()
        let button = app.buttons["tracker.button"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        return button
    }

    /// Disable Tracker and its confirmation, if the agent is registered.
    @MainActor
    private func disableIfRegistered(_ app: XCUIApplication, _ button: XCUIElement) {
        guard button.label == "Disable Tracker" else {
            return
        }
        button.click()
        let sheet = app.sheets.buttons["Disable Tracker"]
        let confirm = sheet.waitForExistence(timeout: 5) ? sheet : app.dialogs.buttons["Disable Tracker"]
        guard confirm.waitForExistence(timeout: 5) else {
            return
        }
        confirm.click()
        let off = expectation(for: NSPredicate(format: "label == %@", "Enable Tracker"), evaluatedWith: button)
        wait(for: [off], timeout: 10)
    }

    @MainActor
    func testARCH8_enableTrackerRegisters() {
        // Whatever fails below, the Debug agent ends unregistered.
        addTeardownBlock { @MainActor in
            let app = self.launch(reset: false)
            self.disableIfRegistered(app, self.trackerButton(app))
            app.terminate()
        }
        let app = launch()
        let button = trackerButton(app)
        XCTAssertEqual(button.label, "Enable Tracker")
        button.click()
        let registered = NSPredicate(format: "label IN %@", ["Disable Tracker", "Open Login Items"])
        let done = expectation(for: registered, evaluatedWith: button)
        wait(for: [done], timeout: 10)
        disableIfRegistered(app, button)
        XCTAssertEqual(button.label, "Enable Tracker")
        app.terminate()
    }

    /// The Debug agent embedded in the Debug app next to the test runner
    /// (`<APP_NAME> Debug.app/…/TimeTrackingAgent Debug.app`, spec_architecture.md §2.2).
    private static func debugAgentExecutable() throws -> URL {
        let products = Bundle.main.bundleURL.deletingLastPathComponent()
        let agent = "Contents/Library/LoginItems/TimeTrackingAgent Debug.app/Contents/MacOS/TimeTrackingAgent"
        let apps = try FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)
        return try XCTUnwrap(apps.filter { $0.lastPathComponent.hasSuffix(" Debug.app") }.map { $0.appending(path: agent) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    @MainActor
    func testARCH8_agentUnregisterFlagRemovesTheRegistration() throws {
        addTeardownBlock { @MainActor in
            let app = self.launch(reset: false)
            self.disableIfRegistered(app, self.trackerButton(app))
            app.terminate()
        }
        let agent = try Self.debugAgentExecutable()
        let app = launch()
        let button = trackerButton(app)
        button.click()
        let registered = NSPredicate(format: "label IN %@", ["Disable Tracker", "Open Login Items"])
        wait(for: [expectation(for: registered, evaluatedWith: button)], timeout: 10)
        // What make mac-debug-unregister runs.
        let process = Process()
        process.executableURL = agent
        process.arguments = ["--unregister"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        // The pane re-reads the registration every 5 s.
        let off = expectation(for: NSPredicate(format: "label == %@", "Enable Tracker"), evaluatedWith: button)
        wait(for: [off], timeout: 15)
        app.terminate()
    }
}
