// ReportPrinter: File › Print… for Reports (spec_planner_reports.md §7):
// the standard print panel, landscape, light appearance with area colors,
// the column header repeated on each page.

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
        let height = info.paperSize.height - info.topMargin - info.bottomMargin
        let printedAt = model.clock.now
        var page = ReportPrintView(model: model, snapshot: snapshot, printedAt: printedAt, width: width)
        // Pages of exactly the printable height, so the automatic pagination
        // cuts between them and each repeats the column header.
        let top = NSHostingView(rootView: page.top.environment(\.colorScheme, .light))
        page.pageHeight = height
        page.topHeight = top.fittingSize.height + 14
        let view = NSHostingView(rootView: page.environment(\.colorScheme, .light))
        view.appearance = NSAppearance(named: .aqua)
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }
}
