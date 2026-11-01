// ProjectPickerView: the shared project picker (spec_projects.md §5).

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

    #if os(macOS)
        /// Vertical row padding: standard menu rows on the Mac.
        private static let rowPadding: CGFloat = 5
    #else
        /// Vertical row padding: 44 pt touch targets on iOS.
        private static let rowPadding: CGFloat = 11
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsSearchField {
                searchField
                    .padding(.horizontal, Design.Spacing.small + 2)
                    .padding(.vertical, Design.Spacing.small + 2)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    rows.padding(.vertical, Design.Spacing.compact)
                }
                .onChange(of: model.highlight) { _, highlight in
                    if let highlight {
                        proxy.scrollTo(highlight, anchor: nil)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 340)
        .frame(maxHeight: 440)
        .fixedSize(horizontal: false, vertical: true)
        #endif
        .task { await model.reload() }
        .accessibilityIdentifier("picker")
    }

    private var searchField: some View {
        HStack(spacing: Design.Spacing.tight + 2) {
            Image(systemName: SymbolName.search).foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(model.placeholder, text: $model.search)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .accessibilityIdentifier("picker.search")
        }
        .padding(.horizontal, Design.Spacing.small)
        .padding(.vertical, searchPadding)
        .background(RoundedRectangle(cornerRadius: searchRadius).fill(.fill.tertiary))
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
                Divider().padding(.vertical, Design.Spacing.tight)
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
            Label("Create Project “\(name)”", systemImage: SymbolName.add)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Design.Spacing.medium)
                .padding(.vertical, Self.rowPadding)
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
            .padding(.top, Design.Spacing.small)
            .padding(.bottom, 2)
    }

    private func row(_ item: ProjectPickerItem, dot: String?, name: String, trailing: String, checked: Bool) -> some View {
        let highlighted = model.highlight == item
        return Button {
            onChoose(model.choice(for: item))
        } label: {
            HStack(spacing: Design.Spacing.small) {
                Image(systemName: SymbolName.checkmark)
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
            .padding(.horizontal, Design.Spacing.medium)
            .padding(.vertical, Self.rowPadding)
            .background(highlightBackground(item))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(item)
        .accessibilityIdentifier(Self.identifier(for: item))
    }

    #if os(macOS)
        private var searchPadding: CGFloat {
            Design.Spacing.tight + 1
        }

        private var searchRadius: CGFloat {
            Design.Radius.small
        }
    #else
        private var searchPadding: CGFloat {
            Design.Spacing.small + 1
        }

        private var searchRadius: CGFloat {
            Design.Radius.card
        }
    #endif

    private func highlightBackground(_ item: ProjectPickerItem) -> some View {
        RoundedRectangle(cornerRadius: Design.Radius.small)
            .fill(model.highlight == item ? Color.accentColor : .clear)
            .padding(.horizontal, Design.Spacing.compact)
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
