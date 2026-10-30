// ActivityView: the Activity section's range bar, header, chips, panels,
// and health footer (spec_planner_activity.md §1; mockups/planner_activity.png).

import SwiftUI
import TimeTrackingCore

/// The Activity section.
struct ActivityView: View {
    @Bindable var model: ActivityModel
    @State private var showsDatePopover = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Activity").font(.title2.bold())
                DateRangeControl(range: model.range, showsPopover: $showsDatePopover) { Task { await model.reload() } }
                Spacer()
                devicePopup
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    ActivityChips(model: model)
                    content
                }
                .padding(16)
            }
            Divider()
            ActivityFooter(model: model)
        }
        .navigationTitle("Activity")
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
            .fixedSize()
            .accessibilityIdentifier("activity.devices")
        }
    }

    @ViewBuilder private var header: some View {
        if let summary = model.summary {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(ActivityText.duration(summary.total)) active").font(.largeTitle.bold())
                    .accessibilityIdentifier("activity.total")
                Text(summary.headerDetail).foregroundStyle(.secondary)
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
        case .setup:
            card {
                Text("Set up the tracker to see where your time goes. Nothing is recorded until you enable it.")
                Button("Open Tracker Settings…") { model.router?.showTrackerSettings() }
            }
            .accessibilityIdentifier("activity.setup")
        case let .noActivity(notRunning):
            card {
                Text(ActivityEmptyState.noActivityText(model.days))
                if notRunning {
                    Text("The tracker was not running.").foregroundStyle(.secondary)
                    Button("Tracker Settings…") { model.router?.showTrackerSettings() }
                }
            }
            .accessibilityIdentifier("activity.empty")
        case .nothingForContexts:
            card {
                Text("Nothing recorded for the selected contexts")
                Button("Show All Contexts") { Task { await model.selectAll() } }
            }
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
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
        HStack(spacing: 6) {
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
            HStack(spacing: 4) {
                if let context {
                    ContextGlyph(context: context)
                }
                Text(title)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
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
        HStack(spacing: 6) {
            if let health = model.health {
                Circle().fill(health.dot.color).frame(width: 8, height: 8)
                Text(health.statusLine)
                if !health.activeSources.isEmpty {
                    Text("· " + health.activeSources.joined(separator: ", ")).foregroundStyle(.secondary)
                }
                if !health.problems.isEmpty {
                    Text("· " + health.problems.joined(separator: ", ")).foregroundStyle(.orange)
                }
            }
            Spacer()
            if model.isRecordingMac {
                Button("Tracker Settings…") { model.router?.showTrackerSettings() }
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .help(model.health?.tooltip.joined(separator: "\n") ?? "")
        .task {
            while !Task.isCancelled {
                await model.loadHealth()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .accessibilityIdentifier("activity.footer")
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
