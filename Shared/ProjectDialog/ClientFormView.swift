// ClientFormView: the client sheet (spec_planner_projects.md §4.2).

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
            TextField("Name:", text: $model.name)
                .accessibilityIdentifier("clientForm.name")
                .onSubmit(submit)
                .onChange(of: model.name) { Task { await model.validate() } }
            if let error = model.nameError {
                Text(error).font(.caption).foregroundStyle(.red)
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

/// Cancel and the confirm button's actions.
struct FormSheetActions {
    var cancel: () -> Void
    var submit: () -> Void
}

/// Title, fields, Cancel and the confirm button.
struct FormSheet<Fields: View>: View {
    var title: String
    var confirmTitle: String
    var canSubmit: Bool
    var actions: FormSheetActions
    @ViewBuilder var fields: Fields

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Form {
                fields
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: actions.cancel).keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: actions.submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("form.confirm")
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
