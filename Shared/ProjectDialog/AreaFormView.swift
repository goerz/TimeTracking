// AreaFormView: the area sheet with the system color well
// (spec_planner_projects.md §4.3, §4.4).

import SwiftUI
import TimeTrackingCore

/// New Area and Edit Area.
struct AreaFormView: View {
    @Bindable var model: AreaFormModel
    var onDone: (Area?) -> Void

    var body: some View {
        FormSheet(
            title: model.title,
            confirmTitle: model.confirmTitle,
            canSubmit: model.canSubmit,
            actions: FormSheetActions(cancel: { onDone(nil) }, submit: submit)
        ) {
            TextField("Name", text: $model.name)
                .disabled(!model.nameEditable)
                .accessibilityIdentifier("areaForm.name")
                .onSubmit(submit)
                .onChange(of: model.name) { Task { await model.validate() } }
            if let note = model.nameNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.nameError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("areaForm.error")
            }
            AreaColorWell(hex: $model.color).accessibilityIdentifier("areaForm.color")
        }
    }

    private func submit() {
        Task {
            if let area = await model.submit() {
                onDone(area)
            }
        }
    }
}

/// The Color field: a `ColorPicker` without opacity, stored as `#RRGGBB`.
struct AreaColorWell: View {
    @Binding var hex: String

    var body: some View {
        ColorPicker("Color", selection: color, supportsOpacity: false)
    }

    private var color: Binding<Color> {
        Binding {
            Color(hex: hex)
        } set: { color in
            if let value = color.hexString {
                hex = value
            }
        }
    }
}
