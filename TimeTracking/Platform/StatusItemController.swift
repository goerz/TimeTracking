// StatusItemController: the menu bar item and the Dock menu
// (spec_menubar.md §1, §2, §4, §5; spec_architecture.md §4.2).

import AppKit
import Observation
import TimeTrackingCore

/// The `NSStatusItem` with its `NSMenu`; renders `StatusItemPresenter`.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let app: AppModel
    private let item: NSStatusItem
    private let menu = NSMenu()
    private var tick: Timer?
    private var menuTick: Timer?
    private var isMenuOpen = false
    private var asleep = false

    init(app: AppModel) {
        self.app = app
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        // Not removable by ⌘-dragging, so an accessory app stays reachable.
        item.behavior = []
        item.button?.imagePosition = .imageLeading
        item.button?.setAccessibilityIdentifier("statusItem")
        menu.delegate = self
        menu.autoenablesItems = false
        // Both clicks and "Move focus to status menus" open the menu.
        item.menu = menu
        observe()
        render()
    }

    /// Re-renders whenever an observed input changes (running entry,
    /// Pomodoro, settings, warning), without waiting for a tick.
    private func observe() {
        withObservationTracking {
            _ = app.revision
            _ = app.statusState
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.render()
                self?.observe()
            }
        }
    }

    // MARK: Rendering

    func render() {
        let now = app.clock.now
        let content = StatusItemPresenter.content(app.statusState, at: now)
        guard let button = item.button else {
            return
        }
        button.image = Self.image(content.symbol, badge: content.badge)
        button.attributedTitle = NSAttributedString(
            string: content.title.isEmpty ? "" : content.title,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
        )
        button.imageHugsTitle = true
        button.setAccessibilityLabel(content.accessibilityLabel)
        button.setAccessibilityTitle(content.title)
        if isMenuOpen {
            rebuildMenu()
        }
        scheduleTick()
    }

    private func scheduleTick() {
        tick?.invalidate()
        tick = nil
        guard !asleep, let next = StatusItemPresenter.nextTick(app.statusState, after: app.clock.now, menuOpen: false) else {
            return
        }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    /// Sleep cancels the tick; wake re-renders from the clock and re-arms it.
    func setAsleep(_ asleep: Bool) {
        self.asleep = asleep
        if asleep {
            tick?.invalidate()
            tick = nil
        } else {
            render()
        }
    }

    static func image(_ symbol: String, badge: Bool) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else {
            return nil
        }
        guard badge else {
            base.isTemplate = true
            return base
        }
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: NSRect(x: 0, y: 1, width: 15, height: 15))
            if let mark = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil) {
                mark.draw(in: NSRect(x: rect.maxX - 9, y: 0, width: 9, height: 9))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Menu

    func menuWillOpen(_: NSMenu) {
        isMenuOpen = true
        rebuildMenu()
        // The header refreshes every second while open.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildMenu() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        menuTick = timer
    }

    func menuDidClose(_: NSMenu) {
        isMenuOpen = false
        menuTick?.invalidate()
        menuTick = nil
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        for entry in StatusItemPresenter.menu(app.statusState, at: app.clock.now) {
            menu.addItem(makeItem(entry))
        }
    }

    /// The Dock menu (`applicationDockMenu(_:)`).
    func dockMenu() -> NSMenu {
        let dock = NSMenu()
        dock.autoenablesItems = false
        for entry in StatusItemPresenter.dockMenu(app.statusState) {
            dock.addItem(makeItem(entry))
        }
        return dock
    }

    private func makeItem(_ entry: StatusMenuEntry) -> NSMenuItem {
        switch entry {
        case .separator:
            return .separator()
        case let .header(text):
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        case let .item(title, key, enabled, command):
            let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: key?.key ?? "")
            item.keyEquivalentModifierMask = key?.modifierFlags ?? []
            item.target = self
            item.isEnabled = enabled
            item.representedObject = CommandBox(command)
            return item
        }
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let command = (sender.representedObject as? CommandBox)?.command else {
            return
        }
        Task { await self.run(command) }
    }

    private func run(_ command: MenuCommand) async {
        switch command {
        case .openTrackerSettings: app.router?.openSettings(pane: .tracker)
        case .new: await app.newEntry()
        case .continueLatest: await app.continueLatest()
        case .stop: await app.stopEntry()
        case let .pomodoro(action): app.perform(action)
        case .showTimer: app.router?.showTimer(focusTask: false)
        case .openPlanner: app.router?.openPlanner()
        case .settings: app.router?.openSettings(pane: nil)
        case .quit: NSApp.terminate(nil)
        }
    }
}

/// A menu command as an Objective-C object.
private final class CommandBox: NSObject {
    let command: MenuCommand

    init(_ command: MenuCommand) {
        self.command = command
    }
}
