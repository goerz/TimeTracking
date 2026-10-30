// PinnedProjectsScreen: the ordered pinned list of Settings > Widgets
// (spec_ios.md §2.9, §3.4): add from the picker, reorder, remove.

import SwiftUI
import TimeTrackingCore

struct PinnedProjectsScreen: View {
    var pinned: PinnedProjectsModel
    var store: TimeStore

    @State private var picker: ProjectPickerModel?

    var body: some View {
        List {
            ForEach(pinned.rows) { row in
                HStack(spacing: Design.Spacing.small) {
                    AreaDot(color: row.area?.color, size: 8)
                    Text(row.project.name)
                }
            }
            .onMove { source, destination in Task { await pinned.move(from: source, to: destination) } }
            .onDelete { offsets in Task { await pinned.remove(at: offsets) } }
        }
        .overlay {
            if pinned.rows.isEmpty {
                ContentUnavailableView {
                    Label("No Pinned Projects", systemImage: "pin")
                } description: {
                    Text("Pinned projects appear as buttons in the Pinned widget.")
                } actions: {
                    addButton
                }
            }
        }
        .navigationTitle("Pinned Projects")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showPicker()
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
                .accessibilityIdentifier("settings.addPinned")
            }
            if !pinned.rows.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .sheet(item: $picker) { picker in
            NavigationStack {
                ProjectPickerView(model: picker) { choice in
                    self.picker = nil
                    if case let .project(id?) = choice {
                        Task { await pinned.add(id) }
                    }
                } onCancel: {
                    self.picker = nil
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var addButton: some View {
        Button("Add Project") { showPicker() }
            .buttonStyle(.borderedProminent)
    }

    private func showPicker() {
        picker = ProjectPickerModel(store: store, currentProject: nil, taskMatching: false)
    }
}
