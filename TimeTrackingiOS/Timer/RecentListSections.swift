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
                ForEach(day.rows) { listing in
                    EntryRow(model: model, listing: listing)
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.list.title(for: day.day))
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(DurationText.clock(day.totalSeconds(at: model.clock.now))).monospacedDigit()
                    }
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .textCase(nil)
                // The total lines up with the rows' durations.
                .padding(.trailing, Design.CircleDiameter.row + Design.Spacing.medium)
                .accessibilityIdentifier("day.\(day.day)")
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
            .accessibilityIdentifier("row.continue.\(listing.id)")
        }
        .padding(.vertical, Design.Spacing.tight)
        .contentShape(Rectangle())
        .onTapGesture { model.openEditor(listing.id) }
        .accessibilityAddTraits(.isButton)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("row.\(listing.id)")
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
