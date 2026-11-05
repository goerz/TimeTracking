// CalendarView: the Calendar section's toolbar, summary strip, day headers,
// day columns, and zoom control (spec_calendar.md §1).

import SwiftUI
import TimeTrackingCore

/// The Calendar section.
struct CalendarView: View {
    @Bindable var model: CalendarModel
    @Environment(\.undoManager) private var undoManager
    @State private var scrollPosition = ScrollPosition(y: 0)
    @State private var viewportHeight: CGFloat = 600
    /// Whether the opening scroll to the current time has happened.
    @State private var scrolledToNow = false
    /// The hours' scroll offset and visible height.
    @State private var hoursScroll = CGRect(x: 0, y: 0, width: 0, height: 600)
    /// Where a pinch began, in the visible hours.
    @State private var pinchY: CGFloat?
    /// A zoom's scroll offset, applied again once the content has its new
    /// height (the scroll view keeps its old offset when the content shrinks).
    @State private var zoomOffset: CGFloat?
    @State private var pinchBase: Double?
    @State private var dayWidthBase: Double?
    @State private var panTranslation: CGFloat = 0
    @State private var pickedDate = Date()
    @FocusState private var searchFocused: Bool

    static let gutter: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            if !model.filterChips.isEmpty {
                FilterChipBar(chips: model.filterChips, identifier: "calendar") { kind in
                    model.removeChip(kind)
                } clearAll: {
                    model.clearFilters()
                }
                .padding(.horizontal, Design.Spacing.content)
                .padding(.top, Design.Spacing.small)
            }
            CalendarSummaryStrip(model: model)
                .background { CalendarKeyHandlers(model: model) }
            Divider()
            VStack(spacing: 0) {
                headers
                Divider()
                columns
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                viewportChanged(to: size)
            }
            #if os(macOS)
            // Sideways trackpad and mouse scrolling moves through time.
            .background(HorizontalScrollMonitor { model.scroll(byPoints: Double($0), momentum: $1) })
            #endif
            .overlay(alignment: .bottomTrailing) {
                CalendarZoomControl(model: model)
                    // Clear of the vertical scroll bar.
                    .padding(.trailing, Design.Spacing.window)
                    .padding(.bottom, Design.Spacing.large)
            }
        }
        .navigationTitle("Calendar")
        .navigationSubtitle(model.rangeLabel)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar { CalendarToolbar(model: model, pickedDate: $pickedDate) }
            .searchable(text: $model.search, placement: .toolbar, prompt: "Search")
            .searchFocused($searchFocused)
            .onChange(of: model.searchFocusRequests) { searchFocused = true }
            .onChange(of: searchFocused) { _, focused in model.searchFocused = focused }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calendar.view")
            .task {
                model.undoManager = undoManager
                await model.reload()
                await model.router?.consumeCalendarRequest()
            }
            .task(id: model.router?.calendarRequest) {
                await model.router?.consumeCalendarRequest()
            }
            .task { await model.followActivity() }
            .task { await model.followEvents() }
            .onChange(of: model.scrollRequest?.serial) { _, _ in
                if let hour = model.scrollRequest?.hour {
                    scrollPosition.scrollTo(y: hour * model.pointsPerHour)
                }
            }
            .alert("Discard the running entry?", isPresented: $model.confirmsRunningDelete) {
                Button("Discard", role: .destructive) { Task { await model.deleteSelection(confirmed: true) } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Delete this activity?", isPresented: blockDeleteBinding, presenting: model.blockToDelete) { _ in
                Button("Delete", role: .destructive) { Task { await model.deleteBlockFromLog(confirmed: true) } }
                Button("Cancel", role: .cancel) { Task { await model.deleteBlockFromLog(confirmed: false) } }
                    .keyboardShortcut(.defaultAction)
            } message: { block in
                let range = CalendarText.range(block.start, block.end, zone: model.calendar.timeZone)
                Text("\(range) · \(ActivityContext.groupKeyName(block.groupKey))\nThis removes it on every device and cannot be undone.")
            }
            .alert(
                "Couldn't Delete This Activity",
                isPresented: .isPresent($model.trackerError),
                presenting: model.trackerError
            ) { _ in
                Button("OK") { model.trackerError = nil }
            } message: { Text($0) }
            .overlay(alignment: .bottom) { CalendarNoticeView(model: model) }
    }

    /// The day headers; dragging them sideways scrolls through time.
    private var headers: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.gutter)
                // Over a cut-off day, so the gutter keeps its clicks.
                .contentShape(Rectangle())
                .zIndex(1)
            CalendarDayStrip(model: model) { day, width in
                CalendarDayHeader(model: model, day: day, width: width)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // Alongside the headers' own clicks, which would otherwise take the drag.
        .simultaneousGesture(DragGesture(minimumDistance: 20).onChanged { value in
            model.scroll(byPoints: -Double(value.translation.width - panTranslation))
            panTranslation = value.translation.width
        }.onEnded { _ in panTranslation = 0 })
    }

    private var columns: some View {
        ScrollView(.vertical) {
            // Leading-aligned at the width the scroll view offers, so the
            // columns line up with the headers whether or not a scroll bar
            // takes room.
            HStack(alignment: .top, spacing: 0) {
                CalendarTimeAxis(model: model)
                    .frame(width: Self.gutter)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("calendar.timeAxis")
                    .contentShape(Rectangle())
                    .zIndex(1)
                CalendarDayStrip(model: model) { day, width in
                    CalendarDayColumn(model: model, day: day, width: width)
                }
            }
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in
            hoursScroll = rect
            model.visibleColumnsY = Double(rect.minY) ... Double(rect.maxY)
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, _ in
            if let zoomOffset {
                scrollPosition.scrollTo(y: zoomOffset)
                self.zoomOffset = nil
            }
        }
        .onChange(of: model.pointsPerHour) { old, new in keepTimeInPlace(from: old, to: new) }
        #if os(iOS)
            // Pinch vertically to zoom the hours, horizontally the day width;
            // a sideways swipe, with one finger or two, scrolls through time
            // (spec_ios.md §10.2).
            .gesture(CalendarPinch { scale, horizontal in
                pinch(scale: scale, horizontal: horizontal)
            } onEnd: {
                pinchBase = nil
                dayWidthBase = nil
            })
            .gesture(CalendarSidewaysPan { delta in
                model.scroll(byPoints: -Double(delta))
            } onEnded: { velocity in
                // The days coast on, slowing down, as a scroll view's would.
                withAnimation(.easeOut(duration: 0.45)) {
                    model.scroll(byPoints: -Double(velocity) * 0.2)
                }
            })
        #else
            .gesture(MagnifyGesture().onChanged { value in
                pinchY = value.startLocation.y
                pinch(scale: value.magnification, horizontal: false)
            }.onEnded { _ in
                pinchBase = nil
                pinchY = nil
            })
        #endif
    }

    private func pinch(scale: Double, horizontal: Bool) {
        if horizontal {
            let base = dayWidthBase ?? model.dayWidth
            dayWidthBase = base
            model.setDayWidth(base * scale)
        } else {
            let base = pinchBase ?? model.pointsPerHour
            pinchBase = base
            model.pointsPerHour = CalendarZoom.clamped(base * scale)
        }
    }

    /// A zoom of the hours keeps one time where it was on screen: under a
    /// pinch, else the now-line while it shows, else the center (§1.3).
    private func keepTimeInPlace(from old: Double, to new: Double) {
        let nowY = model.days.contains(model.today) ? model.axis(model.today).nowOffset(model.clock.now).map { $0 * old / new } : nil
        let offset = Double(hoursScroll.minY)
        let height = Double(hoursScroll.height)
        let hours = model.days.map { model.axis($0).interval.duration / 3600 }.max() ?? 24
        let anchor = CalendarZoom.anchor(offset: offset, viewportHeight: height, nowY: nowY, pinchY: pinchY.map(Double.init))
        let target = CalendarZoom.scrollOffset(offset, anchor: anchor, from: old, to: new, maximum: hours * new - height)
        scrollPosition.scrollTo(y: target)
        zoomOffset = CGFloat(target)
    }

    /// The viewport's new size; the opening position does not depend on
    /// the data, so it is taken as soon as the height is known.
    private func viewportChanged(to size: CGSize) {
        viewportHeight = size.height
        model.setViewportWidth(Double(size.width - Self.gutter))
        if !scrolledToNow, size.height > 0 {
            scrolledToNow = true
            // After this layout pass: a position set during it stays pending
            // and is applied again, undoing the user's scrolling.
            Task { scrollToNow() }
        }
    }

    /// On opening, the current time sits one third down the viewport.
    private func scrollToNow() {
        let axis = model.axis(model.today)
        if let offset = axis.nowOffset(model.clock.now) {
            scrollPosition.scrollTo(y: max(0, offset - viewportHeight / 3))
        }
    }

    private var blockDeleteBinding: Binding<Bool> {
        Binding { model.blockToDelete != nil } set: { shown in
            if !shown, model.blockToDelete != nil {
                Task { await model.deleteBlockFromLog(confirmed: false) }
            }
        }
    }
}
