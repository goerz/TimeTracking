// TimerScreen: the iPhone's Timer (spec_ios.md §2.1): a large title, the
// settings and menu buttons, the running-entry card, the Mac activity line,
// the sync pill, and the searchable day-grouped list.

import AppIntents
import SwiftUI
import TimeTrackingCore

struct TimerScreen: View {
    @Bindable var model: PhoneModel

    @Environment(\.undoManager) private var undoManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RunningEntryCard(model: model)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    statusLines
                }
                if !model.settings.siriTipDismissed {
                    SiriTipView(intent: StartTimerIntent(inferProject: true), isVisible: siriTipVisible)
                        .listRowBackground(Color.clear)
                }
                RecentListSections(model: model)
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("timer.list")
            .searchable(text: Bindable(model.list).filter, prompt: "Filter")
            .onChange(of: model.list.filter) {
                model.list.isFilterVisible = !model.list.filter.isEmpty
                Task { await model.list.reload() }
            }
            .navigationTitle("Timer")
            .toolbar { toolbar }
            .safeAreaInset(edge: .top) { bannerView }
        }
        .sheet(item: $model.sheet) { sheet in
            sheetContent(sheet)
        }
        .alert(
            model.timer.alert?.message ?? "",
            isPresented: Binding(get: { model.timer.alert != nil }, set: { model.timer.alert = $0 ? model.timer.alert : nil }),
            presenting: model.timer.alert
        ) { alert in
            timerAlertButtons(alert)
        }
        .alert(
            "Unknown TimeTracking URL",
            isPresented: Binding(get: { model.urlAlert != nil }, set: { model.urlAlert = $0 ? model.urlAlert : nil })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.urlAlert ?? "")
        }
        .onAppear {
            model.timer.undoManager = undoManager
            model.list.undoManager = undoManager
        }
    }

    private var siriTipVisible: Binding<Bool> {
        Binding(get: { !model.settings.siriTipDismissed }, set: { model.settings.siriTipDismissed = !$0 })
    }

    @ViewBuilder private var statusLines: some View {
        ForEach(model.macLines, id: \.self) { line in
            Label(line, systemImage: "desktopcomputer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("timer.macActivity")
        }
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let pill = model.syncPill(at: model.clock.now) {
                Label(pill, systemImage: "icloud.slash")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.quaternary))
                    .accessibilityIdentifier("timer.syncPill")
            }
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder private var bannerView: some View {
        if let banner = model.banner {
            HStack {
                Text("An entry was adjusted after syncing").font(.subheadline)
                Spacer()
                Button("Show") { model.openEditor(banner.entryID) }
                    .accessibilityIdentifier("timer.bannerShow")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial))
            .padding(.horizontal)
            .accessibilityIdentifier("timer.banner")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                model.sheet = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("timer.settings")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Continue Latest", systemImage: "arrow.counterclockwise") {
                    Task { await model.timer.continueEntry() }
                }
                .disabled(model.timer.mostRecentOther == nil)
                Button("Stop", systemImage: "stop.fill") {
                    Task { await model.timer.stop() }
                }
                .disabled(!model.timer.isRunning)
                Button("Discard", systemImage: "xmark.circle", role: .destructive) {
                    Task { await model.timer.requestDiscard(skipAlert: false) }
                }
                .disabled(!model.timer.isRunning)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("timer.menu")
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: PhoneSheet) -> some View {
        switch sheet {
        case let .picker(picker):
            PickerSheet(model: model, picker: picker)
        case let .editor(id):
            EntryEditSheet(model: model, entryID: id)
        case .settings:
            SettingsScreen(model: model)
        }
    }

    @ViewBuilder
    private func timerAlertButtons(_ alert: TimerAlert) -> some View {
        switch alert {
        case .discard:
            Button("Discard", role: .destructive) { Task { await model.timer.discard() } }
                .accessibilityIdentifier("alert.discard")
        case let .restoreProject(id, _):
            Button("Restore Project and Continue") { Task { await model.timer.restoreProjectAndContinue(id) } }
                .accessibilityIdentifier("alert.restore")
        case let .deleteEntry(id, _):
            Button("Delete", role: .destructive) { Task { await model.list.delete(id) } }
                .accessibilityIdentifier("alert.delete")
        }
        Button("Cancel", role: .cancel) {}
            .accessibilityIdentifier("alert.cancel")
    }
}
