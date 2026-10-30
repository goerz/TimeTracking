// OnboardingView: the blocking account screen, the device name, and the
// initial sync's progress (spec_ios.md §11).

import SwiftUI
import TimeTrackingCore

struct OnboardingView: View {
    @Bindable var onboarding: OnboardingModel
    var model: PhoneModel

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            switch onboarding.step {
            case .checking, .done:
                ProgressView()
            case .noAccount:
                noAccount
            case .deviceName:
                deviceName
            case let .syncing(entries):
                ProgressView()
                Text("Receiving your data from iCloud…")
                Text("\(entries) entries").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(32)
        .frame(maxWidth: 480)
    }

    static let explanation = "TimeTracking keeps your time on your Mac and this device in sync through iCloud. "
        + "Sign in with the Mac's Apple Account and turn on iCloud Drive."

    private var noAccount: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash").font(.system(size: 56)).accessibilityHidden(true)
            Text("iCloud Needed").font(.title.bold())
            Text(Self.explanation)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = DeviceInfo.settingsURL {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
            Button("Try Again") {
                Task { await onboarding.check() }
            }
            .accessibilityIdentifier("onboarding.tryAgain")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.noAccount")
    }

    private var deviceName: some View {
        VStack(spacing: 16) {
            Text("Name This Device").font(.title.bold())
            Text("Entries show where they were created.").foregroundStyle(.secondary)
            TextField("Device name", text: $onboarding.deviceName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("onboarding.deviceName")
            Button("Continue") {
                Task { await onboarding.confirmName(model: model) }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("onboarding.continue")
        }
    }
}
