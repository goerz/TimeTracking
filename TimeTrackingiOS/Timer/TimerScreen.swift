// TimerScreen: the iPhone's Timer (spec_ios.md §2.1): a large title, the
// settings button, the running-entry card, the Mac activity line,
// the sync pill, and the searchable day-grouped list.

import AppIntents
import SwiftUI
import TimeTrackingCore

struct TimerScreen: View {
    @Bindable var model: PhoneModel

    @Environment(\.undoManager) private var undoManager
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                if model.settings.isPad, proxy.size.width > Self.twoColumnWidth {
                    // The iPad above 900 pt: the card column and the list side by side (§10.1).
                    HStack(spacing: 0) {
                        List { cardSection }
                            .listStyle(.insetGrouped)
                            .frame(width: min(420, proxy.size.width * 0.4))
                        recentList(includingCard: false)
                    }
                } else {
                    recentList(includingCard: true)
                }
            }
            // In the drawer under the title, revealed by pulling down: the
            // filter is occasional, so it does not cover the list.
            .searchable(text: Bindable(model.list).filter, placement: .navigationBarDrawer, prompt: "Filter")
            .searchFocused($searchFocused)
            .onChange(of: model.list.isFilterVisible) { _, visible in
                // ⌘F on the iPad's keyboard.
                if visible {
                    searchFocused = true
                }
            }
            .onChange(of: model.list.filter) {
                model.list.isFilterVisible = !model.list.filter.isEmpty
                Task { await model.list.reload() }
            }
            .navigationTitle("Timer")
            .toolbar { toolbar }
            .safeAreaInset(edge: .top) { bannerView }
        }
        .sheet(item: sheetBinding) { sheet in
            sheetContent(sheet)
        }
        .timerAlert(timer: model.timer, list: model.list)
        .alert(
            "Can't Open This Link",
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

    static let twoColumnWidth: CGFloat = 900

    @ViewBuilder private var cardSection: some View {
        if model.macLines.isEmpty, model.syncPill(at: .distantFuture) == nil {
            // No footer at all, so the tip sits close under the card.
            Section {
                RunningEntryCard(model: model)
            }
        } else {
            Section {
                RunningEntryCard(model: model)
            } footer: {
                statusLines
            }
        }
        if !model.settings.siriTipDismissed {
            Section {
                SiriTipView(intent: StartTimerIntent(inferProject: true), isVisible: siriTipVisible)
                    // The tip draws its own platter, as wide as the card.
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func recentList(includingCard: Bool) -> some View {
        ScrollViewReader { proxy in
            List {
                if includingCard {
                    cardSection
                }
                RecentListSections(model: model)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(Design.Spacing.medium)
            .accessibilityIdentifier("timer.list")
            .onChange(of: model.list.scrollToTopRequest) {
                // ⌘↑ (spec_ios.md §10.3).
                if let first = model.list.days.first {
                    proxy.scrollTo(first.id, anchor: .top)
                }
            }
        }
    }

    /// The iPad shows the picker as a popover from the chip, the iPhone as a sheet.
    private var sheetBinding: Binding<PhoneSheet?> {
        Binding {
            if model.settings.isPad, case .picker = model.sheet {
                return nil
            }
            return model.sheet
        } set: { value in
            if value == nil, model.settings.isPad, case .picker = model.sheet {
                return
            }
            model.sheet = value
        }
    }

    private var siriTipVisible: Binding<Bool> {
        Binding(get: { !model.settings.siriTipDismissed }, set: { model.settings.siriTipDismissed = !$0 })
    }

    /// The Mac activity lines and the sync pill, under the card.
    private var statusLines: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.tight) {
            ForEach(model.macLines, id: \.self) { line in
                Label(line, systemImage: SymbolName.mac)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .accessibilityAddTraits(.isButton)
                    .onTapGesture { model.macActivityTapped() }
                    .accessibilityIdentifier("timer.macActivity")
            }
            // Nothing while no pill can show (sending shows after 10 s).
            if model.syncPill(at: .distantFuture) != nil {
                syncPill
            }
        }
        .textCase(nil)
    }

    private var syncPill: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let pill = model.syncPill(at: model.clock.now) {
                Label(pill, systemImage: SymbolName.iCloudOff)
                    .font(.caption)
                    .padding(.horizontal, Design.Spacing.small)
                    .padding(.vertical, Design.Spacing.tight)
                    .background(Capsule().fill(.quaternary))
                    .accessibilityIdentifier("timer.syncPill")
            }
        }
    }

    @ViewBuilder private var bannerView: some View {
        if let banner = model.banner {
            HStack {
                Text("Another device changed an entry").font(.subheadline)
                Spacer()
                Button("Show") { model.openEditor(banner.entryID) }
                    .accessibilityIdentifier("timer.bannerShow")
            }
            .padding(Design.Spacing.medium)
            .background(RoundedRectangle(cornerRadius: Design.Radius.card).fill(.thinMaterial))
            .padding(.horizontal)
            .accessibilityIdentifier("timer.banner")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                model.sheet = .settings
            } label: {
                Label("Settings", systemImage: SymbolName.settings)
            }
            .accessibilityIdentifier("timer.settings")
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
}
