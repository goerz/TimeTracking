// MenuHeaderView: the status menu's disabled header lines as one view, so
// the task, details, and glyphs keep their styles (menubar.md §2.1,
// design.md §8).

import SwiftUI

/// Consecutive header lines of the status menu.
struct MenuHeaderView: View {
    var lines: [MenuHeaderLine]

    /// The menu's text inset, so the header lines up with the items' titles.
    static let inset: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, Design.Spacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func row(_ line: MenuHeaderLine) -> some View {
        HStack(spacing: Design.Spacing.compact) {
            if let dot = line.dot {
                AreaDot(color: dot.isEmpty ? nil : dot, size: 8)
                    .frame(width: 14)
            } else if let symbol = line.symbol {
                Image(symbol: symbol)
                    .foregroundStyle(line.style == .warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
                    .frame(width: 14)
            }
            text(line)
                .lineLimit(1)
        }
    }

    private func text(_ line: MenuHeaderLine) -> Text {
        let main = Text(line.text)
        let secondary = Text(line.secondary ?? "").foregroundStyle(.secondary)
        return switch line.style {
        case .title: Text("\(main)\(secondary)").font(.headline)
        case .primary: Text("\(main)\(secondary)").monospacedDigit()
        case .secondary: Text("\(main)\(secondary)").foregroundStyle(.secondary).monospacedDigit()
        case .warning: Text("\(main)\(secondary)")
        }
    }
}
