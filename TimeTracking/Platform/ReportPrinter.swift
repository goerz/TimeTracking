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
