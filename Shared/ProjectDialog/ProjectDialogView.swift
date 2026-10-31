// ProjectDialogView: the shared new- and edit-project dialog
// (spec_planner_projects.md §3).

import SwiftUI
import TimeTrackingCore

/// The dialog as a sheet. Create or Save calls `onDone` with the project.
struct ProjectDialogView: View {
    @Bindable var model: ProjectDialogModel
    var preferredArea: AreaID?
    /// Inside a navigation stack already (iOS: the picker's sheet).
    var embedded = false
    var onDone: (Project?) -> Void

    @Environment(\.undoManager) private var undoManager
    @FocusState private var nameFocused: Bool
    @State private var clientForm: ClientFormModel?
    @State private var areaForm: AreaFormModel?

    private static let newClientTag = "new-client"
    private static let newAreaTag = "new-area"

    var body: some View {
        DialogScaffold(
            title: model.title,
            confirmTitle: model.confirmTitle,
            canSubmit: model.canSubmit,
            actions: FormSheetActions(cancel: { onDone(nil) }, submit: { submit() }),
            confirmIdentifier: "projectDialog.confirm",
            embedded: embedded
        ) {
            Section {
                TextField("Name", text: $model.name)
                    .focused($nameFocused)
                    .accessibilityIdentifier("projectDialog.name")
                    .onSubmit { submit() }
                    .onChange(of: model.name) {
                        Task { await model.validate() }
                    }
            } footer: {
                if let error = model.nameError {
                    Text(error).foregroundStyle(Color.errorText).accessibilityIdentifier("projectDialog.nameError")
                }
                if let error = model.lastError {
                    Text(error).foregroundStyle(Color.errorText).accessibilityIdentifier("projectDialog.error")
                }
            }
            Section {
                clientPicker
                areaPicker
                if case .edit = model.mode {
                    Toggle("Archived", isOn: $model.isArchived)
                        .accessibilityIdentifier("projectDialog.archived")
                }
            }
        }
        .task {
            model.undoManager = model.undoManager ?? undoManager
            await model.load(preferredArea: preferredArea)
            nameFocused = true
        }
        .sheet(item: $clientForm) { form in
            ClientFormView(model: form) { client, general in
                clientForm = nil
                if let client {
                    Task { await model.clientCreated(client, general: general) }
                }
            }
        }
        .sheet(item: $areaForm) { form in
            AreaFormView(model: form) { area in
                areaForm = nil
                if let area {
                    Task { await model.areaCreated(area) }
                }
            }
        }
        .alert(
            model.confirmation?.title ?? "",
            isPresented: .isPresent($model.confirmation),
            presenting: model.confirmation
        ) { confirmation in
            Button(confirmation.confirmTitle) { submit(confirmed: true) }
                .accessibilityIdentifier("projectDialog.confirmMove")
            Button("Cancel", role: .cancel) { model.confirmation = nil }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private var clientPicker: some View {
        Picker("Client", selection: clientSelection) {
            ForEach(model.clients) { client in
                Text(client.name).tag(client.id.rawValue)
            }
            Divider()
            Text("New Client…").tag(Self.newClientTag)
        }
        .accessibilityIdentifier("projectDialog.client")
    }

    private var areaPicker: some View {
        Picker("Area", selection: areaSelection) {
            ForEach(model.areas) { area in
                Label {
                    Text(area.isRetired ? "\(area.name) (retired)" : area.name)
                } icon: {
                    AreaSwatch(color: area.color)
                }
                .tag(area.id.rawValue)
            }
            Divider()
            Text("New Area…").tag(Self.newAreaTag)
        }
        .accessibilityIdentifier("projectDialog.area")
    }

    private var clientSelection: Binding<String> {
        Binding {
            model.clientID?.rawValue ?? ""
        } set: { tag in
            if tag == Self.newClientTag {
                Task { clientForm = await ClientFormModel.create(store: model.store) }
            } else if let id = ClientID(tag) {
                Task { await model.select(client: id) }
            }
        }
    }

    private var areaSelection: Binding<String> {
        Binding {
            model.areaID?.rawValue ?? ""
        } set: { tag in
            if tag == Self.newAreaTag {
                if let client = model.clientID {
                    Task { areaForm = await AreaFormModel.create(store: model.store, client: client) }
                }
            } else {
                model.areaID = AreaID(tag)
            }
        }
    }

    private func submit(confirmed: Bool = false) {
        guard model.canSubmit else {
            return
        }
        Task {
            if let project = await model.submit(confirmed: confirmed) {
                onDone(project)
            }
        }
    }
}

extension Color {
    /// The color as uppercase `#RRGGBB` in sRGB: converted from its own
    /// space (Display P3 included), clamped, and rounded to 8 bits.
    var hexString: String? {
        let resolved = resolve(in: EnvironmentValues())
        guard let space = CGColorSpace(name: CGColorSpace.extendedSRGB),
              let converted = resolved.cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let parts = converted.components, parts.count >= 3
        else {
            return nil
        }
        return AreaColor(red: Double(parts[0]), green: Double(parts[1]), blue: Double(parts[2])).hex
    }
}
