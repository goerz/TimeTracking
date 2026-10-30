// BlockCard: an activity block with its hover button, menu, and popover
// (spec_planner_calendar.md §3.1, §3.2, §3.3, §3.4).

import SwiftUI
import TimeTrackingCore

/// A pale card with the dominant context's color as left border (§3.1).
struct BlockCard: View {
    var model: CalendarModel
    var block: ActivityBlock
    var size: CGSize
    @State private var hovering = false
    @State private var showsPopover = false
    @State private var hoverTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let selected = model.selection.contains(.block(block.id))
        let tint = ContextColorLookup(colors: model.contextColors, dark: colorScheme == .dark)
            .color(block.items.first?.context ?? block.groupKey)
        let style = CalendarZoom.cardStyle(height: Double(size.height))
        ZStack(alignment: .topLeading) {
            if block.source == .knowledge {
                RoundedRectangle(cornerRadius: Design.Radius.small).fill(Hatch.paint(tint.opacity(0.3), on: tint.opacity(0.1)))
            } else {
                RoundedRectangle(cornerRadius: Design.Radius.small).fill(tint.opacity(0.18))
            }
            coveredDimming
            Rectangle().fill(tint).frame(width: 3)
            if style != .bar, !CalendarColumn.drawsBars(width: Double(size.width + 4)) {
                label(style)
            }
            if hovering {
                Button { Task { await model.createEntry(from: block) } } label: { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(tint)
                    .padding(Design.Spacing.tight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .help("Create Entry…")
                    .accessibilityLabel("Create Entry")
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: Design.Radius.small))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.small).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
        .phaseAnimator([false, true], trigger: model.isHighlighted(block)) { view, phase in
            view.scaleEffect(model.isHighlighted(block) && phase ? 1.04 : 1)
        }
        .onHover(perform: hover)
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            model.select(.block(block.id))
            showsPopover = true
        }
        .draggable("block:\(block.id)")
        .contextMenu { menu }
        .popover(isPresented: $showsPopover) { BlockPopover(model: model, block: block) }
        .accessibilityIdentifier("calendar.block")
    }

    private var coveredDimming: some View {
        ForEach(model.coveredParts(of: block), id: \.self) { part in
            let axis = model.axis(TrackingDay(block.localDay) ?? model.today)
            Rectangle().fill(.background.opacity(0.5))
                .frame(height: CGFloat(part.duration * model.pointsPerHour / 3600))
                .offset(y: CGFloat(axis.y(part.start) - axis.y(block.start)))
        }
    }

    /// The group key and share, then (full height) the dominant item.
    private func label(_ style: CalendarZoom.CardStyle) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: Design.Spacing.tight) {
                Text(block.groupKey).fontWeight(.semibold)
                Text("\(Int((block.groupShare * 100).rounded()))%").foregroundStyle(.secondary).monospacedDigit()
                glyphs
            }
            if style == .full {
                Text([block.items.first?.subject, block.items.first?.detail].compactMap(\.self).filter { !$0.isEmpty }
                    .joined(separator: " "))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption).lineLimit(1)
        .padding(.leading, Design.Spacing.small)
        .padding(.trailing, Design.Spacing.tight)
        .padding(.vertical, style == .full ? Design.Spacing.tight : 0)
    }

    @ViewBuilder private var glyphs: some View {
        if block.background.count + max(0, block.items.count - 1) > 0, !block.background.isEmpty {
            Text("+\(block.background.count)").foregroundStyle(.secondary)
        }
        if block.source == .device {
            Image(systemName: "iphone").imageScale(.small).accessibilityHidden(true)
        }
        if block.device == "remote" {
            Image(systemName: "cloud").imageScale(.small).accessibilityHidden(true)
        }
    }

    private func hover(_ inside: Bool) {
        hovering = inside
        hoverTask?.cancel()
        if inside {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled {
                    showsPopover = true
                }
            }
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Create Entry…") { Task { await model.createEntry(from: block) } }
        if block.isOpen {
            Button("Start Now") { Task { await model.startNow(block) } }
        }
        Menu("Always Use Project…") {
            ForEach(model.projects.filter { !$0.isArchived && !$0.isDeleted }) { project in
                Button(project.name) { Task { await model.alwaysUseProject(project.id, for: block) } }
            }
        }
        Button("Ignore This Group Key…") { Task { await model.ignoreGroupKey(of: block) } }
        if model.canDeleteFromLog(block) {
            Divider()
            Button("Delete Block from Log…", role: .destructive) { model.confirmDeleteFromLog(block) }
        }
    }
}
