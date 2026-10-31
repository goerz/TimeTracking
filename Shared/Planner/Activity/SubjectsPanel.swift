// SubjectsPanel: where the time went, by subject, with the drill-down
// (spec_planner_activity.md §1.6).

import SwiftUI
import TimeTrackingCore

/// "Where the time went": the subjects and their details (§1.6).
struct SubjectsPanel: View {
    @Bindable var model: ActivityModel

    var body: some View {
        ActivityPanel(title: "Where the time went") {
            Picker("Kind", selection: $model.subjectKind) {
                ForEach(ActivitySubjectKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let detail = model.drillDetail {
                drill(detail)
            } else {
                list
            }
        }
        .accessibilityIdentifier("activity.subjects")
    }

    @ViewBuilder private var list: some View {
        let rows = model.subjectRows
        let largest = rows.map(\.seconds).max() ?? 1
        ForEach(rows.prefix(model.showsAllSubjects ? rows.count : 20)) { row in
            HStack {
                ForEach(row.contexts.prefix(2), id: \.self) { ContextGlyph(context: $0) }
                Text(row.subject ?? "Other (brief activity)").foregroundStyle(row.subject == nil ? .secondary : .primary).lineLimit(1)
                Spacer()
                Capsule().fill(Color.accentColor).frame(width: 140 * CGFloat(row.seconds) / CGFloat(max(largest, 1)), height: 8)
                Text(ActivityText.duration(row.seconds)).frame(width: 64, alignment: .trailing)
                if model.isRecordingMac, row.hasDetails {
                    Image(systemName: SymbolName.next).accessibilityHidden(true).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isButton)
            .onTapGesture { model.open(row) }
            .contextMenu {
                if model.isRecordingMac, let subject = row.subject, row.contexts.contains(where: { ActivityContext($0).kind == .browser }) {
                    Button("Exclude \(ActivityContext.domain(ofSite: subject)) from Tracking…") { model.exclude(site: subject) }
                }
            }
        }
        if rows.count > 20, !model.showsAllSubjects {
            Button("Show all (\(rows.count))") { model.showsAllSubjects = true }.buttonStyle(.borderless)
        }
        if !model.isRecordingMac {
            Text("Details stay on the Mac that recorded them").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func drill(_ detail: ActivitySubjectDetail) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.compact) {
            HStack {
                Button(model.displayName(detail.context)) { model.closeDrill() }.buttonStyle(.borderless)
                Text("› \(detail.subject)")
                if let visited = detail.visitedText {
                    Text("· \(visited)").foregroundStyle(.secondary)
                }
            }
            if let coverage = detail.coverageText {
                Text(coverage).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(detail.lines) { line in
                HStack {
                    Text(line.detail).lineLimit(1)
                    Spacer()
                    Text(ActivityText.duration(line.seconds))
                }
            }
        }
    }
}
