// ActivityView: the Activity section's range bar, header, chips, panels,
// and health footer (spec_planner_activity.md §1; mockups/planner_activity.png).

import SwiftUI
import TimeTrackingCore

/// The Activity section.
struct ActivityView: View {
    @Bindable var model: ActivityModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            switch model.emptyState {
            case .setup:
                setupState.frame(maxHeight: .infinity)
            case let .noActivity(notRunning):
                noActivityState(notRunning: notRunning).frame(maxHeight: .infinity)
            case .panels, .nothingForContexts:
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing.large) {
                        header
                        ActivityChips(model: model)
                        content
                    }
                    .padding(Design.Spacing.content)
                }
            }
            Divider()
            ActivityFooter(model: model)
        }
        .navigationTitle("Activity")
        .navigationSubtitle(model.range.label)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                DateRangeToolbar(range: model.range, showsPopover: $model.showsDatePopover) {
                    model.range.goToToday()
                    Task { await model.reload() }
                } onChange: {
                    Task { await model.reload() }
                }
                if (model.summary?.devices.count ?? 0) > 1 {
                    ToolbarItem(placement: .primaryAction) { devicePopup }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("planner.activity")
            .task(id: model.router?.activityRequests) { await model.reload() }
            .task { await followChanges() }
            .onKeyPress(.escape) {
                Task { await model.escape() }
                return .handled
            }
            .environment(\.contextColors, ContextColorLookup(colors: model.contextColors, dark: colorScheme == .dark))
    }

    private func followChanges() async {
        for await _ in model.activity.changes {
            await model.reload()
        }
    }

    @ViewBuilder private var devicePopup: some View {
        if let summary = model.summary, summary.devices.count > 1 {
            Picker("Devices", selection: $model.selectedDevice) {
                Text("All devices").tag(String?.none)
                ForEach(summary.devices) { device in
                    Text("\(device.displayName) \(ActivityText.duration(device.seconds))").tag(String?.some(device.device))
                }
            }
            .pickerStyle(.menu)
            .help("Devices")
            .accessibilityIdentifier("activity.devices")
        }
    }

    @ViewBuilder private var header: some View {
        if let summary = model.summary {
            VStack(alignment: .leading, spacing: Design.Spacing.tight) {
                Text("\(ActivityText.duration(summary.total)) active").font(.title2.weight(.semibold)).monospacedDigit()
                    .accessibilityIdentifier("activity.total")
                Text(summary.headerDetail).font(.subheadline).foregroundStyle(.secondary)
                if let note = model.clipNote {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.emptyState {
        case .panels:
            if let summary = model.summary {
                ActivityPanels(model: model, summary: summary)
            }
        case .setup, .noActivity:
            // The whole section shows these (setupState, noActivityState).
            EmptyView()
        case .nothingForContexts:
            card {
                Text("Nothing recorded for the selected apps")
                Button("Show All Apps") { Task { await model.selectAll() } }
            }
        }
    }

    /// No block yet and no tracker set up (§1.9, §5).
    private var setupState: some View {
        ContentUnavailableView {
            Label("No Activity Yet", systemImage: SymbolName.activity)
        } description: {
            if model.isRecordingMac {
                Text("Set up the tracker to see where your time goes. Nothing is recorded until you enable it.")
            } else {
                Text("The tracker runs on your Mac. Set it up in the Mac app's Settings, Tracker pane.")
            }
        } actions: {
            if model.isRecordingMac {
                Button("Open Tracker Settings…") { model.router?.showTrackerSettings() }
            }
        }
        .accessibilityIdentifier("activity.setup")
    }

    /// No blocks in the range (§1.9).
    private func noActivityState(notRunning: Bool) -> some View {
        ContentUnavailableView {
            Label(ActivityEmptyState.noActivityText(model.days), systemImage: SymbolName.activity)
        } description: {
            if notRunning {
                Text("The tracker was not running.")
            }
        } actions: {
            if notRunning, model.isRecordingMac {
                Button("Tracker Settings…") { model.router?.showTrackerSettings() }
            }
        }
        .accessibilityIdentifier("activity.empty")
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.small, content: content)
            .padding(Design.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
    }
}

/// Context colors for the panels.
struct ContextColorLookup {
    var colors: [String: Int] = [:]
    var dark = false

    func color(_ context: String?) -> Color {
        guard let context, !ActivityContext(context).isPrivate, let hex = ContextPalette.hex(colors[context], dark: dark) else {
            return .gray
        }
        return Color(hex: hex)
    }
}

extension EnvironmentValues {
    @Entry var contextColors = ContextColorLookup()
}

/// The glyph of a context (§1.3).
struct ContextGlyph: View {
    var context: String
    @Environment(\.contextColors) private var colors

    var body: some View {
        let kind = ActivityContext(context).kind
        Image(systemName: kind == .session ? "terminal" : kind == .browser ? "safari" : "app").accessibilityHidden(true)
            .foregroundStyle(colors.color(context))
    }
}

/// "All", eight chips, "N more…" (§1.3).
private struct ActivityChips: View {
    @Bindable var model: ActivityModel

    var body: some View {
        let ranking = model.summary?.ranking ?? []
        HStack(spacing: Design.Spacing.compact) {
            chip("All", selected: model.contexts.isEmpty) { Task { await model.selectAll() } }
            ForEach(ranking.prefix(8)) { total in
                chip(model.displayName(total.context), context: total.context, selected: model.contexts.contains(total.context)) {
                    Task { await model.toggle(total.context) }
                }
                .help(ActivityText.duration(total.seconds))
            }
            if ranking.count > 8 {
                Button("\(ranking.count - 8) more…") { model.showsMore = true }
                    .buttonStyle(.bordered)
                    .clipShape(Capsule())
                    .popover(isPresented: $model.showsMore) { morePopover }
            }
        }
        .accessibilityIdentifier("activity.chips")
    }

    private func chip(_ title: String, context: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing.tight) {
                if let context {
                    ContextGlyph(context: context)
                }
                Text(title)
            }
            .padding(.horizontal, Design.Spacing.medium)
            .padding(.vertical, Design.Spacing.tight)
            .background(Capsule().fill(selected ? Color.accentColor : Color.secondary.opacity(0.12)))
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var morePopover: some View {
        VStack(alignment: .leading) {
            TextField("Search", text: $model.moreSearch)
            List(model.summary?.moreContexts(search: model.moreSearch, displayName: model.displayName) ?? []) { total in
                Button {
                    Task { await model.toggle(total.context) }
                } label: {
                    HStack {
                        ContextGlyph(context: total.context)
                        Text(model.displayName(total.context))
                        Spacer()
                        Text(ActivityText.duration(total.seconds)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 300, height: 320)
    }
}

/// The health footer (§1.10, §5).
private struct ActivityFooter: View {
    var model: ActivityModel

    var body: some View {
        HStack(spacing: Design.Spacing.small) {
            if let health = model.health {
                Circle().fill(health.dot.color).frame(width: 8, height: 8)
                Text(health.statusLine)
                if !health.problems.isEmpty {
                    Text("· " + health.problems.joined(separator: ", ")).foregroundStyle(.orange)
                }
            }
            if model.iCloudWaiting {
                Text(waitingText).foregroundStyle(.secondary).accessibilityIdentifier("activity.waitingForICloud")
            }
            Spacer()
            if model.isRecordingMac {
                Button("Tracker Settings…") { model.router?.showTrackerSettings() }
                    .buttonStyle(.borderless)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, Design.Spacing.content)
        .padding(.vertical, Design.Spacing.small)
        .help(model.health?.tooltip.joined(separator: "\n") ?? "")
        .task { await model.followHealth() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity.footer")
    }
}

extension ActivityFooter {
    /// "Waiting for iCloud · activity up to 14:02".
    private var waitingText: String {
        guard let newest = model.newestBlockEnd else {
            return "Waiting for iCloud"
        }
        return "Waiting for iCloud · activity up to \(CalendarText.clock(newest, zone: model.range.calendar.timeZone))"
    }
}

extension ActivityHealthDot {
    var color: Color {
        switch self {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        case .gray: .gray
        }
    }
}
