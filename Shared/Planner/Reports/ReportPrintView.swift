// ReportPrintView: the printed Reports page (spec_planner_reports.md §7),
// printed by the Mac's print panel and shared as a PDF on the iPad.

import SwiftUI
import TimeTrackingCore

/// How the table rows of a printout fall on pages, so each page can repeat
/// the column header.
struct ReportPrintPages: Equatable {
    /// The height of one table row (header, body, and footer rows alike).
    static let rowHeight: CGFloat = 15

    /// Row ranges per page: the first page holds `firstCapacity` rows (it
    /// also carries the header, tiles, and chart), the others `capacity`;
    /// every page has room for the column header, the last also for the
    /// footer (divider and total). At least one page, possibly empty.
    static func split(rows: Int, firstCapacity: Int, capacity: Int) -> [Range<Int>] {
        var pages: [Range<Int>] = []
        var start = 0
        var room = max(firstCapacity, 0)
        while true {
            let remaining = rows - start
            if remaining + 1 <= room {
                pages.append(start ..< rows)
                return pages
            }
            // A full page; the footer (and any rest) goes to the next one.
            let take = min(remaining, room)
            pages.append(start ..< start + take)
            start += take
            room = max(capacity, 1)
        }
    }

    /// Rows that fit below the column header in `height`.
    static func capacity(height: CGFloat) -> Int {
        max(Int((height / rowHeight).rounded(.down)) - 1, 0)
    }
}

/// The printout: header, tiles, chart, and the breakdown at its current
/// expansion or the entry list. With `pageHeight` the table is cut into
/// pages of that height, each repeating the column header; without it the
/// whole report is one tall page (the iPad's PDF).
struct ReportPrintView: View {
    var model: ReportsModel
    var snapshot: ReportSnapshot
    var printedAt: Date
    var width: CGFloat
    /// The printable page height and the height the top part takes.
    var pageHeight: CGFloat?
    var topHeight: CGFloat = 0

    var body: some View {
        let rows = tableRows
        if let pageHeight {
            let pages = ReportPrintPages.split(
                rows: rows.count,
                firstCapacity: ReportPrintPages.capacity(height: pageHeight - topHeight - 16),
                capacity: ReportPrintPages.capacity(height: pageHeight - 16)
            )
            VStack(alignment: .leading, spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 0) {
                        if index == 0 {
                            top.padding(.bottom, Design.Spacing.large)
                        }
                        table(rows: Array(rows[pages[index]]), footer: index == pages.count - 1)
                    }
                    .padding(Design.Spacing.small)
                    .frame(width: width, height: pageHeight, alignment: .topLeading)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Design.Spacing.large) {
                top
                table(rows: rows, footer: true)
            }
            .padding(Design.Spacing.small)
            .frame(width: width, alignment: .leading)
        }
    }

    /// The range, filters, print date, tiles, and chart.
    var top: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.large) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.range.label).font(.title2.weight(.semibold))
                let chips = model.filterChips.map(\.text)
                Text(chips.isEmpty ? "No filters" : chips.joined(separator: " · ")).foregroundStyle(.secondary)
                Text("Printed \(printedAt.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
            }
            ReportTilesView(model: model, compact: false)
            if let image = chartImage {
                image.resizable().scaledToFit().frame(height: 220).accessibilityLabel("Logged time chart")
            }
        }
        .frame(width: width - 16, alignment: .leading)
    }

    /// The chart through `ImageRenderer` at the printer's scale.
    private var chartImage: Image? {
        let renderer = ImageRenderer(content: ReportChartCard(model: model, height: 220).frame(width: width).environment(
            \.colorScheme,
            .light
        ))
        renderer.scale = 2
        return renderer.cgImage.map { Image(decorative: $0, scale: 2) }
    }

    private var showsBreakdown: Bool {
        model.state.card == .breakdown
    }

    private var columnHeader: [String] {
        showsBreakdown ? ["Name", "Logged time", "Share", "Entries"] : ["Date", "Start", "Stop", "Duration", "Client", "Project", "Task"]
    }

    private var tableRows: [[String]] {
        if showsBreakdown {
            let total = snapshot.tree.seconds
            return model.breakdownRows.map { item in
                [
                    String(repeating: "    ", count: item.depth) + item.title, ReportText.seconds(item.node.seconds),
                    ReportText.share(item.node.seconds, of: total), String(item.node.entryCount),
                ]
            }
        }
        return model.listings.map { listing in
            let entry = listing.entry
            return [
                DayText.weekdayShortDate(entry.day), entry.start.formatted(date: .omitted, time: .shortened),
                entry.end?.formatted(date: .omitted, time: .shortened) ?? "running", ReportText.seconds(entry.seconds(at: printedAt)),
                listing.client?.name ?? "–", listing.project?.name ?? "–", entry.task,
            ]
        }
    }

    private func table(rows: [[String]], footer: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            row(columnHeader, bold: true)
            ForEach(rows.indices, id: \.self) { index in
                row(rows[index], bold: false)
            }
            if footer {
                Divider()
                if showsBreakdown {
                    let total = snapshot.tree
                    row(["Total", ReportText.seconds(total.seconds), "100%", String(total.entryCount)], bold: true)
                } else {
                    Text(model.listFooter(at: printedAt)).font(.system(size: 10, weight: .semibold))
                        .frame(height: ReportPrintPages.rowHeight)
                }
            }
        }
    }

    private func row(_ columns: [String], bold: Bool) -> some View {
        HStack(spacing: Design.Spacing.small) {
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
        .frame(height: ReportPrintPages.rowHeight)
    }
}
