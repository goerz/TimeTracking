// ReportsView: toolbar, filter bar, tiles, chart card, and the breakdown or
// entry list (spec_planner_reports.md §1; spec_design.md §4).

import SwiftUI
import TimeTrackingCore
import UniformTypeIdentifiers

/// The Reports section.
struct ReportsView: View {
    @Bindable var model: ReportsModel

    @State private var showsProgress = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 700
            VStack(spacing: Design.Spacing.large) {
                if !model.filterChips.isEmpty {
                    ReportFilterBar(model: model)
                }
                ReportTilesView(model: model, compact: compact)
                ReportChartCard(model: model, height: compact ? 180 : 280)
                ReportLowerCard(model: model)
            }
            .padding(Design.Spacing.content)
        }
        .navigationTitle("Reports")
        .navigationSubtitle(model.range.label)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar { toolbar }
            .searchable(text: $model.search, placement: .toolbar, prompt: "Search")
            .searchFocused($searchFocused)
            .onChange(of: model.searchFocusRequests) { searchFocused = true }
            .task(id: model.search) {
                // Applied 150 ms after the last keystroke.
                guard model.search != model.appliedSearch else {
                    return
                }
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled {
                    await model.applySearch()
                }
            }
            .overlay(alignment: .top) {
                if showsProgress {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            .task { await model.reload() }
            .task(id: model.isLoading) {
                showsProgress = false
                guard model.isLoading else {
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
                showsProgress = model.isLoading
            }
            .task(id: model.refreshInterval) {
                // While the running entry is in the range: tiles, chart, and table every 60 s.
                guard let interval = model.refreshInterval else {
                    return
                }
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    if !Task.isCancelled {
                        await model.reload()
                    }
                }
            }
            .fileExporter(
                isPresented: $model.exportRequested,
                document: model.exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: model.exportDocument.name
            ) { _ in }
    }

    /// Leading: the period items; trailing: Filters. The search field
    /// follows at the far end (spec_design.md §4).
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        DateRangeToolbar(range: model.range, showsPopover: $model.showsDatePopover) {
            Task { await model.reload() }
        }
        ToolbarItem(placement: .primaryAction) {
            ReportFiltersButton(model: model)
        }
        .visibilityPriority(.high)
    }
}

/// The active filters as removable tokens above the tiles, with Clear All.
private struct ReportFilterBar: View {
    var model: ReportsModel

    var body: some View {
        HStack(spacing: Design.Spacing.small) {
            Image(systemName: SymbolName.filter)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            ForEach(model.filterChips) { chip in
                Button {
                    Task { await model.removeChip(chip.kind) }
                } label: {
                    HStack(spacing: Design.Spacing.tight) {
                        Text(chip.text)
                        Image(systemName: SymbolName.discard).imageScale(.small).foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .help("Remove Filter")
                .accessibilityIdentifier("reports.chip")
            }
            Button("Clear All") { Task { await model.clearFilters() } }
                .buttonStyle(.borderless)
                .controlSize(.small)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.filterBar")
    }
}

/// A CSV file for the save panel.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.commaSeparatedText]
    }

    var text: String
    var name: String

    init(text: String, name: String) {
        self.text = text
        self.name = name
    }

    init(configuration: ReadConfiguration) {
        self.text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        self.name = configuration.file.filename ?? "Report.csv"
    }

    func fileWrapper(configuration _: WriteConfiguration) -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// The four tiles; one line below 700 pt of content height.
struct ReportTilesView: View {
    var model: ReportsModel
    var compact: Bool

    var body: some View {
        let summary = model.snapshot?.summary
        let tiles = [
            ("Logged time", ReportText.tile(summary?.loggedSeconds ?? 0), nil as String?),
            ("Average per day", ReportText.tile(summary?.averagePerDay ?? 0), ReportText.averageCaption(summary)),
            ("Entries", String(summary?.entryCount ?? 0), summary?.includesRunning == true ? "1 running" : nil),
            ("Days with entries", String(summary?.daysWithEntries ?? 0), "of \(summary?.elapsedDays ?? 0)"),
        ]
        if compact {
            HStack(spacing: Design.Spacing.large * 2) {
                ForEach(tiles.indices, id: \.self) { index in
                    HStack(spacing: Design.Spacing.small) {
                        Text(tiles[index].0).foregroundStyle(.secondary)
                        Text(tiles[index].1).fontWeight(.semibold).monospacedDigit()
                            .accessibilityIdentifier("reports.tile.\(index)")
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .accessibilityIdentifier("reports.tiles")
        } else {
            HStack(spacing: Design.Spacing.large) {
                ForEach(tiles.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: Design.Spacing.tight) {
                        Text(tiles[index].0).font(.subheadline).foregroundStyle(.secondary)
                        Text(tiles[index].1).font(.title2.weight(.semibold)).monospacedDigit()
                            .accessibilityIdentifier("reports.tile.\(index)")
                        Text(tiles[index].2 ?? " ").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing.large)
                    .cardBackground()
                }
            }
        }
    }
}
