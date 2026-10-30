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
    private func launch(fixture: String = "small", reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "YES", "-Fixture", fixture] + (reset ? ["-ResetState", "YES"] : [])
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
        XCTAssertFalse(app.staticTexts["timer.placeholder"].exists)
        app.terminate()
    }

    @MainActor
    func testTW1_collapseBelowThreshold() {
        let app = launch()
        let window = app.windows.firstMatch
        let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0))
        // Drag the bottom edge up to a 190 pt tall window: it snaps to the bar.
        let height = window.frame.height
        bottom.press(forDuration: 0.2, thenDragTo: bottom.withOffset(CGVector(dx: 0, dy: -(height - 190))))
        XCTAssertEqual(window.frame.height, 88, accuracy: 2)
        XCTAssertFalse(app.descendants(matching: .any)["timer.list"].exists)
        // Dragging to 250 pt snaps to 300 pt and shows the list.
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0))
        edge.press(forDuration: 0.2, thenDragTo: edge.withOffset(CGVector(dx: 0, dy: 162)))
        XCTAssertEqual(window.frame.height, 300, accuracy: 2)
        app.terminate()
    }

    @MainActor
    func testTW2_compactModeShortcut() {
        let app = launch()
        let window = app.windows.firstMatch
        let full = window.frame
        app.typeKey("m", modifierFlags: [.command, .shift])
        XCTAssertEqual(window.frame.height, 88, accuracy: 2)
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
        let app = launch()
        app.typeKey("r", modifierFlags: [.option, .command])
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.typeKey("r", modifierFlags: [.option, .command])
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        // The task field has keyboard focus: typing goes into it.
        app.typeText("Focus")
        XCTAssertEqual(app.textFields["timer.taskField"].value as? String, "Focus")
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
        let toggle = app.checkBoxes["settings.showDockIcon"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        // The Dock shows a running regular app's tile under its name.
        let dock = XCUIApplication(bundleIdentifier: "com.apple.dock")
        let tile = dock.descendants(matching: .any).matching(NSPredicate(format: "label == %@", app.label)).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        toggle.click()
        // Accessory: no tile, the app stays in front, and the settings window stays key.
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: tile)
        wait(for: [gone], timeout: 5)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(toggle.isHittable)
        toggle.click()
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? Int, 1)
        app.terminate()
    }

    /// The Debug agents inside the app bundles next to the test runner.
    private static func debugAgents() -> [URL] {
        let fileManager = FileManager.default
        var products = Bundle(for: Self.self).bundleURL
        while products.pathComponents.count > 1, !products.lastPathComponent.hasSuffix("-Runner.app") {
            products.deleteLastPathComponent()
        }
        products.deleteLastPathComponent()
        let apps = (try? fileManager.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)) ?? []
        return apps.filter { $0.pathExtension == "app" }.flatMap { app in
            let loginItems = app.appending(path: "Contents/Library/LoginItems")
            let agents = (try? fileManager.contentsOfDirectory(at: loginItems, includingPropertiesForKeys: nil)) ?? []
            return agents.flatMap { agent in
                let macOS = agent.appending(path: "Contents/MacOS")
                return (try? fileManager.contentsOfDirectory(at: macOS, includingPropertiesForKeys: nil)) ?? []
            }
        }
    }

    @MainActor
    func testARCH8_enableTrackerRegisters() {
        // Whatever happens below, the Debug agent ends unregistered
        // (the agent's --unregister, as make mac-debug-unregister runs it).
        addTeardownBlock {
            for agent in Self.debugAgents() {
                let process = Process()
                process.executableURL = agent
                process.arguments = ["--unregister"]
                try? process.run()
                process.waitUntilExit()
            }
        }
        let app = launch()
        app.typeKey(",", modifierFlags: .command)
        let trackerTab = app.toolbars.buttons["Tracker"]
        XCTAssertTrue(trackerTab.waitForExistence(timeout: 5))
        trackerTab.click()
        let button = app.buttons["tracker.button"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(button.title, "Enable Tracker")
        button.click()
        let registered = NSPredicate(format: "title IN %@", ["Disable Tracker", "Open Login Items"])
        expectation(for: registered, evaluatedWith: button)
        waitForExpectations(timeout: 10)
        // Leave the Debug agent unregistered.
        if button.title == "Disable Tracker" {
            button.click()
            app.buttons["Disable Tracker"].firstMatch.click()
        }
        app.terminate()
    }
}
