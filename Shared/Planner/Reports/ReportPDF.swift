// ReportPDF: the printed Reports page as a PDF for the iPad's share sheet,
// whose Print prints it (spec_ios.md §10.2; spec_planner_reports.md §7).

import CoreGraphics
import CoreTransferable
import Foundation
import SwiftUI
import TimeTrackingCore
import UniformTypeIdentifiers

/// The current report, rendered when the share sheet asks for it.
nonisolated struct ReportPDF: Transferable {
    let model: ReportsModel

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { pdf in
            await pdf.render()
        }
        .suggestedFileName("Report.pdf")
    }

    /// One landscape-wide page as tall as the report.
    @MainActor
    func render() -> Data {
        guard let snapshot = model.snapshot else {
            return Data()
        }
        let page = ReportPrintView(model: model, snapshot: snapshot, printedAt: model.clock.now, width: 756)
            .padding(Design.Spacing.window)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: page)
        guard let data = CFDataCreateMutable(nil, 0) else {
            return Data()
        }
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil)
            else {
                return
            }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        return data as Data
    }
}
