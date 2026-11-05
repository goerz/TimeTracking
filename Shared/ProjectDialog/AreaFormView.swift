// AreaFormView: the area sheet with the system color well
// (projects.md §4.3, §4.4).

import SwiftUI
import TimeTrackingCore

/// New Area and Edit Area: Name, Client, Color.
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
                Text(error).font(.caption).foregroundStyle(Color.errorText)
            }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(Color.errorText).accessibilityIdentifier("areaForm.error")
            }
            Picker("Client", selection: $model.clientID) {
                if model.clientID == nil {
                    Text("Choose a Client").tag(ClientID?.none)
                }
                ForEach(model.clients) { client in
                    Text(client.name).tag(Optional(client.id))
                }
            }
            .disabled(model.clientFixed)
            .onChange(of: model.clientID) { Task { await model.validate() } }
            .accessibilityIdentifier("areaForm.client")
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
