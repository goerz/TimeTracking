// The main menu in the real app: the shared menus in both windows, the
// section menu only while the Planner is in front, each window listed once
// (spec_timer_window.md §9).

import XCTest

final class MenuUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }

    private static let sharedMenus = ["File", "Edit", "View", "Timer", "Window"]
    private static let sectionMenus = ["Project", "Calendar", "Report", "Activity"]

    @MainActor
    func testTW35_sectionMenuOnlyInThePlanner() {
        let app = XCUIApplication.timeTracking(reset: true)
        app.launchPastOnboarding()
        XCTAssertTrue(app.descendants(matching: .any)["timer.list"].waitForExistence(timeout: 5))

        // Timer window: the shared menus, no section menu, no Entry menu.
        assertMenus(app, sectionMenu: nil)
        let window = items(app, menu: "Window")
        XCTAssertEqual(window.filter { $0.title == "Timer" }.count, 1)
        XCTAssertEqual(window.filter { $0.title == "Planner" }.count, 1)
        XCTAssertFalse(window.contains { $0.title == "Timer Window" })
        assertItem(app, menu: "Timer", item: "Set Project…", enabled: true)
        assertItem(app, menu: "View", item: "Compact Mode", enabled: true)
        assertItem(app, menu: "View", item: "Go to Today", enabled: false)

        // Planner, Calendar: the Calendar menu, without the navigation keys.
        app.typeKey("p", modifierFlags: [.command, .option])
        XCTAssertTrue(app.descendants(matching: .any)["planner.sidebar"].waitForExistence(timeout: 5))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.menuBars.firstMatch.menuBarItems["Calendar"].waitForExistence(timeout: 5))
        assertMenus(app, sectionMenu: "Calendar")
        let calendar = items(app, menu: "Calendar")
        XCTAssertTrue(calendar.contains { $0.title == "Fill Day…" && $0.enabled })
        XCTAssertFalse(calendar.contains { $0.title == "Next Day" || $0.title == "Deselect" || $0.title == "Next Entry" })
        assertItem(app, menu: "Timer", item: "Set Project…", enabled: false)
        assertItem(app, menu: "View", item: "Go to Today", enabled: true)
        assertItem(app, menu: "View", item: "Previous Period", enabled: true)
        assertItem(app, menu: "View", item: "Compact Mode", enabled: false)

        // Planner, Projects: the Project menu, without Start Timer.
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.menuBars.firstMatch.menuBarItems["Project"].waitForExistence(timeout: 5))
        assertMenus(app, sectionMenu: "Project")
        let project = items(app, menu: "Project")
        XCTAssertTrue(project.contains { $0.title == "New Project…" && $0.enabled })
        XCTAssertFalse(project.contains { $0.title == "Start Timer" })

        // Back to the Timer window: the section menu goes.
        // Window › Timer, chosen from the menu: another app on the test Mac
        // may hold ⌥⌘R (as in TW-4).
        app.menuBars.firstMatch.menuBarItems["Window"].click()
        app.menuBars.firstMatch.menuBarItems["Window"].menus.firstMatch.menuItems["Timer"].click()
        XCTAssertTrue(app.menuBars.firstMatch.menuBarItems["Project"].waitForNonExistence(timeout: 5))
        assertMenus(app, sectionMenu: nil)
        app.terminate()
    }

    /// The shared menus are in the menu bar, and of the section menus only
    /// `sectionMenu`.
    @MainActor
    private func assertMenus(_ app: XCUIApplication, sectionMenu: String?) {
        let titles = app.menuBars.firstMatch.menuBarItems.allElementsBoundByIndex.map(\.title)
        for menu in Self.sharedMenus {
            XCTAssertTrue(titles.contains(menu), "missing menu \(menu) in \(titles)")
        }
        XCTAssertFalse(titles.contains("Entry"), "Entry menu in \(titles)")
        for menu in Self.sectionMenus {
            XCTAssertEqual(titles.contains(menu), menu == sectionMenu, "section menu \(menu) in \(titles)")
        }
    }

    /// The top-level items of a menu, read while it is open (SwiftUI updates
    /// a menu's items when it opens).
    @MainActor
    private func items(_ app: XCUIApplication, menu: String) -> [(title: String, enabled: Bool)] {
        let bar = app.menuBars.firstMatch.menuBarItems[menu]
        bar.click()
        let result = bar.menus.firstMatch.children(matching: .menuItem).allElementsBoundByIndex
            .map { (title: $0.title, enabled: $0.isEnabled) }
        app.typeKey(.escape, modifierFlags: [])
        return result
    }

    /// The item is listed, enabled or disabled as given.
    @MainActor
    private func assertItem(_ app: XCUIApplication, menu: String, item: String, enabled: Bool) {
        guard let found = items(app, menu: menu).first(where: { $0.title == item }) else {
            XCTFail("missing \(menu) › \(item)")
            return
        }
        XCTAssertEqual(found.enabled, enabled, "\(menu) › \(item)")
    }
}
