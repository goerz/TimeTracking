// Full and compact mode, restoration, and the list (spec_timer_window.md §1, §3).

import AppKit
import CoreGraphics
import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct TimerWindowTests {
    /// A frame with its top-left corner at (100, 900).
    private func frame(width: CGFloat = 440, height: CGFloat) -> CGRect {
        CGRect(x: 100, y: 900 - height, width: width, height: height)
    }

    @Test("TW-1 a drag released at 199 pt snaps to 106, at 200 or 250 pt to 300, width as dragged, top-left fixed")
    func snapping() {
        let compact = TimerWindowGeometry.snapped(frame(width: 500, height: 199))
        #expect(compact.height == 106)
        #expect(compact.width == 500)
        #expect(compact.maxY == 900 && compact.minX == 100)
        #expect(TimerWindowGeometry.snapped(frame(height: 200)).height == 300)
        #expect(TimerWindowGeometry.snapped(frame(height: 250)).height == 300)
        #expect(TimerWindowGeometry.snapped(frame(height: 106)).height == 106)
        #expect(TimerWindowGeometry.snapped(frame(height: 560)).height == 560)
        #expect(TimerWindowGeometry.snapped(frame(width: 300, height: 560)).width == 400)
        #expect(TimerWindowGeometry.isCompact(height: 199))
        #expect(!TimerWindowGeometry.isCompact(height: 200))
    }

    @Test("TW-2 ⇧⌘M toggles between the remembered compact and full frames at the current top-left corner")
    func toggling() {
        let full = frame(width: 500, height: 620)
        let compact = CGRect(x: 0, y: 0, width: 420, height: 106)
        let toCompact = TimerWindowGeometry.toggled(full, fullFrame: full, compactFrame: compact)
        #expect(toCompact == CGRect(x: 100, y: 900 - 106, width: 420, height: 106))
        let back = TimerWindowGeometry.toggled(toCompact, fullFrame: full, compactFrame: compact)
        #expect(back == CGRect(x: 100, y: 900 - 620, width: 500, height: 620))
        // Without remembered frames, the defaults.
        #expect(TimerWindowGeometry.toggled(full, fullFrame: nil, compactFrame: nil).size == CGSize(width: 480, height: 106))
    }

    @Test("TW-3 the frame at quit is restored unless less than 100 × 44 pt is on a screen; the pin persists")
    func restoration() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let stored = CGRect(x: 200, y: 300, width: 440, height: 88)
        #expect(TimerWindowGeometry.restored(stored, screens: [screen], mainScreen: screen) == stored)
        // Only 60 pt visible: centered on the main screen, size kept.
        let offscreen = CGRect(x: 1380, y: 300, width: 440, height: 88)
        let moved = TimerWindowGeometry.restored(offscreen, screens: [screen], mainScreen: screen)
        #expect(moved == CGRect(x: 500, y: 406, width: 440, height: 88))
        #expect(TimerWindowGeometry.restored(nil, screens: [screen], mainScreen: screen).size == TimerWindowGeometry.defaultFullSize)
        // The pin is a device setting that survives a new settings object.
        let settings = AppSettings.ephemeral()
        settings.timerPinned = true
        #expect(AppSettings(device: settings.device).timerPinned)
        settings.device[.timerFrame] = StoredFrame(stored)
        #expect(AppSettings(device: settings.device).device[.timerFrame]?.rect == stored)
    }

    @Test("TW-3 a relaunched Timer window takes the compact mode, frame, and pin from quit; pinned it floats above normal windows")
    func relaunch() async throws {
        let test = try await TestApp()
        let screen = try #require(NSScreen.main?.visibleFrame)
        let quitFrame = CGRect(x: screen.minX + 120, y: screen.minY + 140, width: 420, height: TimerWindowGeometry.barHeight)
        // State at quit: compact at quitFrame, pinned.
        test.app.settings.device[.timerFrame] = StoredFrame(quitFrame)
        test.app.setPinned(true)
        // Relaunch: new settings over the same defaults, a new window.
        let settings = AppSettings(device: test.app.settings.device)
        #expect(settings.timerPinned)
        let controller = TimerWindowController(settings: settings)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 440, height: 620),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        controller.attach(window)
        #expect(window.frame == quitFrame)
        #expect(controller.isCompact)
        // .floating is above every app's normal-level windows, the other app's key window included.
        #expect(window.level == .floating)
        #expect(window.level.rawValue > NSWindow.Level.normal.rawValue)
        controller.applyPin(false)
        #expect(window.level == .normal)
        // Unpinned at quit: the next launch is at the normal level.
        test.app.settings.timerPinned = false
        let unpinned = TimerWindowController(settings: AppSettings(device: test.app.settings.device))
        let second = NSWindow(contentRect: quitFrame, styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        second.isReleasedWhenClosed = false
        unpinned.attach(second)
        #expect(second.level == .normal)
    }

    @Test("TW-15 two identical consecutive entries are two rows; 14 days with entries, Load Earlier appends 14")
    func listDays() async throws {
        let test = try await TestApp()
        for offset in 1 ... 30 {
            let day = TrackingDay(year: 2024, month: 3, day: 14).adding(days: -offset)
            try await test.entry("Day \(offset)", from: "\(day)T08:00", to: "\(day)T08:30")
        }
        try await test.entry("Same", from: "09:00", to: "09:10")
        try await test.entry("Same", from: "09:10", to: "09:20")
        let list = test.app.list
        #expect(list.days.count == 14)
        #expect(list.days[0].rows.map(\.entry.task) == ["Same", "Same"])
        #expect(list.canLoadMore)
        await list.loadMore()
        #expect(list.days.count == 28)
        await list.loadMore()
        #expect(list.days.count == 31)
        #expect(!list.canLoadMore)
        #expect(list.title(for: TrackingDay(year: 2024, month: 3, day: 14)) == "Today")
        #expect(list.title(for: TrackingDay(year: 2024, month: 3, day: 13)) == "Yesterday")
        #expect(list.title(for: TrackingDay(year: 2024, month: 3, day: 12)) == "Tue, Mar 12")
        #expect(list.title(for: TrackingDay(year: 2023, month: 10, day: 27)) == "Fri, Oct 27, 2023")
    }

    @Test("TW-16 arrows move the selection, Return edits, ⌘O continues it, ⌘⌫ deletes after the alert and ⌘Z restores, Escape clears")
    func listInputs() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Household"])
        try await test.entry("Order toner", projects[0], from: "08:00", to: "08:25")
        try await test.entry("Plan", from: "09:00", to: "09:30")
        let list = test.app.list
        list.moveSelection(by: 1)
        #expect(list.selection == list.rows[0].id)
        list.moveSelection(by: 1)
        let toner = list.rows[1]
        #expect(list.selection == toner.id)
        list.moveSelection(by: 1)
        #expect(list.selection == toner.id)
        // Return or click: the edit popover.
        test.app.presentation.listFocused = true
        test.app.editEntry()
        #expect(test.app.presentation.editing == toner.id)
        // ⌘O continues the selection while the Timer window is key.
        await test.app.continueCommand(timerKey: true)
        #expect(test.app.timer.running?.task == "Order toner")
        await test.app.timer.stop()
        // ⌘⌫: the alert, then delete; ⌘Z restores.
        list.selection = toner.id
        let alert = try #require(list.deleteAlert())
        #expect(alert.message == "Delete this entry? 0:25:00, Household")
        await list.delete(toner.id)
        #expect(!list.rows.contains { $0.id == toner.id })
        await test.undoLast()
        #expect(list.rows.contains { $0.id == toner.id })
        // Escape clears; ⌘↑ scrolls to the top.
        list.selection = toner.id
        list.clearSelection()
        #expect(list.selection == nil)
        let before = list.scrollToTopRequest
        list.scrollToTop()
        #expect(list.scrollToTopRequest == before + 1)
    }

    @Test("TW-16 a click selects and edits, a double-click continues, the context menu has Continue, Edit…, Delete…")
    func rowPointerInputs() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Household"])
        try await test.entry("Order toner", projects[0], from: "08:00", to: "08:25")
        try await test.entry("Plan", from: "09:00", to: "09:30")
        let list = test.app.list
        let toner = try #require(list.rows.first { $0.entry.task == "Order toner" })
        test.app.rowClicked(toner.id)
        #expect(list.selection == toner.id)
        #expect(test.app.presentation.editing == toner.id)
        test.app.presentation.editing = nil
        await test.app.rowDoubleClicked(toner.id).value
        #expect(test.app.timer.running?.task == "Order toner")
        #expect(test.app.timer.running?.projectID == projects[0].id)
        await test.app.timer.stop()
        #expect(TimerRowMenuItem.allCases.map(\.title) == ["Continue", "Edit…", "Delete…"])
        let plan = try #require(list.rows.first { $0.entry.task == "Plan" })
        await test.app.performRowMenu(.continueEntry, on: plan.id)?.value
        #expect(test.app.timer.running?.task == "Plan")
        await test.app.timer.stop()
        #expect(test.app.performRowMenu(.edit, on: plan.id) == nil)
        #expect(test.app.presentation.editing == plan.id)
        #expect(list.selection == plan.id)
        test.app.performRowMenu(.delete, on: toner.id)
        #expect(test.app.timer.alert == list.deleteAlert(for: toner.id))
        #expect(test.app.timer.alert?.message == "Delete this entry? 0:25:00, Household")
    }

    @Test("TW-17 ⌘F with noise leaves only matching entries, and day totals sum them; Escape clears the filter")
    func filter() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Noise Model", "Website"])
        try await test.entry("Draft", projects[0], from: "08:00", to: "08:10")
        try await test.entry("Deploy", projects[1], from: "08:10", to: "08:40")
        try await test.entry("Fix noise plot", projects[1], from: "08:40", to: "08:45")
        let list = test.app.list
        list.showFilter()
        list.filter = "noise"
        await list.reload()
        #expect(list.rows.map(\.entry.task) == ["Fix noise plot", "Draft"])
        #expect(list.days[0].totalSeconds(at: test.clock.now) == 900)
        await list.hideFilter()
        #expect(list.rows.count == 3)
        #expect(list.filter.isEmpty && !list.isFilterVisible)
    }
}
