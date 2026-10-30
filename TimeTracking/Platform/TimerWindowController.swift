// TimerWindowController: the Timer window's AppKit side: frames, compact
// snapping, the pin's window level, hiding on close, restoration
// (spec_timer_window.md §1, spec_architecture.md §4.2).

import AppKit
import SwiftUI
import TimeTrackingCore

/// Owns the Timer window's `NSWindow` once SwiftUI created it.
final class TimerWindowController: NSObject, TimerWindowControlling {
    private(set) weak var window: NSWindow?
    private let settings: AppSettings
    private var observers: [NSObjectProtocol] = []
    private var closeInterceptor: WindowCloseInterceptor?
    /// Whether the window should stay hidden after SwiftUI shows it at launch.
    var hideOnAttach = false
    /// Called when the window becomes key or resigns (menus).
    var onKeyChange: () -> Void = {}

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isCompact: Bool {
        TimerWindowGeometry.isCompact(height: window?.frame.height ?? TimerWindowGeometry.defaultFullSize.height)
    }

    var isKey: Bool {
        window?.isKeyWindow ?? false
    }

    /// Takes over `window` (called once its content is installed).
    func attach(_ window: NSWindow) {
        guard self.window !== window else {
            return
        }
        self.window = window
        window.identifier = NSUserInterfaceItemIdentifier("timer")
        applyTestingAppearance()
        window.minSize = CGSize(width: TimerWindowGeometry.minimumWidth, height: TimerWindowGeometry.barHeight)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        let screens = NSScreen.screens.map(\.visibleFrame)
        let main = NSScreen.main?.visibleFrame ?? screens.first ?? .zero
        let stored = settings.device[.timerFrame]?.rect
        window.setFrame(TimerWindowGeometry.restored(stored, screens: screens, mainScreen: main), display: false)
        applyPin(settings.timerPinned)
        let interceptor = WindowCloseInterceptor(original: window.delegate)
        closeInterceptor = interceptor
        window.delegate = interceptor
        observe(window)
        if hideOnAttach {
            hideOnAttach = false
            window.orderOut(nil)
        }
    }

    /// `-UITesting YES -UITestingAppearance dark` (or `light`) sets the
    /// app's appearance for screenshots without the system setting.
    private func applyTestingAppearance() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "UITesting"), let name = defaults.string(forKey: "UITestingAppearance") else {
            return
        }
        NSApp.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
    }

    private func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.liveResizeEnded() }
            },
            center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveFrame() }
            },
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onKeyChange() }
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onKeyChange() }
            },
        ]
    }

    /// A drag ended: snap per §1.1.
    private func liveResizeEnded() {
        guard let window else {
            return
        }
        let target = TimerWindowGeometry.snapped(window.frame)
        if target != window.frame {
            window.setFrame(target, display: true, animate: true)
        }
        saveFrame()
    }

    /// Remembers the frame and the current mode's frame.
    private func saveFrame() {
        guard let window else {
            return
        }
        let frame = StoredFrame(window.frame)
        settings.device[.timerFrame] = frame
        if isCompact {
            settings.device[.timerCompactFrame] = frame
        } else {
            settings.device[.timerFullFrame] = frame
        }
    }

    func toggleCompact() {
        guard let window else {
            return
        }
        saveFrame()
        let target = TimerWindowGeometry.toggled(
            window.frame,
            fullFrame: settings.device[.timerFullFrame]?.rect,
            compactFrame: settings.device[.timerCompactFrame]?.rect
        )
        window.setFrame(target, display: true, animate: true)
        settings.device[.timerFrame] = StoredFrame(target)
    }

    /// `.floating`: above every app's normal windows, not joining other
    /// apps' full-screen spaces, without activating the window.
    func applyPin(_ pinned: Bool) {
        window?.level = pinned ? .floating : .normal
    }

    func show() {
        guard let window else {
            return
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        NSApp.hide(nil)
    }
}

/// Keeps the Timer window alive when closed: SwiftUI's delegate receives
/// everything else.
private final class WindowCloseInterceptor: NSObject, NSWindowDelegate {
    /// Only read by the Objective-C runtime on the main thread.
    nonisolated(unsafe) weak var original: NSWindowDelegate?

    init(original: NSWindowDelegate?) {
        self.original = original
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    override nonisolated func responds(to selector: Selector?) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override nonisolated func forwardingTarget(for _: Selector?) -> Any? {
        original
    }
}

/// Hands the hosting `NSWindow` to a closure once the view is in a window.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = AccessorView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class AccessorView: NSView {
        var onWindow: (NSWindow) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindow(window)
            }
        }
    }
}
