// CalendarCards: entry, draft, activity block, time block, and event cards
// with their gestures, menus, and popovers (spec_planner_calendar.md §2.1,
// §2.4, §2.5, §3.1, §3.2, §4.2, §4.3, §6).

import SwiftUI
import TimeTrackingCore

/// The text color on an area color (§4.4 of the Projects spec).
func cardTextColor(_ hex: String?) -> Color {
    guard let hex, let color = try? AreaColor(hex) else {
        return .primary
    }
    return color.textColor == .black ? .black : .white
}

// MARK: Entries

/// An entry card: area color, task, "Project · Client", duration; drag to
/// move, top and bottom 6 pt to resize.
struct EntryCard: View {
    var model: CalendarModel
    var listing: EntryListing
    var size: CGSize
    var dayWidth: CGFloat
    @State private var dragOffset: CGSize = .zero
    @State private var hovering = false
    @State private var editor: EntryEditorModel?
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
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(color.map { Color(hex: $0) } ?? Color.gray.opacity(0.5))
            content(textColor: cardTextColor(color))
            if hovering || entry.isRunning || (Self.touch && selected) {
                hoverButtons.frame(maxWidth: .infinity, alignment: .topTrailing).padding(3)
            }
            if overlaps {
                Text("⚠").font(.caption).help(overlapHelp).frame(maxWidth: .infinity, alignment: .topTrailing).padding(.trailing, 24)
            }
            if !Self.touch {
                edgeHandles
            }
        }
        .frame(width: max(2, size.width - 2), height: max(4, size.height - edgeOffsets.top + edgeOffsets.bottom))
        .offset(y: edgeOffsets.top)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(entry.isRunning ? 0.9 : 0), lineWidth: 2))
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
        .popover(isPresented: editingBinding, arrowEdge: .trailing) {
            if let editor {
                EntryEditorView(model: editor, makePicker: makePicker) { model.editingEntry = nil }
            }
        }
        .popover(isPresented: overlapBinding, arrowEdge: .trailing) { OverlapPopover(model: model) }
        .onChange(of: model.editingEntry, initial: true) { _, editing in
            if editing == entry.id {
                let editor = EntryEditorModel(store: model.store, clock: model.clock, entry: entry)
                editor.onChange = { await model.changed() }
                editor.onDelete = { model.editingEntry = nil }
                self.editor = editor
            }
        }
        .help("\(listing.entry.task) · \(ProjectLabel(listing).projectAndClient)")
        .accessibilityIdentifier("calendar.entry")
    }

    @ViewBuilder
    private func content(textColor: Color) -> some View {
        let label = ProjectLabel(listing)
        let duration = TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(entry.isRunning ? DurationText.clock(entry.seconds(at: model.clock.now)) : DurationText
                .hoursMinutes(entry.seconds(at: model.clock.now)))
        }
        switch CalendarZoom.cardStyle(height: Double(size.height)) {
        case .bar:
            EmptyView()
        case .oneLine:
            HStack(spacing: 4) {
                Text(entry.task.isEmpty ? "No task" : entry.task).bold().italic(entry.task.isEmpty)
                duration
            }
            .font(.caption).foregroundStyle(textColor).lineLimit(1).padding(.horizontal, 4)
        case .full:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.task.isEmpty ? "No task" : entry.task).bold().italic(entry.task.isEmpty)
                Text(label.projectAndClient).opacity(0.85)
                HStack(spacing: 2) {
                    Image(systemName: "stopwatch").accessibilityHidden(true)
                    duration
                }
            }
            .font(.caption).foregroundStyle(textColor).lineLimit(1).padding(4)
        }
    }

    private var hoverButtons: some View {
        HStack(spacing: 3) {
            if entry.isRunning {
                Button { Task { await model.stopRunning() } } label: { Image(systemName: "stop.circle.fill") }
                    .accessibilityLabel("Stop")
            } else {
                Button { Task { await model.continueEntry(entry.id) } } label: { Image(systemName: "play.circle.fill") }
                    .accessibilityLabel("Continue")
            }
            Button { model.editingEntry = entry.id } label: { Image(systemName: "ellipsis.circle.fill") }
                .accessibilityLabel("Edit")
        }
        .buttonStyle(.plain)
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
        let others = model.entries(on: entry.day).filter { other in
            other.entry.id != entry.id && other.entry.interval(at: model.clock.now).intersection(with: entry.interval(at: model.clock.now))
                .map { $0.duration > 0 } ?? false
        }
        return "Overlaps " + others.map { other in
            let minutes =
                Int((other.entry.interval(at: model.clock.now).intersection(with: entry.interval(at: model.clock.now))?.duration ?? 0) / 60)
            return "\"\(other.entry.task)\" by \(minutes) min"
        }.joined(separator: ", ")
    }

    private var editingBinding: Binding<Bool> {
        Binding { model.editingEntry == entry.id && editor != nil } set: { shown in
            if !shown {
                model.editingEntry = nil
            }
        }
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

    private func makePicker(_ current: ProjectID?) -> ProjectPickerModel {
        ProjectPickerModel(store: model.store, currentProject: current, taskMatching: false)
    }
}

/// The provisional entry with a dashed border and the edit popover.
struct DraftCard: View {
    var model: CalendarModel
    var size: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.1)))
            .frame(width: size.width, height: size.height)
            .popover(isPresented: draftBinding, arrowEdge: .trailing) { DraftEditor(model: model) }
            .popover(isPresented: overlapBinding, arrowEdge: .trailing) { OverlapPopover(model: model) }
            .accessibilityIdentifier("calendar.draft")
    }

    private var draftBinding: Binding<Bool> {
        Binding { model.draft != nil && model.pendingOverlap == nil } set: { shown in
            if !shown {
                Task { await model.dismissDraft(commit: true) }
            }
        }
    }

    private var overlapBinding: Binding<Bool> {
        Binding {
            if case .create = model.pendingOverlap?.action {
                return true
            }
            return false
        } set: { shown in
            if !shown {
                Task { await model.resolveOverlap(.cancel) }
            }
        }
    }
}

// MARK: Activity blocks

/// A pale card with the dominant context's color as left border (§3.1).
struct BlockCard: View {
    var model: CalendarModel
    var block: ActivityBlock
    var size: CGSize
    @State private var hovering = false
    @State private var showsPopover = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        let selected = model.selection.contains(.block(block.id))
        let border = ContextPalette.hex(model.contextColors[block.items.first?.context ?? block.groupKey], dark: false)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(block.source == .knowledge ? 0.1 : 0.16))
            coveredDimming
            Rectangle().fill(border.map { Color(hex: $0) } ?? .gray).frame(width: 3)
            if CalendarZoom.cardStyle(height: Double(size.height)) == .full, !CalendarColumn.drawsBars(width: Double(size.width)) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text("\(block.groupKey) \(Int((block.groupShare * 100).rounded()))%").bold()
                        glyphs
                    }
                    Text([block.items.first?.subject, block.items.first?.detail].compactMap(\.self).filter { !$0.isEmpty }
                        .joined(separator: " "))
                }
                .font(.caption2).lineLimit(1).padding(.leading, 6).padding(.top, 2)
            }
            if hovering {
                Button { Task { await model.createEntry(from: block) } } label: { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .accessibilityLabel("Create Entry")
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
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
            Rectangle().fill(Color.white.opacity(0.5))
                .frame(height: CGFloat(part.duration * model.pointsPerHour / 3600))
                .offset(y: CGFloat(axis.y(part.start) - axis.y(block.start)))
        }
    }

    @ViewBuilder private var glyphs: some View {
        if block.background.count + max(0, block.items.count - 1) > 0, !block.background.isEmpty {
            Text("+\(block.background.count)").font(.caption2)
        }
        if block.source == .device {
            Image(systemName: "iphone").accessibilityHidden(true)
        }
        if block.device == "remote" {
            Image(systemName: "cloud").accessibilityHidden(true)
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

// MARK: Time blocks and events

/// A time block (dashed area-color border) or an external event (calendar
/// color left border) piece.
struct EventCard: View {
    var model: CalendarModel
    var piece: CalendarPiece<CalendarEvent.ID>
    var size: CGSize
    @State private var dragOffset: CGFloat = 0
    @State private var showsMenu = false

    var body: some View {
        if let block = model.timeBlocks.first(where: { $0.id == piece.id }) {
            timeBlockCard(block)
        } else if let event = model.externalEvents.first(where: { $0.id == piece.id }) {
            eventCard(event)
        }
    }

    private func timeBlockCard(_ block: TimeBlock) -> some View {
        let project = model.project(block.link.projectID)
        let area = project.flatMap { project in model.entries.first { $0.project?.id == project.id }?.area?.color }
        let color = area.map { Color(hex: $0) } ?? .gray
        let selected = model.selection.contains(.timeBlock(block.id))
        return VStack(alignment: .leading, spacing: 1) {
            Text(block.title).bold()
            if let project {
                Text(project.name)
            }
            HStack(spacing: 2) {
                Image(systemName: "calendar").accessibilityHidden(true)
                Text(DurationText.hoursMinutes(Int(block.event.interval.duration)))
            }
        }
        .font(.caption2).lineLimit(1).padding(4)
        .frame(width: size.width - 2, height: size.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [4])))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
        .clipped()
        .offset(y: dragOffset)
        .accessibilityAddTraits(.isButton)
        .onTapGesture(count: 2) { model.editTimeBlock(block) }
        .onTapGesture { model.select(.timeBlock(block.id)) }
        .calendarDrag(minimumDistance: 4, onLongPress: EntryCard.touch ? { showsMenu = true } : nil) { drag in
            dragOffset = drag.translation.height
        } onEnded: { drag in
            dragOffset = 0
            Task { await model.moveTimeBlock(block.id, by: Double(drag.translation.height) / model.pointsPerHour * 3600) }
        }
        .draggable("timeBlock:\(block.id)")
        .help(timeBlockHelp(block))
        .modifier(EntryMenu(showsMenu: $showsMenu) {
            Button("Create Entry…") { Task { await model.createEntry(fromEvent: block.event, timeBlock: block) } }
            Button("Edit…") { model.editTimeBlock(block) }
            Button("Delete", role: .destructive) { Task { await model.deleteTimeBlocks([block.id]) } }
        })
        .accessibilityIdentifier("calendar.timeBlock")
    }

    private func timeBlockHelp(_ block: TimeBlock) -> String {
        if case let .unlinked(reason?) = block.link {
            return reason
        }
        return TimeBlockLink.visibleNotes(block.event.notes)
    }

    private func eventCard(_ event: CalendarEvent) -> some View {
        let color = Color(hex: model.color(of: event))
        return HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).bold().foregroundStyle(color)
                Text(CalendarText.range(event.start, event.end, zone: model.calendar.timeZone)).foregroundStyle(.secondary)
                if let location = event.location {
                    Text(location).foregroundStyle(.secondary)
                }
            }
            .font(.caption2).lineLimit(2).padding(4)
            Spacer(minLength: 0)
        }
        .frame(width: size.width - 2, height: size.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.08)))
        .clipped()
        .accessibilityAddTraits(.isButton)
        .onTapGesture(count: 2) { model.openEvent(event) }
        .onTapGesture { model.select(.event(event.id)) }
        .draggable("event:\(event.id)")
        .help("\(event.notes ?? "")\(event.attendeeCount > 0 ? "\n\(event.attendeeCount) attendees" : "")")
        .contextMenu {
            Button("Create Entry…") { Task { await model.createEntry(fromEvent: event, timeBlock: nil) } }
            Button("Open in Calendar") { model.openEvent(event) }
            Button("Hide This Calendar") { Task { await model.hideCalendar(of: event) } }
        }
        .accessibilityIdentifier("calendar.event")
    }
}

/// The context menu on the Mac; on the iPad, where a long press lifts the
/// item, the same buttons in a popover that a long press without a drag
/// opens (spec_ios.md §10.2).
private struct EntryMenu<Items: View>: ViewModifier {
    @Binding var showsMenu: Bool
    @ViewBuilder var items: () -> Items

    func body(content: Content) -> some View {
        #if os(iOS)
            content.popover(isPresented: $showsMenu) {
                VStack(alignment: .leading, spacing: 0) {
                    Group { items() }
                        .buttonStyle(.borderless)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .simultaneousGesture(TapGesture().onEnded { showsMenu = false })
                }
                .frame(minWidth: 220)
                .padding(.vertical, 6)
                .presentationCompactAdaptation(.popover)
                .accessibilityIdentifier("calendar.menu")
            }
        #else
            content.contextMenu { items() }
        #endif
    }
}
