// ProjectDialogView: the shared new- and edit-project dialog
// (spec_planner_projects.md §3).

import SwiftUI
import TimeTrackingCore

/// The dialog as a sheet. Create or Save calls `onDone` with the project.
struct ProjectDialogView: View {
    @Bindable var model: ProjectDialogModel
    var preferredArea: AreaID?
    var onDone: (Project?) -> Void

    @FocusState private var nameFocused: Bool
    @State private var newClient: String?
    @State private var newArea: String?
    @State private var newAreaColor = Color.accentColor

    private static let newClientTag = "new-client"
    private static let newAreaTag = "new-area"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.title).font(.headline)
            Form {
                TextField("Name:", text: $model.name)
                    .focused($nameFocused)
                    .accessibilityIdentifier("projectDialog.name")
                    .onSubmit { submit() }
                    .onChange(of: model.name) {
                        Task { await model.validate() }
                    }
                if let error = model.nameError {
                    Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("projectDialog.nameError")
                }
                clientPicker
                areaPicker
                if case .edit = model.mode {
                    Toggle("Archived", isOn: $model.isArchived)
                }
            }
            buttons
        }
        .padding(20)
        .frame(width: 400)
        .task {
            await model.load(preferredArea: preferredArea)
            nameFocused = true
        }
        .sheet(item: Binding(get: { newClient.map(NameRequest.init) }, set: { newClient = $0?.name })) { _ in
            NameSheet(title: "New Client", name: Binding(get: { newClient ?? "" }, set: { newClient = $0 })) { name in
                newClient = nil
                if let name {
                    Task { await model.createClient(name: name) }
                }
            }
        }
        .sheet(item: Binding(get: { newArea.map(NameRequest.init) }, set: { newArea = $0?.name })) { _ in
            NameSheet(title: "New Area", name: Binding(get: { newArea ?? "" }, set: { newArea = $0 }), color: $newAreaColor) { name in
                newArea = nil
                if let name {
                    Task { await model.createArea(name: name, color: newAreaColor.hexString) }
                }
            }
        }
    }

    private var clientPicker: some View {
        Picker("Client:", selection: clientSelection) {
            ForEach(model.clients) { client in
                Text(client.name).tag(client.id.rawValue)
            }
            Divider()
            Text("New Client…").tag(Self.newClientTag)
        }
        .accessibilityIdentifier("projectDialog.client")
    }

    private var areaPicker: some View {
        Picker("Area:", selection: areaSelection) {
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

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { onDone(nil) }
                .keyboardShortcut(.cancelAction)
            Button(model.confirmTitle) { submit() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSubmit)
                .accessibilityIdentifier("projectDialog.confirm")
        }
    }

    private var clientSelection: Binding<String> {
        Binding {
            model.clientID?.rawValue ?? ""
        } set: { tag in
            if tag == Self.newClientTag {
                newClient = ""
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
                newArea = ""
            } else {
                model.areaID = AreaID(tag)
            }
        }
    }

    private func submit() {
        guard model.canSubmit else {
            return
        }
        Task {
            if let project = await model.submit() {
                onDone(project)
            }
        }
    }
}

/// A request for a name sheet.
private struct NameRequest: Identifiable {
    var name: String

    var id: String {
        "request"
    }
}

/// The client and area sheets: a name and, for areas, a color.
private struct NameSheet: View {
    var title: String
    @Binding var name: String
    var color: Binding<Color>?
    var onDone: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Name", text: $name).onSubmit { onDone(name.trimmed.isEmpty ? nil : name) }
            if let color {
                ColorPicker("Color", selection: color, supportsOpacity: false)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDone(nil) }.keyboardShortcut(.cancelAction)
                Button("Create") { onDone(name) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

extension Color {
    /// The color as uppercase `#RRGGBB` in sRGB, clamped and rounded to 8 bits.
    var hexString: String? {
        let resolved = resolve(in: EnvironmentValues())
        func byte(_ value: Float) -> Int {
            Int((min(max(Double(value), 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", byte(resolved.red), byte(resolved.green), byte(resolved.blue))
    }
}
