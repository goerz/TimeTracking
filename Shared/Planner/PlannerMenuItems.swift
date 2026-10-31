// PlannerMenuItems: the Report and Activity menu items that the Mac's menu
// bar and the iPad's share (spec_planner_reports.md §8,
// spec_planner_activity.md §2).

import SwiftUI
import TimeTrackingCore

/// Groups of menu items, composed by each platform's Report and Activity menus.
enum PlannerMenuItems {
    /// Previous Period and Next Period.
    @ViewBuilder
    static func reportPeriod(_ model: ReportsModel) -> some View {
        Button("Previous Period") { Task { await model.previousPeriod() } }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(!model.range.canShift)
        Button("Next Period") { Task { await model.nextPeriod() } }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(!model.range.canShift)
    }

    /// Back to Previous Range and Date Range….
    @ViewBuilder
    static func reportRange(_ model: ReportsModel) -> some View {
        Button("Back to Previous Range") { Task { await model.backToPreviousRange() } }
            .keyboardShortcut("[")
            .disabled(model.previousRange == nil)
        Button("Date Range…") { model.showsDatePopover = true }
            .keyboardShortcut("d", modifiers: [.command, .shift])
    }

    /// Filters… and Clear Filters.
    @ViewBuilder
    static func reportFilters(_ model: ReportsModel) -> some View {
        Button("Filters…") { model.showsFilters = true }
            .keyboardShortcut("f", modifiers: [.command, .option])
        Button("Clear Filters") { Task { await model.clearFilters() } }
            .keyboardShortcut("f", modifiers: [.command, .option, .shift])
    }

    /// Show Breakdown and Show Entries.
    @ViewBuilder
    static func reportCards(_ model: ReportsModel) -> some View {
        Button("Show Breakdown") { Task { await model.show(.breakdown) } }
            .keyboardShortcut("1", modifiers: [.command, .control])
        Button("Show Entries") { Task { await model.show(.entries) } }
            .keyboardShortcut("2", modifiers: [.command, .control])
    }

    /// Activity's Previous Period and Next Period.
    @ViewBuilder
    static func activityPeriod(_ model: ActivityModel) -> some View {
        Button("Previous Period") { Task { await model.shiftPeriod(by: -1) } }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(!model.range.canShift)
        Button("Next Period") { Task { await model.shiftPeriod(by: 1) } }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(!model.range.canShift)
    }
}
