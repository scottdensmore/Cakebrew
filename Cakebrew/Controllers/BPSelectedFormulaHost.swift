import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

@MainActor
private final class BPSelectedFormulaPresentation: ObservableObject {
    @Published var state = BPSelectedFormulaState()
    @Published var details = BPFormulaInspectorDetails(information: nil)
    @Published var showsHomebrewOutput = false
    var onSelectRelatedPackage: ((String) -> Void)?
    var onOpenWebsite: (() -> Void)?
}

@MainActor
@objc(BPSelectedFormulaHost)
public final class BPSelectedFormulaHost: NSObject {
    public var content: some View { BPSelectedFormulaInspectorView(presentation: presentation) }
    private let presentation = BPSelectedFormulaPresentation()
    @objc public let viewController: NSViewController

    @objc public var onSelectRelatedPackage: ((String) -> Void)? {
        get { presentation.onSelectRelatedPackage }
        set { presentation.onSelectRelatedPackage = newValue }
    }

    @objc public var onOpenWebsite: (() -> Void)? {
        get { presentation.onOpenWebsite }
        set { presentation.onOpenWebsite = newValue }
    }

    public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPSelectedFormulaInspectorView(presentation: presentation))
        host.sizingOptions = []
        viewController = host
        super.init()
    }

    @objc public func clearSelection() {
        presentation.state.clear()
        presentation.details = BPFormulaInspectorDetails(information: nil)
        presentation.showsHomebrewOutput = false
    }

    @objc public func showMultipleSelection() {
        presentation.state.selectMultiple()
        presentation.details = BPFormulaInspectorDetails(information: nil)
        presentation.showsHomebrewOutput = false
    }

    @objc(beginSelectionWithName:cask:installed:pinned:installPath:latestVersion:dependencies:conflicts:shortDescription:)
    public func beginSelection(name: String,
                               cask: Bool,
                               installed: Bool,
                               pinned: Bool,
                               installPath: String?,
                               latestVersion: String?,
                               dependencies: String?,
                               conflicts: String?,
                               shortDescription: String?) -> UInt64 {
        let snapshot = BPSelectedFormulaSnapshot(
            name: name,
            cask: cask,
            isInstalled: installed,
            isPinned: pinned,
            installPath: installPath,
            latestVersion: latestVersion,
            dependencies: dependencies,
            conflicts: conflicts,
            shortDescription: shortDescription)
        if presentation.state.currentSnapshot?.identity != snapshot.identity {
            presentation.details = BPFormulaInspectorDetails(information: nil)
            presentation.showsHomebrewOutput = false
        }
        return presentation.state.beginSingle(snapshot).generation
    }

    @objc(updateSelectionWithName:cask:installed:pinned:installPath:latestVersion:dependencies:conflicts:shortDescription:)
    public func updateSelection(name: String,
                                cask: Bool,
                                installed: Bool,
                                pinned: Bool,
                                installPath: String?,
                                latestVersion: String?,
                                dependencies: String?,
                                conflicts: String?,
                                shortDescription: String?) {
        let snapshot = BPSelectedFormulaSnapshot(
            name: name,
            cask: cask,
            isInstalled: installed,
            isPinned: pinned,
            installPath: installPath,
            latestVersion: latestVersion,
            dependencies: dependencies,
            conflicts: conflicts,
            shortDescription: shortDescription)
        presentation.state.updateSingle(snapshot)
    }

    @objc(receiveDependents:name:cask:generation:)
    public func receiveDependents(_ dependents: [String], name: String, cask: Bool, generation: UInt64) {
        let request = BPFormulaInformationRequest(
            identity: BPFormulaInformationIdentity(name: name, cask: cask, mode: .general),
            generation: generation)
        presentation.state.receiveDependents(dependents, for: request)
    }

    public func receiveInformation(_ information: String?, name: String, cask: Bool) {
        guard let snapshot = presentation.state.currentSnapshot,
              snapshot.identity.name == name, snapshot.identity.cask == cask else { return }
        presentation.details = BPFormulaInspectorDetails(information: information)
    }

    @objc public func copyInstallPathToPasteboard() -> String {
        guard case .single(let snapshot) = presentation.state.selection,
              snapshot.isInstalled,
              let path = snapshot.installPath,
              !path.isEmpty else {
            return ""
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        return path
    }

    @objc public func revealInstallPathInFinder() -> Bool {
        guard case .single(let snapshot) = presentation.state.selection,
              snapshot.isInstalled,
              let rawPath = snapshot.installPath,
              !rawPath.isEmpty else {
            return false
        }
        let firstToken = rawPath.components(separatedBy: " ").first ?? rawPath
        let url = URL(fileURLWithPath: firstToken)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    @objc(selectRelatedPackageNamed:)
    public func selectRelatedPackage(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presentation.onSelectRelatedPackage?(trimmed)
    }

    @objc public func triggerOpenWebsite() {
        presentation.onOpenWebsite?()
    }
}

private func BPSelectedFormulaLocalizedTitle(_ key: String, fallback: String) -> String {
    Bundle.main.localizedString(forKey: key, value: fallback, table: "BPSelectedFormula")
}

@MainActor
private struct BPSelectedFormulaInspectorView: View {
    @ObservedObject var presentation: BPSelectedFormulaPresentation

    private var emptyValue: String {
        NSLocalizedString("Info_View_Empty_Value", comment: "")
    }

    private var multipleValue: String {
        NSLocalizedString("Info_View_Multiple_Values", comment: "")
    }

    private var descriptionValue: String {
        switch presentation.state.selection {
        case .none, .multiple:
            return emptyValue
        case .single(let snapshot):
            return snapshot.shortDescription ?? NSLocalizedString("Info_View_Formula_No_Description", comment: "")
        }
    }

    private var installedValue: String {
        switch presentation.state.selection {
        case .none:
            return emptyValue
        case .multiple:
            return multipleValue
        case .single(let snapshot):
            if snapshot.isInstalled {
                return snapshot.installPath ?? emptyValue
            }
            return NSLocalizedString("Info_View_Formula_Not_Installed", comment: "")
        }
    }

    private var copyableInstallPath: String? {
        guard case .single(let snapshot) = presentation.state.selection,
              snapshot.isInstalled,
              let path = snapshot.installPath,
              !path.isEmpty else {
            return nil
        }
        return path
    }

    private var versionValue: String {
        switch presentation.state.selection {
        case .none:
            return emptyValue
        case .multiple:
            return multipleValue
        case .single(let snapshot):
            return snapshot.latestVersion ?? emptyValue
        }
    }

    private var dependenciesValue: String {
        switch presentation.state.selection {
        case .none:
            return emptyValue
        case .multiple:
            return multipleValue
        case .single(let snapshot):
            return snapshot.dependencies ?? NSLocalizedString("Info_View_Formula_No_Dependencies", comment: "")
        }
    }

    private var conflictsValue: String {
        switch presentation.state.selection {
        case .none:
            return emptyValue
        case .multiple:
            return multipleValue
        case .single(let snapshot):
            return snapshot.conflicts ?? NSLocalizedString("Info_View_Formula_No_Conflicts", comment: "")
        }
    }

    private var requiredByValue: String {
        guard case .single = presentation.state.selection,
              let dependents = presentation.state.dependents,
              !dependents.isEmpty else {
            return emptyValue
        }
        return dependents.joined(separator: ", ")
    }

    private var headerSymbolName: String {
        if case .single(let snapshot) = presentation.state.selection {
            return snapshot.identity.cask ? "macwindow" : "shippingbox.fill"
        }
        return "info.circle"
    }

    private var relatedPackageNames: [String] {
        guard case .single(let snapshot) = presentation.state.selection,
              !snapshot.identity.cask else {
            return []
        }
        var seen = Set<String>()
        var result: [String] = []
        for dep in snapshot.dependencyNames {
            if seen.insert(dep).inserted {
                result.append(dep)
            }
        }
        if let dependents = presentation.state.dependents {
            for dep in dependents {
                let trimmed = dep.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && seen.insert(trimmed).inserted {
                    result.append(trimmed)
                }
            }
        }
        return result
    }

    var body: some View {
        ScrollView(.vertical) {
            if case .none = presentation.state.selection {
                ContentUnavailableView("Select a Package", systemImage: "shippingbox", description: Text("Choose a package to explore its version, dependencies, and installation details."))
                    .frame(minHeight: 300)
            } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: headerSymbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(selectionTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("formula.detail.header")
                    Spacer()
                    if case .single = presentation.state.selection {
                        if let path = copyableInstallPath {
                            Button {
                                let firstToken = path.components(separatedBy: " ").first ?? path
                                let url = URL(fileURLWithPath: firstToken)
                                if FileManager.default.fileExists(atPath: url.path) {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            } label: {
                                Image(systemName: "folder")
                                    .font(.body)
                            }
                            .buttonStyle(.borderless)
                            .help(NSLocalizedString("Services_Reveal_File", comment: ""))
                            .accessibilityIdentifier("formula.detail.revealPath")
                            .accessibilityLabel(Text("Reveal installation in Finder"))

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(path, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.body)
                            }
                            .buttonStyle(.borderless)
                            .help(NSLocalizedString("Services_Copy_Output", comment: ""))
                            .accessibilityIdentifier("formula.detail.copyPath")
                            .accessibilityLabel(Text("Copy installation path"))
                        }

                        if presentation.onOpenWebsite != nil {
                            Button {
                                presentation.onOpenWebsite?()
                            } label: {
                                Image(systemName: "safari")
                                    .font(.body)
                            }
                            .buttonStyle(.borderless)
                            .help(NSLocalizedString("Toolbar_Formula_Website", comment: ""))
                            .accessibilityIdentifier("formula.detail.website")
                            .accessibilityLabel(NSLocalizedString("Toolbar_Formula_Website", comment: ""))
                        }
                    }
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 16) {
                    inspectorRow(
                        title: BPSelectedFormulaLocalizedTitle("y6Q-3P-Z8p.title", fallback: "Description:"),
                        value: descriptionValue,
                        voiceOverLabel: NSLocalizedString("Detail_VoiceOver_Description", comment: ""),
                        identifier: "formula.detail.description")
                    inspectorRow(
                        title: BPSelectedFormulaLocalizedTitle("Vpa-gA-Haq.title", fallback: "Installed:"),
                        value: installedValue,
                        voiceOverLabel: NSLocalizedString("Detail_VoiceOver_Installed", comment: ""),
                        identifier: "formula.detail.installed")
                    inspectorRow(
                        title: BPSelectedFormulaLocalizedTitle("0oO-wP-SOX.title", fallback: "Version:"),
                        value: versionValue,
                        voiceOverLabel: NSLocalizedString("Detail_VoiceOver_Version", comment: ""),
                        identifier: "formula.detail.version")
                    inspectorRow(
                        title: BPSelectedFormulaLocalizedTitle("v3f-Nd-iQs.title", fallback: "Dependencies:"),
                        value: dependenciesValue,
                        voiceOverLabel: NSLocalizedString("Detail_VoiceOver_Dependencies", comment: ""),
                        identifier: "formula.detail.dependencies")
                    inspectorRow(
                        title: BPSelectedFormulaLocalizedTitle("jTd-ja-Dck.title", fallback: "Conflicts:"),
                        value: conflictsValue,
                        voiceOverLabel: NSLocalizedString("Detail_VoiceOver_Conflicts", comment: ""),
                        identifier: "formula.detail.conflicts")
                    inspectorRow(
                        title: BPSelectedFormulaLocalizedTitle("cbk-Dpt-tc.title", fallback: "Required by:"),
                        value: requiredByValue,
                        voiceOverLabel: NSLocalizedString("Detail_VoiceOver_RequiredBy", comment: ""),
                        identifier: "formula.detail.requiredBy")
                    if let license = presentation.details.license {
                        inspectorRow(title: NSLocalizedString("License:", comment: ""), value: license,
                                     voiceOverLabel: NSLocalizedString("License", comment: ""),
                                     identifier: "formula.detail.license")
                    }
                    if presentation.state.showsPinnedRow {
                        inspectorRow(
                            title: BPSelectedFormulaLocalizedTitle("cbk-Pin-tc.title", fallback: "Pinned:"),
                            value: NSLocalizedString("Generic_Yes", comment: ""),
                            voiceOverLabel: NSLocalizedString("Sidebar_Item_Pinned", comment: ""),
                            identifier: "formula.detail.pinned")
                    }
                }

                if case .single(let snapshot) = presentation.state.selection {
                    BPVersionHistoryView(identity: snapshot.identity, sourceURL: presentation.details.source)
                        .id(snapshot.identity)
                }

                if let source = presentation.details.source {
                    Link(destination: source) {
                        Label("Homebrew Source", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .accessibilityIdentifier("formula.detail.source")
                }

                if let information = presentation.details.information {
                    DisclosureGroup(isExpanded: $presentation.showsHomebrewOutput) {
                        VStack(alignment: .leading, spacing: 10) {
                            Button("Copy Output", systemImage: "doc.on.doc") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(information, forType: .string)
                            }
                            .accessibilityIdentifier("formula.detail.copyOutput")
                            Text(information)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("formula.detail.output")
                                .accessibilityValue(information)
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Homebrew Output")
                            .contentShape(Rectangle())
                            .onTapGesture { presentation.showsHomebrewOutput.toggle() }
                    }
                }

                if presentation.onSelectRelatedPackage != nil && !relatedPackageNames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(relatedPackageNames.prefix(8), id: \.self) { pkgName in
                                Button {
                                    presentation.onSelectRelatedPackage?(pkgName)
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.turn.down.right")
                                            .font(.system(size: 8.5, weight: .semibold))
                                        Text(pkgName)
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .accessibilityIdentifier("formula.detail.chipLabel.\(pkgName)")
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.primary.opacity(0.06))
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("formula.detail.chip.\(pkgName)")
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .accessibilityIdentifier("formula.inspector")
    }

    private var selectionTitle: String {
        if case .single(let snapshot) = presentation.state.selection { return snapshot.identity.name }
        return NSLocalizedString("Multiple Packages", comment: "")
    }

    @ViewBuilder
    private func inspectorRow(title: String, value: String, voiceOverLabel: String, identifier: String) -> some View {
        GridRow {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(voiceOverLabel)
                .accessibilityValue(value)
                .accessibilityIdentifier(identifier)
        }
    }
}
