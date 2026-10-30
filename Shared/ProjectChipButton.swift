// ProjectChipButton: the project chip of the Timer bar, the iOS Timer card,
// and the entry editor (spec_design.md §7).

import SwiftUI

/// A bordered capsule: area dot, project, " · client" in secondary, and the
/// popup chevron. "No project" shows a hollow dot.
struct ProjectChipButton: View {
    var label: ProjectLabel
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing.tight + 2) {
                AreaDot(color: label.color)
                label.text(dimmed: label.isNone).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .truncationMode(.tail)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        #if os(macOS)
            .controlSize(.small)
        #else
            // Gray, not the accent color: the chip shows data, not a link.
            .tint(.primary)
        #endif
            .accessibilityLabel(label.projectAndClient)
            .accessibilityHint("Choose a project")
    }
}

extension ProjectLabel {
    /// "Project · Client" with the client in secondary; the project too
    /// when `dimmed` (no project, archived).
    func text(dimmed: Bool = false) -> Text {
        let project = Text(name).foregroundStyle(dimmed ? .secondary : .primary)
        guard let client else {
            return project
        }
        return Text("\(project)\(Text(" · \(client)").foregroundStyle(.secondary))")
    }
}
