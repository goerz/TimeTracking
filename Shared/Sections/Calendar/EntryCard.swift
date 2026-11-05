// EntryCard: an entry card with its gestures, menu, and popovers
// (spec_calendar.md §2.1, §2.4, §2.5, §2.6, §5).

import SwiftUI
import TimeTrackingCore

/// An entry card: area color, task, "Project · Client", duration; drag to
/// move, top and bottom 6 pt to resize.
struct EntryCard: View {
    var model: CalendarModel
    var listing: EntryListing
    /// The column: an entry across Midnight has a card on each of its days.
    var day: TrackingDay
    var size: CGSize
    /// The card's top left corner from the day's left edge and the columns' top.
    var origin: CGPoint
    @State private var dragOffset: CGSize = .zero
    /// The start a drag would give, the card's time label (§2.4).
    @State private var dragStart: Date?
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
        let overlaps = model.overlapping(on: day).contains(entry.id)
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
        // Nothing of the card is drawn outside its time range (§2.1).
        .clipShape(.rect(cornerRadius: Design.Radius.small))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.small).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.small)
            .strokeBorder(textColor.opacity(entry.isRunning ? 0.5 : 0), lineWidth: 1.5))
        .offset(y: edgeOffsets.top)
        .overlay {
            if Self.touch, selected {
                touchHandles
            }
        }
        .overlay(alignment: .topLeading) {
            if let dragStart, !model.cardDragCancelled {
                CalendarDragTime(time: dragStart, zone: model.calendar.timeZone)
            }
        }
        .offset(model.cardDragCancelled ? .zero : dragOffset)
        // Faded while the Filters or the search leave it out (§1.6).
        .opacity(model.passesFilters(listing) ? 1 : 0.25)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(.isButton)
        .cardClicks { model.click(.entry(entry.id)) } onDoubleClick: { model.editingEntry = entry.id }
        .calendarDrag(minimumDistance: 4, onLongPress: longPressed) { drag in
            guard model.continueCardDrag(.entry(entry.id), on: day, from: drag.start) else {
                return
            }
            dragOffset = drag.translation
            dragStart = trackedDay(under: drag).flatMap { target in
                model.movedInterval(of: entry, by: seconds(drag), to: target, from: day, option: ModifierState.optionDown())?.start
            }
        } onEnded: { drag in
            dragOffset = .zero
            dragStart = nil
            guard model.finishCardDrag(), let target = trackedDay(under: drag) else {
                return
            }
            let option = ModifierState.optionDown()
            Task { await model.move(entry.id, by: seconds(drag), to: target, from: day, option: option) }
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
        let oneLine = HStack(spacing: Design.Spacing.tight) {
            title
            duration.opacity(0.85)
        }
        .font(.caption).foregroundStyle(textColor).lineLimit(1)
        .padding(.horizontal, Design.Spacing.tight + 2)
        switch CalendarZoom.cardStyle(height: Double(size.height)) {
        case .bar:
            EmptyView()
        case .oneLine:
            oneLine
        case .full:
            // Three lines only where they fit (about 48 points at the
            // default text size), else the one line (§1.3).
            ViewThatFits(in: .vertical) {
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
                oneLine
            }
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
                guard model.continueCardDrag(.entry(entry.id), on: day, from: drag.start) else {
                    edgeOffsets = (0, 0)
                    return
                }
                if top {
                    edgeOffsets.top = drag.translation.height
                } else {
                    edgeOffsets.bottom = drag.translation.height
                }
            } onEnded: { drag in
                edgeOffsets = (0, 0)
                if model.finishCardDrag() {
                    resize(top: top, by: drag.translation.height)
                }
            }
            .accessibilityIdentifier(top ? "calendar.entry.topHandle" : "calendar.entry.bottomHandle")
    }

    private func resizeGesture(top: Bool) -> some Gesture {
        DragGesture(minimumDistance: 2).onChanged { value in
            _ = model.continueCardDrag(.entry(entry.id), on: day, from: value.startLocation)
        }.onEnded { value in
            if model.finishCardDrag() {
                resize(top: top, by: value.translation.height)
            }
        }
    }

    /// The seconds a drag moves the card by.
    private func seconds(_ drag: CalendarDrag) -> TimeInterval {
        Double(drag.translation.height) / model.pointsPerHour * 3600
    }

    /// The day whose Tracked column lies under the pointer, if one does.
    private func trackedDay(under drag: CalendarDrag) -> TrackingDay? {
        let point = CGPoint(x: origin.x + drag.location.x, y: origin.y + drag.location.y)
        guard let target = model.dropTarget(from: day, at: point), target.column == .tracked else {
            return nil
        }
        return target.day
    }

    private func resize(top: Bool, by translation: CGFloat) {
        // The card's edge, which is the column's where the entry goes on.
        let interval = entry.interval(at: model.clock.now)
        let column = model.axis(day).interval
        let edge = top ? max(interval.start, column.start) : min(interval.end, column.end)
        let date = edge + Double(translation) / model.pointsPerHour * 3600
        let option = ModifierState.optionDown()
        Task { await model.resize(entry.id, top: top, to: date, on: day, option: option) }
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
