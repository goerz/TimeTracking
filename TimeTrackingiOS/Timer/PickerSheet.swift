// PickerSheet: the project picker as a sheet, medium detent resizable to
// large, with the project dialog pushed inside it (spec_ios.md §2.4).

import SwiftUI
import TimeTrackingCore

struct PickerSheet: View {
    @Bindable var model: PhoneModel
    var picker: ProjectPickerModel

    var body: some View {
        NavigationStack {
            ProjectPickerView(model: picker) { choice in
                Task { await model.choose(choice) }
            } onCancel: {
                model.sheet = nil
            }
            .navigationTitle("Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.sheet = nil }
                }
            }
            .navigationDestination(isPresented: dialogShown) {
                if let dialog = model.dialogModel {
                    ProjectDialogView(model: dialog, preferredArea: nil) { project in
                        Task { await model.dialogFinished(project) }
                    }
                    .navigationBarBackButtonHidden()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var dialogShown: Binding<Bool> {
        Binding(get: { model.dialogModel != nil }, set: { model.dialogModel = $0 ? model.dialogModel : nil })
    }
}
