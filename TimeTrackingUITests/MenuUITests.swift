// The main menu in the real app: the same menus in both windows, items of
// the other window disabled, each window listed once (spec_timer_window.md §9).

import XCTest

final class MenuUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }

    private static let appMenus = ["File", "Edit", "View", "Timer", "Entry", "Project", "Window"]

    @MainActor
    func testTW35_sameMenusInBothWindows() {
        let app = XCUIApplication.timeTracking(reset: true)
        app.launchPastOnboarding()
        XCTAssertTrue(app.descendants(matching: .any)["timer.list"].waitForExistence(timeout: 5))

        // Timer window key.
        assertMenus(app)
        let window = items(app, menu: "Window")
        XCTAssertEqual(window.filter { $0.title == "Timer Window" }.count, 1)
        XCTAssertEqual(window.filter { $0.title == "Planner" }.count, 1)
        XCTAssertFalse(window.contains { $0.title == "Timer" })
        assertItem(app, menu: "Entry", item: "Set Project…", enabled: true)
        assertItem(app, menu: "Entry", item: "Move Earlier", enabled: false)
        assertItem(app, menu: "Project", item: "New Project…", enabled: false)
        assertItem(app, menu: "View", item: "Go to Today", enabled: false)
        assertItem(app, menu: "View", item: "Compact Mode", enabled: true)

        // Planner key, Calendar shown.
        app.typeKey("p", modifierFlags: [.command, .option])
        XCTAssertTrue(app.descendants(matching: .any)["planner.sidebar"].waitForExistence(timeout: 5))
        app.typeKey("2", modifierFlags: .command)
        assertMenus(app)
        assertItem(app, menu: "Entry", item: "Set Project…", enabled: false)
        assertItem(app, menu: "Entry", item: "Move Earlier", enabled: true)
        assertItem(app, menu: "Entry", item: "Edit Selection…", enabled: true)
        assertItem(app, menu: "View", item: "Go to Today", enabled: true)
        assertItem(app, menu: "View", item: "Compact Mode", enabled: false)
        assertItem(app, menu: "Project", item: "New Project…", enabled: false)
        app.terminate()
    }

    /// Every app menu is in the menu bar.
    @MainActor
    private func assertMenus(_ app: XCUIApplication) {
        let titles = app.menuBars.firstMatch.menuBarItems.allElementsBoundByIndex.map(\.title)
        for menu in Self.appMenus {
            XCTAssertTrue(titles.contains(menu), "missing menu \(menu) in \(titles)")
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
