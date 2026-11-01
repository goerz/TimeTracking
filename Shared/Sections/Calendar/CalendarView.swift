// CalendarView: the Calendar section's toolbar, summary strip, day headers,
// and day columns (spec_calendar.md §1).

import SwiftUI
import TimeTrackingCore

/// The Calendar section.
struct CalendarView: View {
    @Bindable var model: CalendarModel
    @Environment(\.undoManager) private var undoManager
    @State private var scrollPosition = ScrollPosition(y: 0)
    @State private var viewportHeight: CGFloat = 600
    @State private var pinchBase: Double?
    @State private var daysBase: Int?
    @State private var pickedDate = Date()

    static let gutter: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            CalendarSummaryStrip(model: model)
                .background { CalendarKeyHandlers(model: model) }
            Divider()
            GeometryReader { proxy in
                let dayWidth = max(60, (proxy.size.width - Self.gutter) / CGFloat(model.visibleDays))
                VStack(spacing: 0) {
                    headers(dayWidth: dayWidth)
                    Divider()
                    columns(dayWidth: dayWidth)
                }
                .onAppear { viewportHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, height in viewportHeight = height }
            }
        }
        .navigationTitle("Calendar")
        .navigationSubtitle(model.rangeLabel)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar { CalendarToolbar(model: model, pickedDate: $pickedDate) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calendar.view")
            .task {
                model.undoManager = undoManager
                await model.reload()
                await model.router?.consumeCalendarRequest()
                scrollToNow()
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

    private func headers(dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.gutter)
            ForEach(model.days, id: \.self) { day in
                CalendarDayHeader(model: model, day: day, width: dayWidth)
            }
        }
        // The gutter's clear color must not take half the height.
        .fixedSize(horizontal: false, vertical: true)
        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
            Task { await model.scrolled(dayWidths: -Double(value.translation.width / dayWidth)) }
        })
    }

    private func columns(dayWidth: CGFloat) -> some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                CalendarTimeAxis(model: model)
                    .frame(width: Self.gutter)
                ForEach(model.days, id: \.self) { day in
                    CalendarDayColumn(model: model, day: day, width: dayWidth)
                }
            }
        }
        .scrollPosition($scrollPosition)
        #if os(iOS)
            // Pinch vertically to zoom, horizontally to change the number of
            // days; two fingers sideways scroll days (spec_ios.md §10.2).
            .gesture(CalendarPinch { scale, horizontal in
                pinch(scale: scale, horizontal: horizontal)
            } onEnd: {
                pinchBase = nil
                daysBase = nil
            })
            .gesture(CalendarTwoFingerSwipe { translation in
                Task { await model.scrolled(dayWidths: -Double(translation / dayWidth)) }
            })
        #else
            .gesture(MagnifyGesture().onChanged { value in
                pinch(scale: value.magnification, horizontal: false)
            }.onEnded { _ in pinchBase = nil })
        #endif
    }

    private func pinch(scale: Double, horizontal: Bool) {
        if horizontal {
            let base = daysBase ?? model.visibleDays
            daysBase = base
            let count = min(7, max(1, Int((Double(base) / max(scale, 0.01)).rounded())))
            if count != model.visibleDays {
                Task { await model.setVisibleDays(count) }
            }
        } else {
            let base = pinchBase ?? model.pointsPerHour
            pinchBase = base
            model.pointsPerHour = CalendarZoom.clamped(base * scale)
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
