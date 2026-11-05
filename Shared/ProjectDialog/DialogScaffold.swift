// DialogScaffold: title, grouped form, Cancel, and the confirming action of
// the project, client, and area dialogs (design.md §7).

import SwiftUI

/// Cancel and the confirm button's actions.
struct FormSheetActions {
    var cancel: () -> Void
    var submit: () -> Void
}

/// On the Mac a sheet: the title as a headline, the grouped form, and Cancel
/// and the confirming action at the bottom trailing edge (⌘↩ confirms). On
/// iOS a navigation page: the title in the bar, Cancel leading, the
/// confirming action trailing; `embedded` when already inside a
/// navigation stack (the picker's sheet).
struct DialogScaffold<Fields: View>: View {
    var title: String
    var confirmTitle: String
    var canSubmit: Bool
    var actions: FormSheetActions
    var confirmIdentifier = "form.confirm"
    var width: CGFloat = 400
    var embedded = false
    @ViewBuilder var fields: Fields

    var body: some View {
        #if os(macOS)
            VStack(spacing: 0) {
                Text(title)
                    .font(.headline)
                    .padding(.top, Design.Spacing.window)
                Form {
                    fields
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    cancelButton
                    confirmButton
                }
                .padding([.horizontal, .bottom], Design.Spacing.window)
            }
            .frame(width: width)
        #else
            if embedded {
                page
            } else {
                NavigationStack { page }
            }
        #endif
    }

    #if os(iOS)
        private var page: some View {
            Form {
                fields
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { cancelButton }
                ToolbarItem(placement: .confirmationAction) { confirmButton }
            }
        }
    #endif

    private var cancelButton: some View {
        Button("Cancel", role: .cancel, action: actions.cancel)
            .keyboardShortcut(.cancelAction)
    }

    private var confirmButton: some View {
        Button(confirmTitle, action: actions.submit)
            .keyboardShortcut(.return, modifiers: .command)
        #if os(macOS)
            .buttonStyle(.borderedProminent)
        #endif
            .disabled(!canSubmit)
            .accessibilityIdentifier(confirmIdentifier)
    }
}
