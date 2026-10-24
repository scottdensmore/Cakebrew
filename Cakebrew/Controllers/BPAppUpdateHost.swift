import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

// MARK: - In-App Update Discovery Host (#149)

@MainActor
private final class BPAppUpdatePresentation: ObservableObject {
    @Published var state: BPAppUpdateState
    @Published var automaticCheckEnabled: Bool
    var onToggleAutomaticCheck: ((Bool) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onRetryCheck: (() -> Void)?
    var onCloseWindow: (() -> Void)?

    init(currentVersionString: String, automaticCheckEnabled: Bool) {
        self.state = BPAppUpdateState(currentVersionString: currentVersionString)
        self.automaticCheckEnabled = automaticCheckEnabled
    }
}

@MainActor
@objc(BPAppUpdateHost)
public final class BPAppUpdateHost: NSObject {
    private let presentation: BPAppUpdatePresentation
    @objc public let viewController: NSViewController
    @objc public let window: NSWindow
    private var feedURL: URL?
    private var publicKeyBase64: String?

    @objc public var automaticCheckEnabled: Bool {
        get { presentation.automaticCheckEnabled }
        set { presentation.automaticCheckEnabled = newValue }
    }

    @objc public var onToggleAutomaticCheck: ((Bool) -> Void)? {
        get { presentation.onToggleAutomaticCheck }
        set { presentation.onToggleAutomaticCheck = newValue }
    }

    @objc public var onOpenURL: ((URL) -> Void)? {
        get { presentation.onOpenURL }
        set { presentation.onOpenURL = newValue }
    }

    @objc public var currentVersionString: String {
        presentation.state.currentVersion.raw
    }

    @objc public var isUpdateAvailable: Bool {
        if case .updateAvailable = presentation.state.phase {
            return true
        }
        return false
    }

    @objc public var isChecking: Bool {
        if case .checking = presentation.state.phase {
            return true
        }
        return false
    }

    public override convenience init() {
        let bundleVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        self.init(currentVersion: bundleVersion, automaticCheckEnabled: true)
    }

    @objc(initWithCurrentVersion:automaticCheckEnabled:)
    public init(currentVersion: String, automaticCheckEnabled: Bool) {
        let presentation = BPAppUpdatePresentation(
            currentVersionString: currentVersion,
            automaticCheckEnabled: automaticCheckEnabled)
        self.presentation = presentation
        let host = NSHostingController(rootView: BPAppUpdateView(presentation: presentation))
        host.preferredContentSize = NSSize(width: 480, height: 320)
        self.viewController = host

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        window.title = NSLocalizedString("Dock_Check_For_Updates", comment: "")
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        self.window = window

        super.init()

        presentation.onOpenURL = { url in
            NSWorkspace.shared.open(url)
        }
        presentation.onRetryCheck = { [weak self] in
            self?.performConfiguredCheck()
        }
        presentation.onCloseWindow = { [weak self] in
            self?.window.close()
        }

        if let feedString = Bundle.main.object(forInfoDictionaryKey: "BPAppUpdateFeedURL") as? String,
           let parsedURL = URL(string: feedString),
           parsedURL.scheme?.lowercased() == "https" {
            self.feedURL = parsedURL
        }
        if let keyString = Bundle.main.object(forInfoDictionaryKey: "BPAppUpdatePublicKey") as? String,
           !keyString.isEmpty {
            self.publicKeyBase64 = keyString
        }
    }

    @objc public func showWindow() {
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc(configureFeedURL:publicKeyBase64:)
    public func configure(feedURL: URL?, publicKeyBase64: String?) {
        self.feedURL = feedURL
        self.publicKeyBase64 = publicKeyBase64
    }

    @objc(beginCheckWithCurrentVersion:)
    @discardableResult
    public func beginCheck(currentVersion: String?) -> UInt64 {
        presentation.state.beginCheck(currentVersionString: currentVersion)
    }

    @objc(receiveFeedData:publicKeyBase64:generation:)
    @discardableResult
    public func receiveFeedData(_ data: Data, publicKeyBase64: String?, generation: UInt64) -> Bool {
        presentation.state.receiveFeedData(data, publicKeyBase64: publicKeyBase64, generation: generation)
    }

    @objc(receiveFeedUnavailableForGeneration:)
    @discardableResult
    public func receiveFeedUnavailable(generation: UInt64) -> Bool {
        presentation.state.receiveFeedUnavailable(generation: generation)
    }

    @objc(receiveErrorMessage:generation:)
    @discardableResult
    public func receiveError(_ message: String, generation: UInt64) -> Bool {
        presentation.state.receiveError(message, generation: generation)
    }

    @objc public func performConfiguredCheck() {
        let bundleVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? presentation.state.currentVersion.raw
        let generation = presentation.state.beginCheck(currentVersionString: bundleVersion)
        guard let feedURL, feedURL.scheme?.lowercased() == "https" else {
            _ = presentation.state.receiveFeedUnavailable(generation: generation)
            return
        }
        let expectedKey = self.publicKeyBase64
        let task = URLSession.shared.dataTask(with: feedURL) { [weak self] data, response, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    _ = self.presentation.state.receiveError(error.localizedDescription, generation: generation)
                    return
                }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    _ = self.presentation.state.receiveFeedUnavailable(generation: generation)
                    return
                }
                guard let data, !data.isEmpty else {
                    _ = self.presentation.state.receiveFeedUnavailable(generation: generation)
                    return
                }
                _ = self.presentation.state.receiveFeedData(data, publicKeyBase64: expectedKey, generation: generation)
            }
        }
        task.resume()
    }
}

@MainActor
private struct BPAppUpdateView: View {
    @ObservedObject var presentation: BPAppUpdatePresentation

    private var automaticBinding: Binding<Bool> {
        Binding(
            get: { presentation.automaticCheckEnabled },
            set: { newValue in
                presentation.automaticCheckEnabled = newValue
                presentation.onToggleAutomaticCheck?(newValue)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("Cakebrew", comment: ""))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("app.update.title")
                    Text("\(NSLocalizedString("Detail_VoiceOver_Version", comment: "")): \(presentation.state.currentVersion.raw)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("app.update.currentVersion")
                }
                Spacer()
            }

            Divider()

            statusCard
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack(spacing: 10) {
                Toggle(NSLocalizedString("App_Update_Auto_Check", comment: ""), isOn: automaticBinding)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .accessibilityIdentifier("app.update.autoCheck")

                Spacer()

                Button(NSLocalizedString("Try Again", comment: "")) {
                    presentation.onRetryCheck?()
                }
                .accessibilityIdentifier("app.update.retry")

                primaryActionButton

                Button(NSLocalizedString("Close", comment: "")) {
                    presentation.onCloseWindow?()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("app.update.close")
            }
        }
        .padding(18)
        .frame(width: 480, height: 320)
    }

    @ViewBuilder
    private var statusCard: some View {
        switch presentation.state.phase {
        case .idle, .checking:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(NSLocalizedString("Loading_Status_Default", comment: ""))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityIdentifier("app.update.checking")

        case .upToDate(let latestVersion):
            VStack(alignment: .leading, spacing: 8) {
                Label(NSLocalizedString("Empty_Outdated_Title", comment: ""), systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("app.update.upToDate")
                Text("Cakebrew \(latestVersion)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

        case .updateAvailable(let release, let isVerified):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(release.title, systemImage: "sparkles")
                        .font(.headline)
                        .accessibilityIdentifier("app.update.availableTitle")
                    Spacer()
                    Text("\(presentation.state.currentVersion.raw) → \(release.version.raw)")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
                if isVerified {
                    Label(NSLocalizedString("App_Update_Verified", comment: ""), systemImage: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("app.update.verifiedBadge")
                }
                if !release.releaseNotes.isEmpty {
                    ScrollView {
                        Text(release.releaseNotes)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("app.update.releaseNotes")
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

        case .feedUnavailable:
            VStack(alignment: .leading, spacing: 8) {
                Label(NSLocalizedString("Dock_Check_For_Updates", comment: ""), systemImage: "arrow.up.forward.app")
                    .font(.headline)
                Text(NSLocalizedString("App_Update_Feed_Unconfigured", comment: ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("app.update.feedUnavailable")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(NSLocalizedString("Generic_Error", comment: ""), systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("app.update.error")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if case .updateAvailable(let release, _) = presentation.state.phase {
            Button(NSLocalizedString("App_Update_Download", comment: "")) {
                presentation.onOpenURL?(release.downloadURL)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("app.update.download")
        } else {
            Button(NSLocalizedString("App_Update_Open_Releases", comment: "")) {
                presentation.onOpenURL?(presentation.state.releasesPageURL)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("app.update.openReleases")
        }
    }
}

