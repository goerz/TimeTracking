// ClientFormView: the client sheet (projects.md §4.2).

import SwiftUI
import TimeTrackingCore

/// New Client and Rename Client.
struct ClientFormView: View {
    @Bindable var model: ClientFormModel
    var onDone: (Client?, Area?) -> Void

    var body: some View {
        FormSheet(
            title: model.title,
            confirmTitle: model.confirmTitle,
            canSubmit: model.canSubmit,
            actions: FormSheetActions(cancel: { onDone(nil, nil) }, submit: submit)
        ) {
            TextField("Name", text: $model.name)
                .accessibilityIdentifier("clientForm.name")
                .onSubmit(submit)
                .onChange(of: model.name) { Task { await model.validate() } }
            if let error = model.nameError {
                Text(error).font(.caption).foregroundStyle(Color.errorText)
            }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(Color.errorText).accessibilityIdentifier("clientForm.error")
            }
            if model.showsColor {
                AreaColorWell(hex: $model.color).accessibilityIdentifier("clientForm.color")
            }
        }
    }

    private func submit() {
        Task {
            if let (client, area) = await model.submit() {
                onDone(client, area)
            }
        }
    }
}

/// A small dialog: title, fields, Cancel and the confirm button.
struct FormSheet<Fields: View>: View {
    var title: String
    var confirmTitle: String
    var canSubmit: Bool
    var actions: FormSheetActions
    @ViewBuilder var fields: Fields

    var body: some View {
        DialogScaffold(title: title, confirmTitle: confirmTitle, canSubmit: canSubmit, actions: actions, width: 360) {
            fields
        }
    }
}
