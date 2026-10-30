// LadderSetEditor: one app set's label and FamilyActivityPicker selection
// (spec_ios.md §9.2). "Everything" keeps its label and selects nothing.

import FamilyControls
import SwiftUI
import TimeTrackingCore

struct LadderSetEditor: View {
    var collection: CollectionModel
    @State private var set: LadderSet
    @State private var selection: FamilyActivitySelection

    init(collection: CollectionModel, set: LadderSet) {
        self.collection = collection
        _set = State(initialValue: set)
        _selection = State(initialValue: set.selection.flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
            ?? FamilyActivitySelection())
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
                    TextField("Label", text: $set.label)
                        .onSubmit { collection.updateSet(set) }
                } footer: {
                    Text("Only this label reaches the activity log.")
                }
                Section("Apps, Categories, and Sites") {
                    ForEach(Array(selection.applicationTokens), id: \.self) { Label($0) }
                    ForEach(Array(selection.categoryTokens), id: \.self) { Label($0) }
                    ForEach(Array(selection.webDomainTokens), id: \.self) { Label($0) }
                }
                FamilyActivityPicker(selection: $selection)
                    .frame(minHeight: 400)
            }
        }
        .navigationTitle(set.label)
        .onChange(of: selection) {
            set.selection = try? JSONEncoder().encode(selection)
            collection.updateSet(set)
        }
        .onDisappear { collection.updateSet(set) }
    }
}
