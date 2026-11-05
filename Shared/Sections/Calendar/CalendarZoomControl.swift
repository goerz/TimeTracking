// CalendarZoomControl: the hours' zoom buttons floating over the columns'
// bottom trailing corner (calendar.md §1.3).

import SwiftUI
import TimeTrackingCore

/// Zoom In above Zoom Out in one glass capsule, like a map's zoom control.
struct CalendarZoomControl: View {
    var model: CalendarModel

    var body: some View {
        VStack(spacing: 0) {
            button("Zoom In", symbol: SymbolName.zoomIn, identifier: "calendar.zoomIn") { model.zoom(by: 1) }
                .disabled(model.pointsPerHour >= CalendarZoom.range.upperBound)
            Divider().frame(width: 18)
            button("Zoom Out", symbol: SymbolName.zoomOut, identifier: "calendar.zoomOut") { model.zoom(by: -1) }
                .disabled(model.pointsPerHour <= CalendarZoom.range.lowerBound)
        }
        .padding(.vertical, Design.Spacing.tight)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func button(_ title: String, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.body)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityIdentifier(identifier)
    }
}
