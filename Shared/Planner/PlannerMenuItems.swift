// PlannerMenuItems: the Report and Activity menu items that the Mac's menu
// bar and the iPad's share (spec_planner_reports.md §8,
// spec_planner_activity.md §2).

import SwiftUI
import TimeTrackingCore

/// Groups of menu items, composed by each platform's Report and Activity
/// menus. With `enabled` false (the Mac, outside Reports) every item is
/// disabled and holds no key equivalent.
enum PlannerMenuItems {
    /// Previous Period and Next Period.
    @ViewBuilder
    static func reportPeriod(_ model: ReportsModel, enabled: Bool = true) -> some View {
        Button("Previous Period") { Task { await model.previousPeriod() } }
            .contextCommand(KeyboardShortcut(.leftArrow, modifiers: [.command, .option]), enabled: enabled && model.range.canShift)
        Button("Next Period") { Task { await model.nextPeriod() } }
            .contextCommand(KeyboardShortcut(.rightArrow, modifiers: [.command, .option]), enabled: enabled && model.range.canShift)
    }

    /// Back to Previous Range and Date Range….
    @ViewBuilder
    static func reportRange(_ model: ReportsModel) -> some View {
        reportBack(model)
        Button("Date Range…") { model.showsDatePopover = true }
            .keyboardShortcut("d", modifiers: [.command, .shift])
    }

    /// Back to Previous Range, after a drill-down.
    static func reportBack(_ model: ReportsModel, enabled: Bool = true) -> some View {
        Button("Back to Previous Range") { Task { await model.backToPreviousRange() } }
            .contextCommand(KeyboardShortcut("["), enabled: enabled && model.previousRange != nil)
    }

    /// Filters… and Clear Filters.
    @ViewBuilder
    static func reportFilters(_ model: ReportsModel, enabled: Bool = true) -> some View {
        Button("Filters…") { model.showsFilters = true }
            .contextCommand(KeyboardShortcut("f", modifiers: [.command, .option]), enabled: enabled)
        Button("Clear Filters") { Task { await model.clearFilters() } }
            .contextCommand(KeyboardShortcut("f", modifiers: [.command, .option, .shift]), enabled: enabled)
    }

    /// Show Breakdown and Show Entries.
    @ViewBuilder
    static func reportCards(_ model: ReportsModel, enabled: Bool = true) -> some View {
        Button("Show Breakdown") { Task { await model.show(.breakdown) } }
            .contextCommand(KeyboardShortcut("1", modifiers: [.command, .control]), enabled: enabled)
        Button("Show Entries") { Task { await model.show(.entries) } }
            .contextCommand(KeyboardShortcut("2", modifiers: [.command, .control]), enabled: enabled)
    }

    /// Activity's Previous Period and Next Period.
    @ViewBuilder
    static func activityPeriod(_ model: ActivityModel, enabled: Bool = true) -> some View {
        Button("Previous Period") { Task { await model.shiftPeriod(by: -1) } }
            .contextCommand(KeyboardShortcut(.leftArrow, modifiers: [.command, .option]), enabled: enabled && model.range.canShift)
        Button("Next Period") { Task { await model.shiftPeriod(by: 1) } }
            .contextCommand(KeyboardShortcut(.rightArrow, modifiers: [.command, .option]), enabled: enabled && model.range.canShift)
    }
}
