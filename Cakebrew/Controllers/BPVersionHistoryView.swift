import AppKit
import SwiftUI

@MainActor
struct BPVersionHistoryView: View {
    let identity: BPFormulaInformationIdentity
    let sourceURL: URL?
    @State private var expanded = false
    @State private var releases: [BPVersionRelease] = []
    @State private var selected: BPVersionRelease?
    @State private var information: BPHistoricalFormulaDetails?
    @State private var loading = false
    @State private var error: String?
    @State private var informationError: String?
    @State private var detailsRetry = 0
    @State private var nextPath = 0
    @State private var nextPage = 1
    @State private var hasMore = true
    @State private var installation: BPVersionInstallReview?
    @State private var managedRelease: BPVersionRelease?
    @State private var selectedInstalled = false
    @State private var operationGeneration = 0

    private var isMock: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-BPMockBrew")
        #else
        false
        #endif
    }

    private var source: BPVersionHistorySource? {
        if let managedRelease { return managedRelease.source }
        if isMock {
            return BPVersionHistorySource(url: URL(string: "https://github.com/Homebrew/homebrew-\(identity.cask ? "cask" : "core")/blob/HEAD/\(identity.cask ? "Casks" : "Formula")/m/\(identity.name).rb")!)
        }
        return sourceURL.flatMap(BPVersionHistorySource.init(url:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let managedRelease {
                returnButton(managedRelease)
            }
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if source == nil {
                        Text("Version history requires a package source in a GitHub Homebrew tap.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Releases from this package’s Homebrew history.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(releases) { release in
                            DisclosureGroup(isExpanded: Binding(
                                get: { selected?.id == release.id },
                                set: { selected = $0 ? release : nil }
                            )) {
                                versionDetails(release)
                                    .padding(.top, 8)
                                    .padding(.bottom, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            } label: {
                                HStack {
                                    Text(release.version).font(.body.monospacedDigit().weight(.medium))
                                    Spacer()
                                    Text(release.displayDate).font(.caption).foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(Text("Version \(release.version), \(release.displayDate)"))
                                .onTapGesture { selected = selected?.id == release.id ? nil : release }
                            }
                        }
                        if loading { ProgressView("Loading versions…").controlSize(.small) }
                        if let error {
                            Text(error).font(.callout).foregroundStyle(.secondary)
                            Button("Try Again") { Task { await loadOlder() } }
                        } else if !loading, hasMore {
                            Button(LocalizedStringKey(releases.isEmpty ? "Load Versions" : "Load Older Versions")) { Task { await loadOlder() } }
                                .accessibilityIdentifier("versionHistory.loadOlder")
                        } else if !loading, releases.isEmpty {
                            Text("No release entries were found in the available formula history.").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Version History")
                    .contentShape(Rectangle())
                    .onTapGesture { expanded.toggle() }
            }
            .task(id: "\(expanded)-\(source?.url(commit: "HEAD").absoluteString ?? "")") {
                if expanded, releases.isEmpty, source != nil { await loadOlder() }
            }
            .task(id: "\(selected?.id ?? "")-\(detailsRetry)") {
                information = nil
                informationError = nil
                guard let selected else { return }
                do {
                    let details: BPHistoricalFormulaDetails
                    if isMock {
                        details = BPHistoricalFormulaDetails(source: """
                        \(identity.cask ? "cask \"\(identity.name)\" do" : "class Mockwget < Formula")
                          desc "A historical mock release"
                          homepage "https://example.com/mockwget"
                          version "\(selected.version)"
                          sha256 "\(String(repeating: "a", count: 64))"
                          license "MIT"
                          depends_on "mockgit"
                        end
                        """)
                    } else {
                        details = try await BPVersionHistoryClient.shared.information(for: selected)
                    }
                    try Task.checkCancellation()
                    information = details
                } catch {
                    if !Task.isCancelled { informationError = error.localizedDescription }
                }
            }
        }
        .task(id: "\(identity)-\(operationGeneration)") {
            if !isMock {
                let name = identity.name
                let cask = identity.cask
                let interface = BPHomebrewInterface.sharedInterface()
                let candidate = await Task.detached { () -> BPVersionRelease? in
                    guard let release = BPVersionReceipt.find(name: name, cask: cask),
                          BPVersionLatestInstaller.isInstalled(release, read: { interface.readVersionHistoryCommand($0) }) else { return nil }
                    return release
                }.value
                if !Task.isCancelled { managedRelease = candidate }
            }
        }
        .task(id: "\(selected?.id ?? "")-\(operationGeneration)") {
            selectedInstalled = false
            guard let selected else { return }
            let interface = BPHomebrewInterface.sharedInterface()
            let progress = Progress(totalUnitCount: 1)
            let installed = await withTaskCancellationHandler {
                await Task.detached {
                    BPVersionLatestInstaller.isInstalled(selected, read: { interface.readVersionHistoryCommand($0, progress: progress) })
                }.value
            } onCancel: { progress.cancel() }
            if !Task.isCancelled { selectedInstalled = installed }
        }
        .sheet(item: $installation, onDismiss: { operationGeneration &+= 1 }) { review in BPVersionInstallSheet(review: review) }
    }

    private func returnButton(_ release: BPVersionRelease) -> some View {
        Button("Return to Latest Release…", systemImage: "arrow.up.circle") {
            installation = BPVersionInstallReview(release: release, sourceText: "", mock: isMock, returnToLatest: true)
        }
        .accessibilityIdentifier("versionHistory.returnLatest")
    }

    @ViewBuilder private func versionDetails(_ release: BPVersionRelease) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Version \(release.version)").font(.headline).accessibilityIdentifier("versionHistory.details")
            Text(release.message).font(.callout).textSelection(.enabled)
            LabeledContent(LocalizedStringKey(identity.cask ? "Cask date" : "Formula date"), value: release.displayDate)
            LabeledContent("Revision", value: String(release.commit.prefix(12)))
                .font(.caption.monospaced())
            if let information {
                if let description = information.description { Text(description).textSelection(.enabled) }
                if let license = information.license { LabeledContent("License", value: license) }
                if let homepage = information.homepage, let url = URL(string: homepage), ["https", "http"].contains(url.scheme) {
                    Link("Project Website", destination: url)
                }
                if !information.dependencies.isEmpty {
                    Text("Declared Dependencies").font(.subheadline.weight(.medium))
                    Text(information.dependencies.joined(separator: "\n"))
                        .font(.caption.monospaced()).textSelection(.enabled)
                }
                DisclosureGroup(LocalizedStringKey(identity.cask ? "Cask Source" : "Formula Source")) {
                    Text(information.source).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("versionHistory.source")
                }
            } else if let informationError {
                Text(informationError).foregroundStyle(.secondary)
                Button("Retry Details") { detailsRetry &+= 1 }
            } else { ProgressView("Loading version information…").controlSize(.small) }
            Link(LocalizedStringKey(identity.cask ? "View Cask at This Revision" : "View Formula at This Revision"), destination: release.source.url(commit: release.commit))
            Group {
                Button("Install & Pin This Version…", systemImage: "pin") {
                    installation = BPVersionInstallReview(release: release, sourceText: information?.source ?? "", mock: isMock)
                }
                .disabled(!release.canInstall || information == nil ||
                          (identity.cask && information?.explicitVersion != release.version) ||
                          (information?.explicitVersion != nil && information?.explicitVersion != release.version))
                .accessibilityIdentifier("versionHistory.install")
                if selectedInstalled { returnButton(release) }
                if !release.canInstall || (identity.cask && information != nil && information?.explicitVersion != release.version) {
                    Text("Automatic installation requires a fixed, matching release version. You can still inspect this revision’s source.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
    }

    private func loadOlder() async {
        guard !loading, hasMore, let source else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let page: BPVersionHistoryPage
            if isMock {
                page = BPVersionHistoryPage(releases: ["0.9.0", "0.8.1"].enumerated().map { index, version in
                    BPVersionRelease(version: version, commit: String(repeating: index == 0 ? "a" : "b", count: 40),
                                     date: "2025-10-10T12:00:00Z", message: "\(identity.name) \(version)", source: source)
                }, nextPath: 1, nextPage: 1, hasMore: false)
            } else {
                page = try await BPVersionHistoryClient.shared.history(source: source, pathIndex: nextPath, page: nextPage)
            }
            try Task.checkCancellation()
            var versions = Set(releases.map(\.version))
            releases.append(contentsOf: page.releases.filter { versions.insert($0.version).inserted })
            nextPath = page.nextPath
            nextPage = page.nextPage
            hasMore = page.hasMore
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

@MainActor
final class BPVersionInstallReview: ObservableObject, Identifiable {
    let id = UUID()
    let release: BPVersionRelease?
    let sourceText: String
    let mock: Bool
    let returnToLatest: Bool
    private let pinnedPlan: BPVersionReturnPlan?
    @Published var originalPackage = ""
    var returnPlan: BPVersionReturnPlan? {
        if var plan = pinnedPlan { plan.upstream = originalPackage.trimmingCharacters(in: .whitespacesAndNewlines); return plan }
        return release.map(BPVersionReturnPlan.init(release:))
    }
    var upstreamCandidates: [String] { pinnedPlan?.upstreamCandidates ?? [] }
    var needsUpstream: Bool { pinnedPlan?.requiresUpstream == true }
    var isCask: Bool { pinnedPlan?.cask ?? release?.source.isCask ?? false }
    var packageName: String { (pinnedPlan?.historical.split(separator: "/").last).map(String.init) ?? release?.source.name ?? "" }
    var upstreamName: String { returnPlan?.upstream ?? release?.source.formula ?? "" }
    var targetName: String { pinnedPlan?.historical ?? release?.target ?? "" }
    var version: String { pinnedPlan?.version ?? release?.version ?? "" }
    var destinationTap: String { release?.destinationTap ?? "" }
    var keepsHistoricalKeg: Bool { returnPlan.map { $0.historical != $0.upstream } ?? true }
    @Published var makeActive = false
    @Published var running = false
    @Published var cancelling = false
    @Published var output = ""
    @Published var result: BPVersionInstallResult?
    private let progress = Progress(totalUnitCount: 1)

    init(release: BPVersionRelease, sourceText: String, mock: Bool, returnToLatest: Bool = false) {
        self.release = release
        self.sourceText = sourceText
        self.mock = mock
        self.returnToLatest = returnToLatest
        pinnedPlan = nil
    }

    init(plan: BPVersionReturnPlan, mock: Bool) {
        release = nil
        sourceText = ""
        self.mock = mock
        returnToLatest = true
        pinnedPlan = plan
        originalPackage = plan.upstream
    }

    func start() {
        guard !running, result == nil, !returnToLatest || returnPlan?.isValid == true else { return }
        let delegate = BPAppDelegate.current
        guard delegate?.runningBackgroundTask != true, !BPHomebrewManager.sharedManager().reloadInFlight else {
            result = BPVersionInstallResult(succeeded: false, message: "Wait for the current Homebrew operation to finish, then try again.")
            return
        }
        delegate?.runningBackgroundTask = true
        running = true
        let interface = BPHomebrewInterface.sharedInterface()
        let release = release
        let activate = makeActive
        let progress = progress
        let sourceText = sourceText
        let mock = mock
        let returnToLatest = returnToLatest
        let plan = returnPlan
        Task.detached(priority: .userInitiated) {
            let read: BPVersionInstaller.Read = { interface.readVersionHistoryCommand($0, progress: progress) }
            let run: BPVersionInstaller.Run = { arguments in
                Task { @MainActor in self.append("\n$ brew \(arguments.joined(separator: " "))\n") }
                return interface.runVersionHistoryCommand(arguments, progress: progress) { chunk in
                    Task { @MainActor in self.append(chunk) }
                }
            }
            let restore: BPVersionInstaller.Run = { arguments in
                Task { @MainActor in self.append("\nRestoring previous state…\n$ brew \(arguments.joined(separator: " "))\n") }
                return interface.runVersionHistoryCommand(arguments, progress: Progress(totalUnitCount: 1)) { chunk in
                    Task { @MainActor in self.append(chunk) }
                }
            }
            let restoreRead: BPVersionInstaller.Read = { arguments in
                interface.readVersionHistoryCommand(arguments, progress: Progress(totalUnitCount: 1))
            }
            let result: BPVersionInstallResult
            if returnToLatest, let plan {
                result = BPVersionLatestInstaller.install(plan, progress: progress,
                    read: read, run: run, recover: restore, recoverRead: restoreRead)
            } else if let release, release.source.isCask {
                result = BPVersionCaskInstaller.install(release, sourceText: sourceText, progress: progress,
                    read: read, run: run, restore: restore, restoreRead: restoreRead,
                    write: { repository, release, text in
                        if !mock { try BPVersionCaskInstaller.saveDefinition(repository: repository, release: release, text: text) }
                    })
            } else if let release {
                result = BPVersionInstaller.install(release, makeActive: activate, progress: progress,
                    read: read, run: run, restore: restore, restoreRead: restoreRead)
            }
            else { result = BPVersionInstallResult(succeeded: false, message: "The selected package could not be resolved.") }
            if !returnToLatest, !mock, result.succeeded, let release {
                do { try BPVersionReceipt.save(release) }
                catch { await MainActor.run { self.append("\nCouldn’t save the upstream receipt: \(error.localizedDescription)\nOpen the original package’s Version History to return to the latest release.\n") } }
            }
            await MainActor.run {
                self.result = result
                self.running = false
                delegate?.runningBackgroundTask = false
                interface.sendDelegateFormulaeUpdatedCall(forCommand: "tap")
            }
        }
    }

    private func append(_ text: String) {
        output.append(text)
        if output.count > 1_000_000 { output = String(output.suffix(1_000_000)) }
    }

    func cancel() {
        guard !cancelling else { return }
        cancelling = true
        progress.cancel()
        BPHomebrewInterface.sharedInterface().cancelCurrentOperation()
    }
}

@MainActor
struct BPVersionInstallSheet: View {
    @ObservedObject var review: BPVersionInstallReview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                if review.returnToLatest { Text("Return to Latest Release") }
                else { Text("Install & Pin Version \(review.version)") }
            } icon: {
                Image(systemName: review.returnToLatest ? "arrow.up.circle" : "clock.arrow.circlepath")
            }
                .font(.title2.weight(.semibold))
            Text(review.packageName).font(.headline)
            if review.result == nil, !review.running {
                if review.returnToLatest {
                    Text("This refreshes Homebrew, installs the current release from the original tap, and removes the version pins so normal upgrades can resume.")
                    if review.isCask {
                        Text("Quit the app before continuing. The latest release replaces the older app. If replacement fails, the app may need to be reinstalled.")
                    } else if review.keepsHistoricalKeg {
                        Text("The latest release becomes active. The older keg stays installed. If switching command links fails, Cakebrew attempts to restore the previous links and pin policy.")
                    }
                    if !review.isCask, !review.keepsHistoricalKeg {
                        Text("This upgrades the pinned formula in place and makes the latest release active. Homebrew may clean up the previous keg.")
                    }
                    if review.needsUpstream {
                        if review.upstreamCandidates.isEmpty {
                            Text("This older copy has no saved upstream record. Enter its original tap and package name to continue.")
                                .font(.callout).foregroundStyle(.secondary)
                            TextField("Original Package", text: $review.originalPackage, prompt: Text("owner/tap/package"))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("pinnedReturn.upstream")
                                .onSubmit { if review.returnPlan?.isValid == true { review.start() } }
                        } else {
                            Text("Choose the original package to return to. Cakebrew found these possible matches.")
                                .font(.callout).foregroundStyle(.secondary)
                            Picker("Original Package", selection: $review.originalPackage) {
                                Text("Choose a Package…").tag("")
                                ForEach(review.upstreamCandidates, id: \.self) { candidate in
                                    Text(verbatim: candidate).tag(candidate)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("pinnedReturn.candidates")
                        }
                    } else {
                        LabeledContent("Original Package", value: review.upstreamName)
                            .font(.callout.monospaced()).textSelection(.enabled)
                    }
                } else if review.isCask {
                    Text("This replaces the installed app with the selected historical cask and pins it against Homebrew upgrades. Homebrew verifies the download checksum first. App preferences are kept; older apps may be unable to open data created by newer versions. Quit the app before continuing.")
                    Text("The app’s own updater can bypass a Homebrew pin. Disable automatic updates in the app if needed. If replacement fails, the app may need to be reinstalled. Pinned releases do not receive automatic security updates.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("This installs the historical formula in the local \(review.destinationTap) tap and pins it against Homebrew upgrades. Homebrew may download formula history and build from source. Older releases may no longer build on this Mac. Pinned versions do not receive automatic security updates.")
                    Toggle("Make this the active version", isOn: $review.makeActive)
                        .accessibilityIdentifier("versionHistory.makeActive")
                    Text("Your current version stays installed. Activating this release changes its command links; existing unrelated files won’t be overwritten. Other installed versions may still receive upgrades.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text("Package: \(review.targetName)").font(.caption.monospaced()).textSelection(.enabled)
            }
            if review.running {
                ProgressView(LocalizedStringKey(review.returnToLatest ? "Returning to latest release…" : "Installing historical version…"))
                    .controlSize(.small)
            }
            if let result = review.result {
                Label(result.message, systemImage: result.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(result.message))
                    .accessibilityIdentifier("versionHistory.result")
                    .textSelection(.enabled)
                if result.succeeded, !review.returnToLatest {
                    Text("This historical recipe stays in your local tap. Use Return to Latest Release in Version History to switch back and resume normal upgrades.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if !review.output.isEmpty {
                ScrollView {
                    Text(review.output).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("versionHistory.operationOutput")
                }
                .frame(minHeight: 160, maxHeight: 260)
            }
            HStack {
                Spacer()
                if review.running {
                    Button("Cancel Operation") { review.cancel() }
                        .disabled(review.cancelling)
                        .accessibilityIdentifier("versionHistory.cancelOperation")
                } else {
                    Button(LocalizedStringKey(review.result == nil ? "Cancel" : "Done")) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("versionHistory.close")
                    if review.result == nil {
                        Button(LocalizedStringKey(review.returnToLatest ? "Unpin & Switch to Latest" : "Install & Pin")) { review.start() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(review.returnToLatest && review.returnPlan?.isValid != true)
                            .accessibilityIdentifier("versionHistory.confirm")
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled(review.running)
    }
}

@MainActor
struct BPPinnedReturnSheet: View {
    let row: BPInstalledPackageRow
    @State private var review: BPVersionInstallReview?
    @State private var error: String?
    @State private var retry = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let review { BPVersionInstallSheet(review: review) }
            else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Return to Latest Release").font(.title2.weight(.semibold))
                    Text(row.name).font(.headline)
                    if let error {
                        Text(error).textSelection(.enabled)
                        Button("Try Again") { retry &+= 1 }
                    } else { ProgressView("Checking pinned package…").controlSize(.small) }
                    HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
                }
                .padding(24).frame(width: 580)
            }
        }
        .task(id: retry) {
            error = nil
            let interface = BPHomebrewInterface.sharedInterface()
            let name = row.name
            let cask = row.cask
            let progress = Progress(totalUnitCount: 1)
            do {
                let plan = try await withTaskCancellationHandler {
                    try await Task.detached {
                        try BPPinnedVersionResolver.resolve(name: name, cask: cask,
                            read: { interface.readVersionHistoryCommand($0, progress: progress) },
                            receipt: { interface.versionHistoryReceipt(name: $0, cask: $1) })
                    }.value
                } onCancel: { progress.cancel() }
                try Task.checkCancellation()
                #if DEBUG
                let mock = ProcessInfo.processInfo.arguments.contains("-BPMockBrew")
                #else
                let mock = false
                #endif
                review = BPVersionInstallReview(plan: plan, mock: mock)
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
