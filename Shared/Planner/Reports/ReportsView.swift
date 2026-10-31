// ReportsView: toolbar, filter bar, tiles, chart card, and the breakdown or
// entry list (spec_planner_reports.md §1; spec_design.md §4).

import SwiftUI
import TimeTrackingCore
import UniformTypeIdentifiers

/// The Reports section.
struct ReportsView: View {
    @Bindable var model: ReportsModel
    /// Print… (the Mac's print panel; the iPad's share sheet).
    var onPrint: (() -> Void)?

    @State private var exporting: CSVDocument?
    @State private var showsProgress = false

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
            .confirmationDialog("Export", isPresented: $model.exportRequested) {
                Button("Breakdown (CSV)…") { export(entries: false) }
                Button("Entries (CSV)…") { export(entries: true) }
            }
            .fileExporter(
                isPresented: .isPresent($exporting),
                document: exporting,
                contentType: .commaSeparatedText,
                defaultFilename: exporting?.name
            ) { _ in
                exporting = nil
            }
    }

    /// File › Export…: the chosen format's CSV.
    func export(entries: Bool) {
        exporting = CSVDocument(text: entries ? model.entriesCSV : model.breakdownCSV, name: model.exportFileName(entries: entries))
    }

    /// Leading: the period items; trailing: Filters, granularity, Print, Export.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        DateRangeToolbar(range: model.range, showsPopover: $model.showsDatePopover) {
            Task { await model.goToToday() }
        } onChange: {
            Task { await model.reload() }
        }
        ToolbarItem(placement: .primaryAction) {
            ReportFiltersButton(model: model)
        }
        .visibilityPriority(.high)
        ToolbarItem(placement: .primaryAction) {
            Picker("Show Totals By", selection: Binding(get: { model.state.granularity }, set: { value in
                Task { await model.setGranularity(value) }
            })) {
                Text("Automatic").tag(Granularity?.none)
                ForEach([Granularity.day, .week, .month, .year], id: \.self) { granularity in
                    Text(granularity.title).tag(Granularity?.some(granularity))
                }
            }
            .pickerStyle(.menu)
            .help("Show Totals By")
            .accessibilityIdentifier("reports.granularity")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            #if os(iOS)
                // The share sheet's Print (spec_ios.md §10.2).
                ShareLink(item: ReportPDF(model: model), preview: SharePreview(model.range.label)) {
                    Label("Print", systemImage: SymbolName.print)
                }
                .accessibilityIdentifier("reports.print")
            #else
                if let onPrint {
                    Button(action: onPrint) {
                        Label("Print", systemImage: SymbolName.print)
                    }
                    .help("Print")
                    .accessibilityIdentifier("reports.print")
                }
            #endif
            Menu {
                Button("Breakdown (CSV)…") { export(entries: false) }
                Button("Entries (CSV)…") { export(entries: true) }
            } label: {
                Label("Export", systemImage: SymbolName.share)
            }
            .help("Export")
            .accessibilityIdentifier("reports.export")
        }
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
