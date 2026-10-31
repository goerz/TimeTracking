// EntryCard: an entry card with its gestures, menu, and popovers
// (spec_planner_calendar.md §2.1, §2.4, §2.5, §2.6, §6).

import SwiftUI
import TimeTrackingCore

/// An entry card: area color, task, "Project · Client", duration; drag to
/// move, top and bottom 6 pt to resize.
struct EntryCard: View {
    var model: CalendarModel
    var listing: EntryListing
    var size: CGSize
    var dayWidth: CGFloat
    @State private var dragOffset: CGSize = .zero
    @State private var hovering = false
    /// The iPad's long-press menu.
    @State private var showsMenu = false
    /// The iPad's resize preview offsets of the top and bottom edges.
    @State private var edgeOffsets: (top: CGFloat, bottom: CGFloat) = (0, 0)

    private var entry: TimeEntry {
        listing.entry
    }

    var body: some View {
        let selected = model.selection.contains(.entry(entry.id))
        let color = listing.area?.color
        let overlaps = model.overlapping(on: entry.day).contains(entry.id)
        let textColor = cardTextColor(color)
        let style = CalendarZoom.cardStyle(height: Double(size.height))
        let wanted = hovering || entry.isRunning || (Self.touch && selected)
        // Wide cards give the buttons their own place at the top right, so
        // the text truncates before them; narrow, tall cards put them at the
        // bottom right, below the text.
        let wide = size.width >= 140
        let atBottom = !wide && style == .full && size.height >= 64
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Design.Radius.small)
                .fill(color.map { Color(hex: $0) } ?? Color.gray.opacity(0.5))
            HStack(alignment: .top, spacing: Design.Spacing.tight) {
                content(textColor: textColor)
                Spacer(minLength: 0)
                if overlaps {
                    Image(systemName: SymbolName.warningFill)
                        .font(.caption)
                        .foregroundStyle(textColor)
                        .padding(.top, Design.Spacing.tight)
                        .help(overlapHelp)
                        .accessibilityLabel(overlapHelp)
                }
                if wanted, wide, style != .bar {
                    hoverButtons(textColor: textColor)
                }
            }
            if wanted, atBottom {
                hoverButtons(textColor: textColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            if !Self.touch {
                edgeHandles
            }
        }
        .frame(width: max(2, size.width - 2), height: max(4, size.height - edgeOffsets.top + edgeOffsets.bottom))
        .offset(y: edgeOffsets.top)
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.small).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.small)
            .strokeBorder(textColor.opacity(entry.isRunning ? 0.5 : 0), lineWidth: 1.5))
        .overlay {
            if Self.touch, selected {
                touchHandles
            }
        }
        .offset(dragOffset)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(.isButton)
        .onTapGesture(count: 2) { model.editingEntry = entry.id }
        .onTapGesture { model.select(.entry(entry.id), extend: ModifierState.optionDown()) }
        .calendarDrag(minimumDistance: 4, onLongPress: longPressed) { drag in
            dragOffset = drag.translation
        } onEnded: { drag in
            dragOffset = .zero
            let days = Int((drag.translation.width / dayWidth).rounded())
            let seconds = Double(drag.translation.height) / model.pointsPerHour * 3600
            Task { await model.move(entry.id, by: seconds, to: entry.day.adding(days: days)) }
        }
        .modifier(EntryMenu(showsMenu: $showsMenu) { menu })
        .modifier(EntryEditorPopover(
            entry: entry,
            editing: Bindable(model).editingEntry,
            store: model.store,
            clock: model.clock,
            arrowEdge: .trailing,
            opensOnAppear: true
        ) { await model.changed() })
        .popover(isPresented: overlapBinding, arrowEdge: .trailing) { OverlapPopover(model: model) }
        .help("\(listing.entry.task) · \(ProjectLabel(listing).projectAndClient)")
        .accessibilityIdentifier("calendar.entry")
    }

    @ViewBuilder
    private func content(textColor: Color) -> some View {
        let label = ProjectLabel(listing)
        // Running: h:mm:ss, ticking; otherwise "1h 33m" (spec_design.md §2).
        let duration = TimelineView(.periodic(from: .now, by: 1)) { _ in
            let seconds = entry.seconds(at: model.clock.now)
            Text(entry.isRunning ? DurationText.clock(seconds) : ActivityText.duration(seconds)).monospacedDigit()
        }
        let title = Text(entry.task.isEmpty ? "No task" : entry.task)
            .fontWeight(.semibold)
            .italic(entry.task.isEmpty)
        switch CalendarZoom.cardStyle(height: Double(size.height)) {
        case .bar:
            EmptyView()
        case .oneLine:
            HStack(spacing: Design.Spacing.tight) {
                title
                duration.opacity(0.85)
            }
            .font(.caption).foregroundStyle(textColor).lineLimit(1)
            .padding(.horizontal, Design.Spacing.tight + 2)
        case .full:
            VStack(alignment: .leading, spacing: 1) {
                title
                Text(label.projectAndClient).opacity(0.85)
                HStack(spacing: 2) {
                    Image(systemName: SymbolName.timer).imageScale(.small).accessibilityHidden(true)
                    duration
                }
                .opacity(0.85)
            }
            .font(.caption).foregroundStyle(textColor).lineLimit(1)
            .padding(.horizontal, Design.Spacing.tight + 2)
            .padding(.vertical, Design.Spacing.tight)
        }
    }

    /// Stop on the running entry (always shown), Continue otherwise, and
    /// Edit, on hover; drawn in the card's text color.
    private func hoverButtons(textColor: Color) -> some View {
        HStack(spacing: 2) {
            if entry.isRunning {
                Button { Task { await model.stopRunning() } } label: { Image(systemName: SymbolName.stopCircle) }
                    .foregroundStyle(.white, Color.stopTint)
                    .help("Stop")
                    .accessibilityLabel("Stop")
            } else {
                Button { Task { await model.continueEntry(entry.id) } } label: { Image(systemName: SymbolName.startCircle) }
                    .foregroundStyle(textColor.opacity(0.9))
                    .help("Continue")
                    .accessibilityLabel("Continue")
            }
            if hovering || Self.touch {
                Button { model.editingEntry = entry.id } label: { Image(systemName: SymbolName.moreCircle) }
                    .foregroundStyle(textColor.opacity(0.9))
                    .help("Edit")
                    .accessibilityLabel("Edit")
            }
        }
        .font(.callout)
        .buttonStyle(.plain)
        .padding(Design.Spacing.tight)
    }

    /// The top and bottom 6 points resize (no bottom handle while running).
    private var edgeHandles: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 6).contentShape(Rectangle()).gesture(resizeGesture(top: true))
            Spacer(minLength: 0)
            if !entry.isRunning {
                Color.clear.frame(height: 6).contentShape(Rectangle()).gesture(resizeGesture(top: false))
            }
        }
    }

    /// Whether the touch equivalents apply (spec_ios.md §10.2).
    static var touch: Bool {
        #if os(iOS)
            true
        #else
            false
        #endif
    }

    /// The iPad's long press without a drag: select and open the menu.
    private var longPressed: (() -> Void)? {
        guard Self.touch else {
            return nil
        }
        return {
            model.select(.entry(entry.id))
            showsMenu = true
        }
    }

    /// The iPad's 44-point handles centered on the top and bottom edges
    /// (none at the bottom while running).
    private var touchHandles: some View {
        VStack(spacing: 0) {
            handle(top: true).offset(y: -CalendarTouch.handleHeight / 2 + edgeOffsets.top)
            Spacer(minLength: 0)
            if !entry.isRunning {
                handle(top: false).offset(y: CalendarTouch.handleHeight / 2 + edgeOffsets.bottom)
            }
        }
    }

    private func handle(top: Bool) -> some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: 28, height: 6)
            .frame(maxWidth: .infinity)
            .frame(height: CalendarTouch.handleHeight)
            .contentShape(Rectangle())
            .calendarDirectDrag { drag in
                if top {
                    edgeOffsets.top = drag.translation.height
                } else {
                    edgeOffsets.bottom = drag.translation.height
                }
            } onEnded: { drag in
                edgeOffsets = (0, 0)
                resize(top: top, by: drag.translation.height)
            }
            .accessibilityIdentifier(top ? "calendar.entry.topHandle" : "calendar.entry.bottomHandle")
    }

    private func resizeGesture(top: Bool) -> some Gesture {
        DragGesture(minimumDistance: 2).onEnded { value in
            resize(top: top, by: value.translation.height)
        }
    }

    private func resize(top: Bool, by translation: CGFloat) {
        let interval = entry.interval(at: model.clock.now)
        let edge = top ? interval.start : interval.end
        let date = edge + Double(translation) / model.pointsPerHour * 3600
        Task { await model.resize(entry.id, top: top, to: date) }
    }
}

/// The context menu, the overlap tooltip, and the overlap popover's binding.
extension EntryCard {
    @ViewBuilder private var menu: some View {
        Button("Continue") { Task { await model.continueEntry(entry.id) } }
        Button("Edit…") { model.editingEntry = entry.id }
        Button("Split Here") {
            Task { await model.split(entry.id, at: entry.start + entry.interval(at: model.clock.now).duration / 2) }
        }
        Button("Duplicate to Next Day") {
            model.selection = [.entry(entry.id)]
            Task { await model.duplicateSelection() }
        }
        Button("Delete", role: .destructive) {
            model.selection = [.entry(entry.id)]
            Task { await model.deleteSelection() }
        }
    }

    private var overlapHelp: String {
        model.overlapHelp(for: entry)
    }

    private var overlapBinding: Binding<Bool> {
        Binding {
            if case let .change(id) = model.pendingOverlap?.action {
                return id == entry.id
            }
            return false
        } set: { shown in
            if !shown {
                Task { await model.resolveOverlap(.cancel) }
            }
        }
    }
}
