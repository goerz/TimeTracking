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
                HStack {
                    Text(model.list.title(for: day.day))
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(DurationText.clock(day.totalSeconds(at: model.clock.now))).monospacedDigit()
                    }
                }
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

    private var archived: Bool {
        listing.project?.isArchived ?? false
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(listing.entry.task.isEmpty ? "No task" : listing.entry.task)
                    .foregroundStyle(listing.entry.task.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                if model.badged.contains(listing.id) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Adjusted")
                        .accessibilityIdentifier("row.badge.\(listing.id)")
                }
            }
            HStack(spacing: 6) {
                AreaDot(color: listing.area?.color)
                Text(listing.project?.name ?? "No project")
                    .foregroundStyle(archived || listing.project == nil ? .secondary : .primary)
                if let client = listing.client?.name {
                    Text("· \(client)").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .lineLimit(1)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            labels
            Spacer(minLength: 8)
            Text(DurationText.clock(listing.entry.seconds(at: model.clock.now))).monospacedDigit()
            Button {
                Task { await model.timer.continueEntry(listing.id) }
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(CircleButtonStyle(color: .startGreen, diameter: 36))
            .accessibilityLabel("Continue")
            .accessibilityIdentifier("row.continue.\(listing.id)")
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openEditor(listing.id) }
        .accessibilityAddTraits(.isButton)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("row.\(listing.id)")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button("Continue", systemImage: "play.fill") {
                Task { await model.timer.continueEntry(listing.id) }
            }
            .tint(.startGreen)
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
