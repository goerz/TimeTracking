// TimerWindowView: the Timer window's content (spec_timer_window.md §1 to §3, §6.3).

import SwiftUI
import TimeTrackingCore

/// The bar, and the list at or above the threshold height.
struct TimerWindowView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager
    @State private var runningEditor: EntryEditorModel?
    /// The hidden title bar's height. The hosting view adds it to the
    /// content's minimum, so the content asks for that much less.
    @State private var titleBarInset: CGFloat = 0

    var body: some View {
        @Bindable var presentation = app.presentation
        GeometryReader { geometry in
            VStack(spacing: 0) {
                RunningEntryBar()
                    .popover(isPresented: runningEditorShown, arrowEdge: .bottom) {
                        if let runningEditor {
                            EntryEditorView(model: runningEditor, makePicker: makePicker) {
                                app.presentation.editing = nil
                            }
                        }
                    }
                    .zIndex(1)
                if !TimerWindowGeometry.isCompact(height: geometry.size.height) {
                    Divider()
                    TimerListView()
                }
            }
            .overlay(alignment: .topLeading) {
                TaskFieldPopup()
                    .padding(.leading, app.presentation.taskFieldLeading - Design.Spacing.medium)
                    .offset(y: RunningEntryBar.titleRowHeight + Design.CircleDiameter.bar + Design.Spacing.tight)
                    .zIndex(2)
            }
        }
        .frame(minWidth: TimerWindowGeometry.minimumWidth, minHeight: TimerWindowGeometry.barHeight - titleBarInset)
        .background(WindowAccessor { window in
            titleBarInset = window.frame.height - window.contentLayoutRect.height
        })
        .ignoresSafeArea()
        .focusedSceneValue(\.timerWindowActive, true)
        .onAppear {
            app.timer.undoManager = undoManager
            app.list.undoManager = undoManager
        }
        .onChange(of: app.presentation.editing) { _, editing in
            if let running = app.timer.running, editing == running.id {
                let model = EntryEditorModel(store: app.store, clock: app.clock, entry: running)
                model.onChange = { await app.afterChange() }
                model.onDelete = { app.presentation.editing = nil }
                runningEditor = model
            }
        }
        .alert(item: Binding(get: { app.timer.alert }, set: { app.timer.alert = $0 })) { alert in
            timerAlert(alert)
        }
        .sheet(item: idlePrompt) { _ in
            IdlePromptView()
        }
        .sheet(item: $presentation.dialogModel) { dialog in
            ProjectDialogView(model: dialog) { project in
                Task { await app.dialogFinished(project) }
            }
        }
        // The first-launch alert, once the window shows (AppKit, TrackerOnboardingAlert).
        .onChange(of: app.showsTrackerOnboarding, initial: true) { _, shows in
            if shows {
                app.presentTrackerOnboarding()
            }
        }
    }

    private var runningEditorShown: Binding<Bool> {
        Binding {
            app.timer.running.map { app.presentation.editing == $0.id } ?? false && runningEditor != nil
        } set: { shown in
            if !shown {
                app.presentation.editing = nil
            }
        }
    }

    private var idlePrompt: Binding<IdlePromptItem?> {
        Binding {
            app.idle.prompt.map { IdlePromptItem(prompt: $0) }
        } set: { _ in }
    }

    private func makePicker(_ current: ProjectID?) -> ProjectPickerModel {
        ProjectPickerModel(store: app.store, currentProject: current, taskMatching: true)
    }

    private func timerAlert(_ alert: TimerAlert) -> Alert {
        switch alert {
        case .discard:
            Alert(
                title: Text(alert.message),
                primaryButton: .destructive(Text("Discard")) { Task { await app.timer.discard() } },
                secondaryButton: .cancel()
            )
        case let .restoreProject(id, _):
            Alert(
                title: Text(alert.message),
                primaryButton: .default(Text("Restore Project and Continue")) {
                    Task { await app.timer.restoreProjectAndContinue(id) }
                },
                secondaryButton: .cancel()
            )
        case let .deleteEntry(id, _):
            Alert(
                title: Text(alert.message),
                primaryButton: .destructive(Text("Delete")) { Task { await app.list.delete(id) } },
                secondaryButton: .cancel()
            )
        }
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
                Image(systemName: "moon.zzz")
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
