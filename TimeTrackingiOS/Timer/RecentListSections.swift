// RecentListSections: the day-grouped recent list (spec_ios.md §2.6): one
// section per day with its live total, rows with a play button, swipes, and
// a context menu; the 14-day paging of spec_timer_window.md §3.

import SwiftUI
import TimeTrackingCore

struct RecentListSections: View {
    @Bindable var model: PhoneModel

    var body: some View {
        ForEach(model.list.days) { day in
            Section {
                if let running = day.runningListing {
                    RunningRow(model: model, listing: running)
                }
                ForEach(day.rows) { listing in
                    EntryRow(model: model, listing: listing)
                }
            } header: {
                DayHeaderLabel(day: day, title: model.list.title(for: day.day), clock: model.clock)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
                    // The total lines up with the rows' durations.
                    .padding(.trailing, Design.CircleDiameter.row + Design.Spacing.medium)
            }
        }
        if model.list.canLoadMore {
            Button("Load Earlier Entries") {
                Task { await model.list.loadMore() }
            }
            .accessibilityIdentifier("timer.loadMore")
        }
    }
}

/// The running entry as Today's first row: its live duration in the accent
/// color, no play button; a tap opens the edit sheet.
struct RunningRow: View {
    @Bindable var model: PhoneModel
    var listing: EntryListing

    var body: some View {
        HStack(spacing: Design.Spacing.medium) {
            EntryRowLabels(listing: listing, badged: model.badged.contains(listing.id))
            Spacer(minLength: Design.Spacing.small)
            RunningDurationText(entry: listing.entry, clock: model.clock)
            Color.clear.frame(width: Design.CircleDiameter.row, height: 1)
        }
        .padding(.vertical, Design.Spacing.tight)
        .contentShape(Rectangle())
        .onTapGesture { model.openEditor(listing.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue("running")
        .accessibilityIdentifier("timer.runningRow")
    }
}

/// One stopped entry: task, area dot, project and client, duration, play.
struct EntryRow: View {
    @Bindable var model: PhoneModel
    var listing: EntryListing

    var body: some View {
        HStack(spacing: Design.Spacing.medium) {
            EntryRowLabels(listing: listing, badged: model.badged.contains(listing.id))
            Spacer(minLength: Design.Spacing.small)
            Text(DurationText.clock(listing.entry.seconds(at: model.clock.now))).monospacedDigit()
            Button {
                Task { await model.timer.continueEntry(listing.id) }
            } label: {
                Label("Continue", systemImage: "play.fill")
            }
            .buttonStyle(CircleButtonStyle(color: .startTint, diameter: Design.CircleDiameter.row))
            .accessibilityIdentifier("timer.row.continue.\(listing.id)")
        }
        .padding(.vertical, Design.Spacing.tight)
        .contentShape(Rectangle())
        .onTapGesture { model.openEditor(listing.id) }
        .accessibilityAddTraits(.isButton)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timer.row.\(listing.id)")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button("Continue", systemImage: "play.fill") {
                Task { await model.timer.continueEntry(listing.id) }
            }
            .tint(.startTint)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                model.timer.alert = model.list.deleteAlert(for: listing.id)
            }
        }
        .contextMenu {
            Button("Continue", systemImage: "play.fill") { Task { await model.timer.continueEntry(listing.id) } }
            Button("Edit", systemImage: "pencil") { model.openEditor(listing.id) }
            Button("Copy Task", systemImage: "doc.on.doc") { Clipboard.copy(listing.entry.task) }
            Button("Delete", systemImage: "trash", role: .destructive) {
                model.timer.alert = model.list.deleteAlert(for: listing.id)
            }
        }
    }
}
