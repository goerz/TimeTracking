// ProjectPickerView: the shared project picker (spec_planner_projects.md §5).

import SwiftUI
import TimeTrackingCore

/// The picker's list, with or without its own search field. On the Mac it is
/// a popover 340 pt wide and at most 440 pt tall.
struct ProjectPickerView: View {
    @Bindable var model: ProjectPickerModel
    /// Whether the picker has its own search field (not when opened by `@`).
    var showsSearchField = true
    var onChoose: (ProjectPickerChoice) -> Void
    var onCancel: () -> Void = {}

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsSearchField {
                searchField.padding(10)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    rows.padding(.vertical, 6)
                }
                .onChange(of: model.highlight) { _, highlight in
                    if let highlight {
                        proxy.scrollTo(highlight, anchor: nil)
                    }
                }
            }
        }
        .frame(width: 340)
        .frame(maxHeight: 440)
        .fixedSize(horizontal: false, vertical: true)
        .task { await model.reload() }
        .accessibilityIdentifier("picker")
    }

    private var searchField: some View {
        TextField(model.placeholder, text: $model.search)
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .accessibilityIdentifier("picker.search")
            .onAppear { searchFocused = true }
            .onChange(of: model.search) {
                Task { await model.reload() }
            }
            .onKeyPress(.upArrow) {
                model.moveHighlight(by: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                model.moveHighlight(by: 1)
                return .handled
            }
            .onKeyPress(.escape) {
                onCancel()
                return .handled
            }
            .onKeyPress(keys: [.return]) { press in
                let choice = press.modifiers.contains(.command) ? model.createFromSearch() : model.chooseHighlighted()
                if let choice {
                    onChoose(choice)
                }
                return .handled
            }
    }

    @ViewBuilder private var rows: some View {
        let content = model.content
        LazyVStack(alignment: .leading, spacing: 0) {
            if content.showsNoProject {
                row(.noProject, dot: nil, name: "No Project", trailing: "", checked: model.currentProject == nil)
            }
            if !content.recent.isEmpty {
                header("Recent")
                ForEach(content.recent) { row in
                    projectRow(.recent(row.id), row)
                }
            }
            ForEach(content.groups) { group in
                header(group.client.name)
                ForEach(group.rows) { row in
                    projectRow(.project(row.id), row)
                }
            }
            if let name = content.createName {
                Divider().padding(.vertical, 4)
                createRow(name)
            }
        }
    }

    private func projectRow(_ item: ProjectPickerItem, _ row: ProjectPickerRow) -> some View {
        self.row(item, dot: row.area.color, name: row.project.name, trailing: row.trailing, checked: row.id == model.currentProject)
    }

    private func createRow(_ name: String) -> some View {
        Button {
            onChoose(.create(name))
        } label: {
            Label("Create Project “\(name)”", systemImage: "plus")
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(highlightBackground(.create(name)))
        }
        .buttonStyle(.plain)
        .id(ProjectPickerItem.create(name))
        .accessibilityIdentifier("picker.create")
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 30)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func row(_ item: ProjectPickerItem, dot: String?, name: String, trailing: String, checked: Bool) -> some View {
        let highlighted = model.highlight == item
        return Button {
            onChoose(model.choice(for: item))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
                    .font(.caption.weight(.semibold))
                    .opacity(checked ? 1 : 0)
                    .frame(width: 12)
                AreaDot(color: dot)
                Text(name).lineLimit(1)
                Spacer(minLength: 8)
                Text(trailing)
                    .lineLimit(1)
                    .foregroundStyle(highlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
            }
            .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(highlightBackground(item))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(item)
        .accessibilityIdentifier(Self.identifier(for: item))
    }

    private func highlightBackground(_ item: ProjectPickerItem) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(model.highlight == item ? Color.accentColor : .clear)
            .padding(.horizontal, 6)
    }

    static func identifier(for item: ProjectPickerItem) -> String {
        switch item {
        case .noProject: "picker.noProject"
        case let .recent(id): "picker.recent.\(id)"
        case let .project(id): "picker.project.\(id)"
        case .create: "picker.create"
        }
    }
}
