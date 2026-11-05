// ReportMenuContent: the Report menu's items, on the Mac and the iPad
// (reports.md §8).

import SwiftUI
import TimeTrackingCore

/// The Report menu; its range commands are View › Go to Today, Previous
/// Period, Next Period, and Date Range…, and Export… is in File.
struct ReportMenuContent: View {
    var model: ReportsModel
    var enabled: Bool

    var body: some View {
        Button("Back to Previous Range") { Task { await model.backToPreviousRange() } }
            .contextCommand(KeyboardShortcut("["), enabled: enabled && model.previousRange != nil)
        Divider()
        Button("Filters…") { model.showsFilters = true }
            .contextCommand(KeyboardShortcut("f", modifiers: [.command, .option]), enabled: enabled)
        Button("Clear Filters") { Task { await model.clearFilters() } }
            .contextCommand(KeyboardShortcut("f", modifiers: [.command, .option, .shift]), enabled: enabled)
        Divider()
        Button("Show Breakdown") { Task { await model.show(.breakdown) } }
            .contextCommand(KeyboardShortcut("1", modifiers: [.command, .control]), enabled: enabled)
        Button("Show Entries") { Task { await model.show(.entries) } }
            .contextCommand(KeyboardShortcut("2", modifiers: [.command, .control]), enabled: enabled)
        Divider()
        chartMenus
        Divider()
        Button("Expand All") { model.expandAll() }
            .contextCommand(KeyboardShortcut(.rightArrow, modifiers: [.command, .shift]), enabled: enabled)
        Button("Collapse All") { model.collapseAll() }
            .contextCommand(KeyboardShortcut(.leftArrow, modifiers: [.command, .shift]), enabled: enabled)
    }

    /// Stack By.
    private var chartMenus: some View {
        Menu("Stack By") {
            ForEach(StackKind.allCases, id: \.self) { kind in
                Button(kind.title) { Task { await model.setStack(kind) } }
            }
        }
        .disabled(!enabled)
    }
}
