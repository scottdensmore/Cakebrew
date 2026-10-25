import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

// MARK: - SwiftUI Tahoe Settings Host

@MainActor
private final class BPPreferencesPresentation: ObservableObject {
    @Published var backgroundCheckEnabled: Bool = true
    @Published var backgroundCheckInterval: Double = 21600.0
    @Published var greedyCaskUpgrades: Bool = false
    @Published var automaticAppUpdateCheckEnabled: Bool = true
    @Published var showMenuBarExtra: Bool = false
    @Published var helperStatusText: String = ""
    @Published var helperActionTitle: String?

    var onBackgroundCheckChanged: ((Bool) -> Void)?
    var onIntervalChanged: ((Double) -> Void)?
    var onGreedyChanged: ((Bool) -> Void)?
    var onAutomaticAppUpdateCheckChanged: ((Bool) -> Void)?
    var onShowMenuBarExtraChanged: ((Bool) -> Void)?
    var onCheckForAppUpdates: (() -> Void)?
    var onHelperAction: (() -> Void)?
}

@MainActor
@objc(BPPreferencesHost)
public final class BPPreferencesHost: NSObject {
    public var content: some View { BPPreferencesView(presentation: presentation) }
    private let presentation = BPPreferencesPresentation()
    @objc public let viewController: NSViewController

    @objc public var showMenuBarExtra: Bool {
        get { presentation.showMenuBarExtra }
        set { presentation.showMenuBarExtra = newValue }
    }

    @objc public var onBackgroundCheckChanged: ((Bool) -> Void)? {
        get { presentation.onBackgroundCheckChanged }
        set { presentation.onBackgroundCheckChanged = newValue }
    }

    @objc public var onIntervalChanged: ((Double) -> Void)? {
        get { presentation.onIntervalChanged }
        set { presentation.onIntervalChanged = newValue }
    }

    @objc public var onGreedyChanged: ((Bool) -> Void)? {
        get { presentation.onGreedyChanged }
        set { presentation.onGreedyChanged = newValue }
    }

    @objc public var onAutomaticAppUpdateCheckChanged: ((Bool) -> Void)? {
        get { presentation.onAutomaticAppUpdateCheckChanged }
        set { presentation.onAutomaticAppUpdateCheckChanged = newValue }
    }

    @objc public var onShowMenuBarExtraChanged: ((Bool) -> Void)? {
        get { presentation.onShowMenuBarExtraChanged }
        set { presentation.onShowMenuBarExtraChanged = newValue }
    }

    @objc public var onCheckForAppUpdates: (() -> Void)? {
        get { presentation.onCheckForAppUpdates }
        set { presentation.onCheckForAppUpdates = newValue }
    }

    @objc public var onHelperAction: (() -> Void)? {
        get { presentation.onHelperAction }
        set { presentation.onHelperAction = newValue }
    }

    public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPPreferencesView(presentation: presentation))
        host.sizingOptions = []
        viewController = host
        super.init()
    }

    @objc(syncWithBackgroundCheckEnabled:interval:greedy:automaticAppUpdates:helperStatus:helperActionTitle:)
    public func sync(backgroundCheckEnabled: Bool,
                     interval: Double,
                     greedy: Bool,
                     automaticAppUpdates: Bool,
                     helperStatus: String,
                     helperActionTitle: String?) {
        presentation.backgroundCheckEnabled = backgroundCheckEnabled
        if interval == 3600.0 || interval == 21600.0 || interval == 86400.0 {
            presentation.backgroundCheckInterval = interval
        } else {
            presentation.backgroundCheckInterval = 21600.0
        }
        presentation.greedyCaskUpgrades = greedy
        presentation.automaticAppUpdateCheckEnabled = automaticAppUpdates
        presentation.helperStatusText = helperStatus
        presentation.helperActionTitle = (helperActionTitle?.isEmpty == false) ? helperActionTitle : nil
    }
}

@MainActor
private struct BPPreferencesView: View {
    @ObservedObject var presentation: BPPreferencesPresentation

    private var backgroundCheckBinding: Binding<Bool> {
        Binding(
            get: { presentation.backgroundCheckEnabled },
            set: { newValue in
                presentation.backgroundCheckEnabled = newValue
                presentation.onBackgroundCheckChanged?(newValue)
            }
        )
    }

    private var intervalBinding: Binding<Double> {
        Binding(
            get: { presentation.backgroundCheckInterval },
            set: { newValue in
                presentation.backgroundCheckInterval = newValue
                presentation.onIntervalChanged?(newValue)
            }
        )
    }

    private var greedyBinding: Binding<Bool> {
        Binding(
            get: { presentation.greedyCaskUpgrades },
            set: { newValue in
                presentation.greedyCaskUpgrades = newValue
                presentation.onGreedyChanged?(newValue)
            }
        )
    }

    private var autoAppUpdateBinding: Binding<Bool> {
        Binding(
            get: { presentation.automaticAppUpdateCheckEnabled },
            set: { newValue in
                presentation.automaticAppUpdateCheckEnabled = newValue
                presentation.onAutomaticAppUpdateCheckChanged?(newValue)
            }
        )
    }

    private var menuBarExtraBinding: Binding<Bool> {
        Binding(
            get: { presentation.showMenuBarExtra },
            set: { newValue in
                presentation.showMenuBarExtra = newValue
                presentation.onShowMenuBarExtraChanged?(newValue)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(NSLocalizedString("Preferences_Background_Check", comment: ""), isOn: backgroundCheckBinding)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("preferences.backgroundCheck")

                HStack(spacing: 8) {
                    Text(NSLocalizedString("Preferences_Check_Interval", comment: ""))
                        .foregroundStyle(presentation.backgroundCheckEnabled ? .primary : .secondary)
                    Picker("", selection: intervalBinding) {
                        Text(NSLocalizedString("Preferences_Interval_Hourly", comment: "")).tag(3600.0)
                        Text(NSLocalizedString("Preferences_Interval_Six_Hours", comment: "")).tag(21600.0)
                        Text(NSLocalizedString("Preferences_Interval_Daily", comment: "")).tag(86400.0)
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    .disabled(!presentation.backgroundCheckEnabled)
                    .accessibilityIdentifier("preferences.interval")
                }
                .padding(.leading, 18)

                Toggle(NSLocalizedString("Preferences_Menu_Bar_Extra", comment: ""), isOn: menuBarExtraBinding)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("preferences.menuBarExtra")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            VStack(alignment: .leading, spacing: 6) {
                Toggle(NSLocalizedString("Preferences_Greedy_Casks", comment: ""), isOn: greedyBinding)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("preferences.greedyCasks")

                Text(NSLocalizedString("Preferences_Greedy_Casks_Note", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle(NSLocalizedString("App_Update_Auto_Check", comment: ""), isOn: autoAppUpdateBinding)
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("preferences.autoAppUpdates")
                    Spacer()
                    Button(NSLocalizedString("Dock_Check_For_Updates", comment: "")) {
                        presentation.onCheckForAppUpdates?()
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("preferences.checkForAppUpdates")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Preferences_Helper_Section", comment: ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(presentation.helperStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("preferences.helperStatus")
                if let actionTitle = presentation.helperActionTitle {
                    Button(actionTitle) {
                        presentation.onHelperAction?()
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("preferences.helperAction")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

