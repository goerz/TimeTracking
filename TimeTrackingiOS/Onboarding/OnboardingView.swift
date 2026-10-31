// OnboardingView: the blocking account screen, the device name, and the
// initial sync's progress (spec_ios.md §11).

import SwiftUI
import TimeTrackingCore

struct OnboardingView: View {
    @Bindable var onboarding: OnboardingModel
    var model: PhoneModel

    @Environment(\.openURL) private var openURL

    var body: some View {
        switch onboarding.step {
        case .checking, .done:
            ProgressView()
        case .noAccount:
            noAccount
        case .deviceName:
            deviceName
        case let .syncing(entries):
            syncing(entries)
        }
    }

    static let explanation = "Your time stays in sync between your Mac and this device through iCloud. "
        + "Sign in with the Mac's Apple Account and turn on iCloud Drive."

    private var noAccount: some View {
        ContentUnavailableView {
            Label("iCloud Needed", systemImage: SymbolName.iCloudOff)
        } description: {
            Text(Self.explanation)
        } actions: {
            Button("Open Settings") {
                if let url = DeviceInfo.settingsURL {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Try Again") {
                Task { await onboarding.check() }
            }
            .accessibilityIdentifier("onboarding.tryAgain")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.noAccount")
    }

    private var deviceName: some View {
        NavigationStack {
            Form {
                Section {
                    deviceNameHeader
                        .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Device name", text: $onboarding.deviceName)
                        .submitLabel(.continue)
                        .onSubmit(confirm)
                        .accessibilityIdentifier("onboarding.deviceName")
                }
            }
            .frame(maxWidth: 560)
            .safeAreaInset(edge: .bottom) {
                Button(action: confirm) {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(onboarding.deviceName.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(Design.Spacing.large)
                .frame(maxWidth: 560)
                .accessibilityIdentifier("onboarding.continue")
            }
        }
    }

    /// The device symbol, the title, and what the name is for.
    private var deviceNameHeader: some View {
        VStack(spacing: Design.Spacing.small) {
            Image(systemName: DeviceInfo.isPad ? SymbolName.iPad : SymbolName.iPhone)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Name This Device")
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
            Text("Entries show where they were created.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, Design.Spacing.large)
    }

    private func confirm() {
        Task { await onboarding.confirmName(model: model) }
    }

    private func syncing(_ entries: Int) -> some View {
        ContentUnavailableView {
            Label("Receiving Your Data", systemImage: SymbolName.iCloudDownload)
        } description: {
            Text("Loading your entries from iCloud.")
        } actions: {
            VStack(spacing: Design.Spacing.small) {
                ProgressView()
                Text("\(entries) entries").foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}
