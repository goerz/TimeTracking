// ReportPrinter: File › Print… for Reports (spec_planner_reports.md §7):
// the standard print panel, landscape, light appearance with area colors.

import AppKit
import SwiftUI
import TimeTrackingCore

/// Prints the current report through `NSPrintOperation`.
enum ReportPrinter {
    static func print(_ model: ReportsModel) {
        guard let snapshot = model.snapshot else {
            return
        }
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.orientation = .landscape
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let page = ReportPrintView(model: model, snapshot: snapshot, printedAt: model.clock.now, width: width)
            .environment(\.colorScheme, .light)
        let view = NSHostingView(rootView: page)
        view.appearance = NSAppearance(named: .aqua)
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }
}

/// The printed page: header, tiles, chart, and the breakdown at its current
/// expansion or the entry list.
struct ReportPrintView: View {
    var model: ReportsModel
    var snapshot: ReportSnapshot
    var printedAt: Date
    var width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.range.label).font(.title2.weight(.semibold))
                let chips = model.filterChips.map(\.text)
                Text(chips.isEmpty ? "No filters" : chips.joined(separator: " · ")).foregroundStyle(.secondary)
                Text("Printed \(printedAt.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
            }
            ReportTilesView(model: model, compact: false)
            if let image = chartImage {
                Image(nsImage: image).resizable().scaledToFit().frame(height: 220).accessibilityLabel("Logged time chart")
            }
            if model.state.card == .breakdown {
                breakdown
            } else {
                entries
            }
        }
        .padding(8)
        .frame(width: width, alignment: .leading)
    }

    /// The chart through `ImageRenderer` at the printer's scale.
    private var chartImage: NSImage? {
        let renderer = ImageRenderer(content: ReportChartCard(model: model, height: 220).frame(width: width).environment(
            \.colorScheme,
            .light
        ))
        renderer.scale = 2
        return renderer.nsImage
    }

    private var breakdown: some View {
        let total = snapshot.tree.seconds
        return VStack(alignment: .leading, spacing: 3) {
            row(["Name", "Logged time", "Share", "Entries"], bold: true)
            ForEach(model.breakdownRows) { item in
                row([
                    String(repeating: "    ", count: item.depth) + item.title, ReportText.seconds(item.node.seconds),
                    ReportText.share(item.node.seconds, of: total), String(item.node.entryCount),
                ], bold: false)
            }
            Divider()
            row(["Total", ReportText.seconds(total), "100%", String(snapshot.tree.entryCount)], bold: true)
        }
    }

    private var entries: some View {
        VStack(alignment: .leading, spacing: 3) {
            row(["Date", "Start", "Stop", "Duration", "Client", "Project", "Task"], bold: true)
            ForEach(model.listings) { listing in
                let entry = listing.entry
                row([
                    DayText.weekdayShortDate(entry.day), entry.start.formatted(date: .omitted, time: .shortened),
                    entry.end?.formatted(date: .omitted, time: .shortened) ?? "running", ReportText.seconds(entry.seconds(at: printedAt)),
                    listing.client?.name ?? "–", listing.project?.name ?? "–", entry.task,
                ], bold: false)
            }
            Divider()
            Text(model.listFooter(at: printedAt)).fontWeight(.semibold)
        }
    }

    private func row(_ columns: [String], bold: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(columns.indices, id: \.self) { index in
                Text(columns[index])
                    .lineLimit(1)
                    .frame(
                        maxWidth: index == 0 || index == columns.count - 1 ? .infinity : 110,
                        alignment: index == 0 ? .leading : .trailing
                    )
            }
        }
        .font(.system(size: 10, weight: bold ? .semibold : .regular))
    }
}
