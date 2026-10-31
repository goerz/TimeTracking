// TimerWindowView: the Timer's content, in the main window and in the Mini
// Timer (spec_timer_window.md §1 to §3, §6.3).

import SwiftUI
import TimeTrackingCore

/// The bar, and the list at or above the threshold height.
struct TimerWindowView: View {
    /// The main window's Timer item, laid out as the iPad's Timer tab (the
    /// bar beside the list above 900 pt, above it below), without the pin
    /// or compact mode; otherwise the Mini Timer.
    var embedded = false
    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager
    @Environment(\.appearsActive) private var appearsActive
    /// The hidden title bar's height. The hosting view adds it to the
    /// content's minimum, so the content asks for that much less.
    @State private var titleBarInset: CGFloat = 0
    /// The embedded bar's leading edge, for the suggestion popup.
    @State private var barMinX: CGFloat = 0

    /// The iPad's width for two columns (`TimerScreen.twoColumnWidth`).
    static let twoColumnWidth: CGFloat = 900

    /// This view's own state: the main window's or the Mini Timer's.
    private var view: TimerUIState {
        embedded ? app.mainTimer : app.miniTimer
    }

    var body: some View {
        @Bindable var view = view
        return GeometryReader { geometry in
            if embedded {
                embeddedLayout(width: geometry.size.width)
            } else {
                windowLayout(height: geometry.size.height)
            }
        }
        .frame(minWidth: TimerWindowGeometry.minimumWidth, minHeight: TimerWindowGeometry.barHeight - titleBarInset)
        .background(WindowAccessor { window in
            titleBarInset = window.frame.height - window.contentLayoutRect.height
        })
        .ignoresSafeArea(embedded ? [] : .all)
        .focusedSceneValue(\.timerWindowActive, true)
        .environment(view)
        .onAppear {
            view.list.undoManager = undoManager
        }
        .onChange(of: appearsActive, initial: true) { _, active in
            // The main window reports for itself, whatever it shows.
            if !embedded {
                app.windowActivated(.miniTimer, isKey: active, undoManager: undoManager)
            }
        }
        // The main window shows the Timer's alerts at its root, whatever it shows.
        .timerAlert(timer: app.timer, list: view.list, active: !embedded && app.alertWindow == .miniTimer)
        .sheet(item: idlePrompt) { _ in
            IdlePromptView()
        }
        .sheet(item: $view.dialogModel) { dialog in
            ProjectDialogView(model: dialog) { project in
                Task { await app.dialogFinished(project, in: view) }
            }
        }
        // The first-launch alert, once the window shows (AppKit, TrackerOnboardingAlert).
        .onChange(of: app.showsTrackerOnboarding, initial: true) { _, shows in
            if shows {
                app.presentTrackerOnboarding()
            }
        }
    }

    /// The main window's Timer tab: as the iPad's, two columns when wide.
    @ViewBuilder
    private func embeddedLayout(width: CGFloat) -> some View {
        if width > Self.twoColumnWidth {
            HStack(alignment: .top, spacing: 0) {
                embeddedBar
                    .frame(width: min(480, max(TimerWindowGeometry.minimumWidth, width * 0.4)))
                    .frame(maxHeight: .infinity, alignment: .top)
                Divider()
                TimerListView()
            }
        } else {
            VStack(spacing: 0) {
                embeddedBar
                Divider()
                TimerListView()
            }
        }
    }

    /// The bar without the title row, its editor popover, and the task
    /// field's suggestions.
    private var embeddedBar: some View {
        @Bindable var view = view
        return RunningEntryBar(showsTitleRow: false)
            .padding(.top, Design.Spacing.medium)
            .modifier(EntryEditorPopover(
                entry: app.timer.running,
                editing: $view.editing,
                store: app.store,
                clock: app.clock,
                taskMatching: true,
                arrowEdge: .bottom
            ) { await app.afterChange() })
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).minX
            } action: { minX in
                barMinX = minX
            }
            .overlay(alignment: .topLeading) {
                TaskFieldPopup()
                    .padding(.leading, view.taskFieldLeading - barMinX - Design.Spacing.medium)
                    .offset(y: Design.Spacing.medium + Design.CircleDiameter.bar + Design.Spacing.tight)
            }
            .zIndex(1)
    }

    /// The Mini Timer (the former Timer window), unchanged.
    private func windowLayout(height: CGFloat) -> some View {
        @Bindable var view = view
        return VStack(spacing: 0) {
            RunningEntryBar()
                .modifier(EntryEditorPopover(
                    entry: app.timer.running,
                    editing: $view.editing,
                    store: app.store,
                    clock: app.clock,
                    taskMatching: true,
                    arrowEdge: .bottom
                ) { await app.afterChange() })
                .zIndex(1)
            if !TimerWindowGeometry.isCompact(height: height) {
                Divider()
                TimerListView()
            }
        }
        .overlay(alignment: .topLeading) {
            TaskFieldPopup()
                .padding(.leading, view.taskFieldLeading - Design.Spacing.medium)
                .offset(y: RunningEntryBar.titleRowHeight + Design.CircleDiameter.bar + Design.Spacing.tight)
                .zIndex(2)
        }
    }

    /// The idle prompt is the Mini Timer's (the prompt brings it forward).
    private var idlePrompt: Binding<IdlePromptItem?> {
        Binding {
            embedded ? nil : app.idle.prompt.map { IdlePromptItem(prompt: $0) }
        } set: { _ in }
    }
}

/// The idle prompt as a sheet item.
struct IdlePromptItem: Identifiable {
    var prompt: IdlePrompt

    var id: Date {
        prompt.idleStart
    }
}

/// "You have been away" (spec_timer_window.md §6.3).
struct IdlePromptView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.window) {
            HStack(alignment: .top, spacing: Design.Spacing.large) {
                Image(systemName: SymbolName.idle)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Design.Spacing.tight) {
                    Text("You have been away").font(.headline)
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(app.idle.sinceText(at: app.clock.now)).accessibilityIdentifier("idle.since")
                    }
                    Text(app.idle.prompt?.runningText ?? "").foregroundStyle(.secondary).lineLimit(2)
                }
            }
            HStack {
                button(.split, key: "s", modifiers: .command)
                button(.discardAndContinue, key: "d", modifiers: [.command, .shift])
                button(.discard, key: "d", modifiers: .command)
                Spacer()
                Button(IdleOption.keep.title) { resolve(.keep) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("idle.keep")
            }
        }
        .padding(Design.Spacing.window)
        .frame(width: 480)
        .onKeyPress(.escape) {
            resolve(.keep)
            return .handled
        }
    }

    private func button(_ option: IdleOption, key: KeyEquivalent, modifiers: EventModifiers) -> some View {
        Button(option.title) { resolve(option) }
            .keyboardShortcut(key, modifiers: modifiers)
            .accessibilityIdentifier("idle.\(option.rawValue)")
    }

    private func resolve(_ option: IdleOption) {
        Task { await app.idle.resolve(option) }
    }
}

extension FocusedValues {
    // Set while the Timer window is key; the "Timer key" commands need it.
    // swiftlint:disable:next discouraged_optional_boolean
    @Entry var timerWindowActive: Bool?
}
