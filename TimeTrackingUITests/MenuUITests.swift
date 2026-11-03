// The main menu in the real app: one fixed set of object menus in every
// window, each item enabled by what it acts on, the Mini Timer listed once
// in Window (spec_timer.md §9).

import XCTest

final class MenuUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }

    private static let menus = ["File", "Edit", "View", "Timer", "Entry", "Project", "Window"]
    private static let formerSectionMenus = ["Calendar", "Report", "Activity"]

    @MainActor
    func testTM35_sameMenusEnabledByTheViewShown() {
        let app = XCUIApplication.timeTracking(reset: true)
        app.launchPastOnboarding()
        XCTAssertTrue(app.descendants(matching: .any)["timer.list"].waitForExistence(timeout: 5))

        // The main window's Timer: the Timer's entry commands, no project.
        assertMenus(app)
        assertItem(app, menu: "Entry", item: "Set Project…", enabled: true)
        assertItem(app, menu: "Project", item: "Edit Project…", enabled: false)
        assertItem(app, menu: "View", item: "Go to Today", enabled: false)
        assertItem(app, menu: "View", item: "Compact Mode", enabled: false)
        let window = items(app, menu: "Window")
        XCTAssertEqual(window.filter { $0.title == "Mini Timer" }.count, 1)
        XCTAssertFalse(window.contains { ["Timer", "Planner", "Timer Window"].contains($0.title) })
        // The main window, by the app's name, last (where macOS lists windows).
        let appName = app.menuBars.firstMatch.menuBarItems.element(boundBy: 1).title
        XCTAssertEqual(window.filter { $0.title == appName }.count, 1, "\(window.map(\.title))")
        XCTAssertEqual(window.last?.title, appName)

        // Calendar: its entry commands, without the navigation keys.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["calendar.view"].waitForExistence(timeout: 5))
        assertMenus(app)
        let entry = items(app, menu: "Entry")
        XCTAssertTrue(entry.contains { $0.title == "Duplicate to Next Day" && $0.enabled })
        XCTAssertFalse(entry.contains { $0.title == "Next Day" || $0.title == "Deselect" || $0.title == "Next Entry" })
        assertItem(app, menu: "Entry", item: "Set Project…", enabled: false)
        assertItem(app, menu: "View", item: "Go to Today", enabled: true)
        assertItem(app, menu: "View", item: "Previous Period", enabled: true)

        // Projects: the Project menu, without Start Timer (Timer › Start Timer).
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["projects.table"].waitForExistence(timeout: 5))
        let project = items(app, menu: "Project")
        XCTAssertTrue(project.contains { $0.title == "Edit Project…" })
        XCTAssertFalse(project.contains { $0.title == "Start Timer" })
        XCTAssertTrue(items(app, menu: "File").contains { $0.title == "New Project…" && $0.enabled })

        // The Mini Timer: the same menus; its window options enabled.
        _ = app.openMiniTimer()
        assertMenus(app)
        assertItem(app, menu: "View", item: "Compact Mode", enabled: true)
        assertItem(app, menu: "Entry", item: "Set Project…", enabled: true)
        app.terminate()
    }

    /// The object menus are in the menu bar, and none of the former section menus.
    @MainActor
    private func assertMenus(_ app: XCUIApplication) {
        let titles = app.menuBars.firstMatch.menuBarItems.allElementsBoundByIndex.map(\.title)
        for menu in Self.menus {
            XCTAssertTrue(titles.contains(menu), "missing menu \(menu) in \(titles)")
        }
        for menu in Self.formerSectionMenus {
            XCTAssertFalse(titles.contains(menu), "section menu \(menu) in \(titles)")
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
