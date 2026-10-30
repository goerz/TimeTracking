// LadderSetEditor: one app set's label and FamilyActivityPicker selection
// (spec_ios.md §9.2). "Everything" keeps its label and selects nothing.

import FamilyControls
import SwiftUI
import TimeTrackingCore

struct LadderSetEditor: View {
    var collection: CollectionModel
    @State private var set: LadderSet
    @State private var selection: FamilyActivitySelection
    @State private var choosing = false

    init(collection: CollectionModel, set: LadderSet) {
        self.collection = collection
        _set = State(initialValue: set)
        _selection = State(initialValue: set.selection.flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
            ?? FamilyActivitySelection())
    }

    private var isEmpty: Bool {
        selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty
    }

    var body: some View {
        Form {
            if set.isEverything {
                Section {
                    LabeledContent("Label", value: set.label)
                } footer: {
                    Text("Measures all use of this device. It cannot be changed or deleted.")
                }
            } else {
                Section {
                    LabeledContent("Label") {
                        TextField("Label", text: $set.label)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onSubmit { collection.updateSet(set) }
                    }
                } footer: {
                    Text("Only this label reaches the activity log.")
                }
                Section("Apps, Categories, and Sites") {
                    ForEach(Array(selection.applicationTokens), id: \.self) { Label($0) }
                    ForEach(Array(selection.categoryTokens), id: \.self) { Label($0) }
                    ForEach(Array(selection.webDomainTokens), id: \.self) { Label($0) }
                    Button(isEmpty ? "Choose Apps…" : "Change Apps…") { choosing = true }
                }
            }
        }
        .navigationTitle(set.label)
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(isPresented: $choosing, selection: $selection)
        .onChange(of: selection) {
            set.selection = try? JSONEncoder().encode(selection)
            collection.updateSet(set)
        }
        .onDisappear { collection.updateSet(set) }
    }
}
