// ActivityPanels: the heatmap, bars by day, Contexts, Subjects, In the
// background, and Away panels in one or two columns
// (activity.md §1.4 to §1.8).

import SwiftUI
import TimeTrackingCore

/// The panels in two columns above 1100 points (the left one fits a
/// day-row heatmap: 24 cells of 14 pt with 3 pt gaps), one below.
struct ActivityPanels: View {
    var model: ActivityModel
    var summary: ActivitySummary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Design.Spacing.large) {
                VStack(spacing: Design.Spacing.large) {
                    HeatmapPanel(model: model, summary: summary)
                    ContextsPanel(model: model, summary: summary)
                    BackgroundPanel(summary: summary)
                }
                .frame(width: 564)
                VStack(spacing: Design.Spacing.large) {
                    BarsPanel(model: model, summary: summary)
                    SubjectsPanel(model: model)
                    AwayPanel(summary: summary)
                }
                .frame(width: 520)
            }
            VStack(spacing: Design.Spacing.large) {
                HeatmapPanel(model: model, summary: summary)
                BarsPanel(model: model, summary: summary)
                ContextsPanel(model: model, summary: summary)
                SubjectsPanel(model: model)
                BackgroundPanel(summary: summary)
                AwayPanel(summary: summary)
            }
        }
    }
}
