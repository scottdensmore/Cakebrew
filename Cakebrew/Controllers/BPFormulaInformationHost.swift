import AppKit
import ObjectiveC
import SwiftUI

@MainActor
private final class BPFormulaInformationPresentation: ObservableObject {
    @Published var state = BPFormulaInformationState()
}

/// This facade exposes only Cocoa types in the generated Objective-C header.
@MainActor
@objc(BPFormulaInformationHost)
public final class BPFormulaInformationHost: NSObject {
    private let presentation = BPFormulaInformationPresentation()
    @objc public let viewController: NSViewController

    public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPFormulaInformationView(presentation: presentation))
        host.preferredContentSize = NSSize(width: 460, height: 320)
        viewController = host
        super.init()
    }

    @objc(beginWithName:cask:)
    public func begin(name: String, cask: Bool) -> UInt64 {
        begin(name: name, cask: cask, infoType: 0)
    }

    @objc(beginWithName:cask:infoType:)
    public func begin(name: String, cask: Bool, infoType: Int) -> UInt64 {
        presentation.state.begin(name: name, cask: cask, mode: BPFormulaInformationMode(rawInfoType: infoType)).generation
    }

    @objc(receiveInformation:website:name:cask:generation:)
    public func receive(information: String?, website: URL?, name: String, cask: Bool, generation: UInt64) {
        receive(information: information, website: website, name: name, cask: cask, infoType: 0, generation: generation)
    }

    @objc(receiveInformation:website:name:cask:infoType:generation:)
    public func receive(information: String?, website: URL?, name: String, cask: Bool, infoType: Int, generation: UInt64) {
        let mode = BPFormulaInformationMode(rawInfoType: infoType)
        presentation.state.receive(request: BPFormulaInformationRequest(
            identity: BPFormulaInformationIdentity(name: name, cask: cask, mode: mode), generation: generation),
            information: information, website: website)
    }

    @objc public func close() {
        presentation.state.close()
    }

    @objc
    @discardableResult
    public func copyInformationToPasteboard() -> String {
        let text = presentation.state.information ?? ""
        guard !text.isEmpty else { return "" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return text
    }
}

func BPFormulaInformationAttributedText(_ information: String) -> AttributedString {
    let attributed = NSMutableAttributedString(string: information)
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        let range = NSRange(location: 0, length: attributed.length)
        detector.enumerateMatches(in: information, range: range) { match, _, _ in
            if let match, let url = match.url {
                attributed.addAttribute(.link, value: url, range: match.range)
            }
        }
    }
    return AttributedString(attributed)
}

@MainActor
private struct BPFormulaInformationView: View {
    @ObservedObject var presentation: BPFormulaInformationPresentation

    private var mode: BPFormulaInformationMode {
        presentation.state.request?.identity.mode ?? .general
    }

    private var isCask: Bool {
        presentation.state.request?.identity.cask ?? false
    }

    private var headerSymbolName: String {
        switch mode {
        case .general:
            return isCask ? "macwindow" : "shippingbox.fill"
        case .installedDependents, .allDependents:
            return "point.3.connected.trianglepath.dotted"
        }
    }

    private var kindBadgeText: String {
        isCask
            ? BPLocalizedWithFallback("Casks", fallback: "Cask")
            : BPLocalizedWithFallback("Formulae", fallback: "Formula")
    }

    private var titleText: String {
        let name = presentation.state.request?.identity.name ?? ""
        switch mode {
        case .general:
            return String(format: NSLocalizedString("Information_Title", comment: "Package information popover title"), name)
        case .installedDependents:
            return String(format: NSLocalizedString("Formula_Installed_Dependents_Title", comment: "Installed dependents popover title"), name)
        case .allDependents:
            return String(format: NSLocalizedString("Formula_All_Dependents_Title", comment: "All dependents popover title"), name)
        }
    }

    private var titleIdentifier: String {
        mode == .general ? "formula.information.title" : "formula.dependents.title"
    }

    private var loadingIdentifier: String {
        mode == .general ? "formula.information.loading" : "formula.dependents.loading"
    }

    private var textIdentifier: String {
        mode == .general ? "formula.information.text" : "formula.dependents.text"
    }

    private var unavailableText: String {
        switch mode {
        case .general:
            return NSLocalizedString("Information_Unavailable", comment: "No package information was returned")
        case .installedDependents, .allDependents:
            return NSLocalizedString("Info_View_Empty_Value", comment: "No dependents placeholder")
        }
    }

    private var unavailableIdentifier: String {
        mode == .general ? "formula.information.unavailable" : "formula.dependents.empty"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: headerSymbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                Text(titleText)
                    .font(.headline)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(titleIdentifier)

                Text(kindBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )

                Spacer(minLength: 4)

                if let website = presentation.state.website {
                    Button {
                        NSWorkspace.shared.open(website)
                    } label: {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.borderless)
                    .help(website.absoluteString)
                    .accessibilityIdentifier("formula.information.website")
                }

                if let info = presentation.state.information, !info.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(info, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help(BPLocalizedWithFallback("Services_Copy_Output", fallback: "Copy Output"))
                    .accessibilityIdentifier("formula.information.copy")
                }
            }
            Divider()
            if presentation.state.isLoading {
                ProgressView(NSLocalizedString("Loading_Status_Default", comment: ""))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier(loadingIdentifier)
            } else if let information = presentation.state.information {
                ScrollView {
                    Text(BPFormulaInformationAttributedText(information))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(textIdentifier)
                }
            } else {
                Text(unavailableText)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityIdentifier(unavailableIdentifier)
            }
        }
        .padding(16)
        .frame(width: 460, height: 320)
    }
}

@MainActor
private final class BPSelectedFormulaPresentation: ObservableObject {
    @Published var state = BPSelectedFormulaState()
    var onSelectRelatedPackage: ((String) -> Void)?
    var onShowMoreInfo: (() -> Void)?
    var onOpenWebsite: (() -> Void)?
}

@MainActor
@objc(BPSelectedFormulaHost)
public final class BPSelectedFormulaHost: NSObject {
    private let presentation = BPSelectedFormulaPresentation()
    @objc public let viewController: NSViewController

    @objc public var onSelectRelatedPackage: ((String) -> Void)? {
        get { presentation.onSelectRelatedPackage }
        set { presentation.onSelectRelatedPackage = newValue }
    }

    @objc public var onShowMoreInfo: (() -> Void)? {
        get { presentation.onShowMoreInfo }
        set { presentation.onShowMoreInfo = newValue }
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
    }

    @objc public func showMultipleSelection() {
        presentation.state.selectMultiple()
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

    @objc public func triggerShowMoreInfo() {
        presentation.onShowMoreInfo?()
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: headerSymbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(BPSelectedFormulaLocalizedTitle("F2k-Nm-vhK.title", fallback: "Selected Formula Information"))
                        .font(.system(size: 13, weight: .bold))
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
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            .help(NSLocalizedString("Services_Reveal_File", comment: ""))
                            .accessibilityIdentifier("formula.detail.revealPath")

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(path, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            .help(NSLocalizedString("Services_Copy_Output", comment: ""))
                            .accessibilityIdentifier("formula.detail.copyPath")
                        }

                        if presentation.onShowMoreInfo != nil {
                            Button {
                                presentation.onShowMoreInfo?()
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            .help(NSLocalizedString("Toolbar_More_Information", comment: ""))
                            .accessibilityIdentifier("formula.detail.moreInfo")
                        }

                        if presentation.onOpenWebsite != nil {
                            Button {
                                presentation.onOpenWebsite?()
                            } label: {
                                Image(systemName: "safari")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            .help(NSLocalizedString("Toolbar_Formula_Website", comment: ""))
                            .accessibilityIdentifier("formula.detail.website")
                        }
                    }
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 5) {
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
                    if presentation.state.showsPinnedRow {
                        inspectorRow(
                            title: BPSelectedFormulaLocalizedTitle("cbk-Pin-tc.title", fallback: "Pinned:"),
                            value: NSLocalizedString("Generic_Yes", comment: ""),
                            voiceOverLabel: NSLocalizedString("Sidebar_Item_Pinned", comment: ""),
                            identifier: "formula.detail.pinned")
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func inspectorRow(title: String, value: String, voiceOverLabel: String, identifier: String) -> some View {
        GridRow {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(voiceOverLabel)
                .accessibilityValue(value)
                .accessibilityIdentifier(identifier)
        }
    }
}

private func BPMainMenuLocalizedTitle(_ key: String, fallback: String) -> String {
    Bundle.main.localizedString(forKey: key, value: fallback, table: "MainMenu")
}

@MainActor
private final class BPInstalledPackageListPresentation: ObservableObject {
    @Published var state = BPInstalledPackageListState()
    @Published var sortOrder: [KeyPathComparator<BPInstalledPackageRow>] = []
    weak var hostView: NSView?
    weak var tableView: NSTableView?
    var contextMenu: NSMenu?
    var bridgeCoordinator: BPInstalledTableBridgeCoordinator?
    var isSyncingTableSelection = false
    var onSelectionChanged: ((String?, Bool) -> Void)?
    var onSortChanged: ((String?, Bool) -> Void)?
    var onTableAction: ((Int) -> Void)?
    var onSpacePressed: (() -> Void)?

    func notifySelectionChanged() {
        if let selected = state.selectedRow {
            onSelectionChanged?(selected.name, selected.cask)
        } else {
            onSelectionChanged?(nil, state.isCaskList)
        }
    }

    @discardableResult
    func ensureTableViewAttached() -> NSTableView? {
        if let hostView {
            bridgeCoordinator?.attach(in: hostView)
        }
        return tableView
    }
}

@MainActor
@objc(BPInstalledPackageListHost)
public final class BPInstalledPackageListHost: NSObject {
    private let presentation = BPInstalledPackageListPresentation()
    nonisolated(unsafe) private var keyMonitor: Any?
    @objc public let viewController: NSViewController

    @objc public var onSelectionChanged: ((String?, Bool) -> Void)? {
        get { presentation.onSelectionChanged }
        set { presentation.onSelectionChanged = newValue }
    }

    @objc public var onSortChanged: ((String?, Bool) -> Void)? {
        get { presentation.onSortChanged }
        set { presentation.onSortChanged = newValue }
    }

    @objc public var onTableAction: ((Int) -> Void)? {
        get { presentation.onTableAction }
        set { presentation.onTableAction = newValue }
    }

    @objc public var onSpacePressed: (() -> Void)? {
        get { presentation.onSpacePressed }
        set { presentation.onSpacePressed = newValue }
    }

    @objc public var contextMenu: NSMenu? {
        get { presentation.contextMenu }
        set {
            presentation.contextMenu = newValue
            presentation.ensureTableViewAttached()?.menu = newValue
        }
    }

    @objc public var rowCount: Int {
        presentation.state.displayedRows.count
    }

    @objc public var selectedRow: Int {
        presentation.state.selectedRowIndex
    }

    @objc public var selectedCount: Int {
        presentation.state.selectedIDs.count
    }

    @objc public var selectedPackageName: String? {
        presentation.state.selectedRow?.name
    }

    @objc public var selectedPackageCask: Bool {
        presentation.state.selectedRow?.cask ?? false
    }

    @objc public var selectedPackageNames: [String] {
        presentation.state.selectedRows.map(\.name)
    }

    @objc public var selectedPackageCasks: [NSNumber] {
        presentation.state.selectedRows.map { NSNumber(value: $0.cask) }
    }

    @objc public var listMode: Int {
        get { presentation.state.mode.rawValue }
        set { presentation.state.setMode(BPPackageListMode(rawMode: newValue)) }
    }

    public override init() {
        let presentation = self.presentation
        let coordinator = BPInstalledTableBridgeCoordinator(presentation: presentation)
        presentation.bridgeCoordinator = coordinator
        let host = BPInstalledPackageHostingController(
            rootView: BPInstalledPackageListView(presentation: presentation),
            presentation: presentation)
        host.sizingOptions = []
        presentation.hostView = host.view
        viewController = host
        super.init()
        installKeyboardMonitor()
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    @objc(updateRowsWithNames:versions:latestVersions:statusRanks:pinnedFlags:cask:)
    public func updateRows(names: [String],
                           versions: [String],
                           latestVersions: [String],
                           statusRanks: [NSNumber],
                           pinnedFlags: [NSNumber],
                           cask: Bool) {
        let count = names.count
        var rows: [BPInstalledPackageRow] = []
        rows.reserveCapacity(count)
        for index in 0..<count {
            let version = index < versions.count ? versions[index] : ""
            let latest = index < latestVersions.count ? latestVersions[index] : ""
            let rank = index < statusRanks.count ? statusRanks[index].intValue : 1
            let pinned = index < pinnedFlags.count ? pinnedFlags[index].boolValue : false
            rows.append(BPInstalledPackageRow(
                name: names[index],
                cask: cask,
                version: version,
                latestVersion: latest,
                statusRank: rank,
                isPinned: pinned))
        }
        let previousSelection = presentation.state.selectedIDs
        presentation.state.replaceRows(rows, isCaskList: cask)
        syncUnderlyingTableSelection()
        if presentation.state.selectedIDs != previousSelection {
            presentation.notifySelectionChanged()
        }
    }

    @objc(updateRowsWithNames:versions:latestVersions:statusRanks:pinnedFlags:caskFlags:mode:)
    public func updateRows(names: [String],
                           versions: [String],
                           latestVersions: [String],
                           statusRanks: [NSNumber],
                           pinnedFlags: [NSNumber],
                           caskFlags: [NSNumber],
                           mode rawMode: Int) {
        let resolvedMode = BPPackageListMode(rawMode: rawMode)
        replaceRows(names: names,
                    versions: versions,
                    latestVersions: latestVersions,
                    statusRanks: statusRanks,
                    pinnedFlags: pinnedFlags,
                    caskFlags: caskFlags,
                    resolvedMode: resolvedMode)
    }

    @objc(updateRowsForObjCModeWithNames:versions:latestVersions:statusRanks:pinnedFlags:caskFlags:objcListMode:)
    public func updateRowsForObjCMode(names: [String],
                                      versions: [String],
                                      latestVersions: [String],
                                      statusRanks: [NSNumber],
                                      pinnedFlags: [NSNumber],
                                      caskFlags: [NSNumber],
                                      objcListMode: Int) {
        let resolvedMode = BPPackageListMode(objcListMode: objcListMode)
        replaceRows(names: names,
                    versions: versions,
                    latestVersions: latestVersions,
                    statusRanks: statusRanks,
                    pinnedFlags: pinnedFlags,
                    caskFlags: caskFlags,
                    resolvedMode: resolvedMode)
    }

    private func replaceRows(names: [String],
                             versions: [String],
                             latestVersions: [String],
                             statusRanks: [NSNumber],
                             pinnedFlags: [NSNumber],
                             caskFlags: [NSNumber],
                             resolvedMode: BPPackageListMode) {
        let count = names.count
        var rows: [BPInstalledPackageRow] = []
        rows.reserveCapacity(count)
        for index in 0..<count {
            let version = index < versions.count ? versions[index] : ""
            let latest = index < latestVersions.count ? latestVersions[index] : ""
            let rank = index < statusRanks.count ? statusRanks[index].intValue : 1
            let pinned = index < pinnedFlags.count ? pinnedFlags[index].boolValue : false
            let cask = index < caskFlags.count ? caskFlags[index].boolValue : resolvedMode.isCaskMode
            rows.append(BPInstalledPackageRow(
                name: names[index],
                cask: cask,
                version: version,
                latestVersion: latest,
                statusRank: rank,
                isPinned: pinned))
        }
        let previousSelection = presentation.state.selectedIDs
        presentation.state.replaceRows(rows, mode: resolvedMode)
        syncUnderlyingTableSelection()
        if presentation.state.selectedIDs != previousSelection {
            presentation.notifySelectionChanged()
        }
    }

    @objc(applySortColumnIdentifier:ascending:)
    public func applySort(columnIdentifier: String?, ascending: Bool) {
        guard let columnIdentifier,
              let column = BPInstalledPackageSortColumn(rawValue: columnIdentifier) else {
            presentation.state.setSort(column: nil, ascending: true)
            presentation.sortOrder = []
            return
        }
        presentation.state.setSort(column: column, ascending: ascending)
        let order: SortOrder = ascending ? .forward : .reverse
        switch column {
        case .name:
            presentation.sortOrder = [KeyPathComparator(\BPInstalledPackageRow.name, order: order)]
        case .version:
            presentation.sortOrder = [KeyPathComparator(\BPInstalledPackageRow.version, order: order)]
        case .latestVersion:
            presentation.sortOrder = [KeyPathComparator(\BPInstalledPackageRow.latestVersion, order: order)]
        case .status:
            presentation.sortOrder = [KeyPathComparator(\BPInstalledPackageRow.statusRank, order: order)]
        }
    }

    @objc(indexOfPackageNamed:cask:)
    public func index(ofPackageNamed name: String, cask: Bool) -> Int {
        presentation.state.index(ofName: name, cask: cask)
    }

    @objc(selectPackageNamed:cask:)
    @discardableResult
    public func selectPackage(named name: String, cask: Bool) -> Bool {
        let didSelect = presentation.state.select(name: name, cask: cask)
        syncUnderlyingTableSelection()
        presentation.notifySelectionChanged()
        return didSelect
    }

    @objc public func deselectAll() {
        presentation.state.select(id: nil)
        presentation.isSyncingTableSelection = true
        defer { presentation.isSyncingTableSelection = false }
        presentation.ensureTableViewAttached()?.deselectAll(nil)
        presentation.notifySelectionChanged()
    }

    @objc public func selectClickedRowIfNeeded() {
        guard let tableView = presentation.ensureTableViewAttached() else { return }
        let clicked = tableView.clickedRow
        guard clicked >= 0 && clicked < presentation.state.displayedRows.count else { return }
        if !presentation.state.selectedRowIndexes.contains(clicked) {
            if presentation.state.selectRow(at: clicked) {
                presentation.isSyncingTableSelection = true
                defer { presentation.isSyncingTableSelection = false }
                tableView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
                presentation.notifySelectionChanged()
            }
        }
    }

    @objc(rectOfSelectedRowInView:)
    public func rectOfSelectedRow(in targetView: NSView) -> NSRect {
        let row = presentation.state.selectedRowIndex
        if let tableView = presentation.ensureTableViewAttached(),
           row >= 0,
           row < tableView.numberOfRows {
            let rect = tableView.rect(ofRow: row)
            if !rect.isEmpty {
                return targetView.convert(rect, from: tableView)
            }
        }
        return NSRect(x: 0, y: 0, width: max(targetView.bounds.width, 1), height: 24)
    }

    private func syncUnderlyingTableSelection() {
        guard let tableView = presentation.ensureTableViewAttached() else { return }
        presentation.isSyncingTableSelection = true
        defer { presentation.isSyncingTableSelection = false }
        let indexes = presentation.state.selectedRowIndexes
        if !indexes.isEmpty {
            let validIndexes = IndexSet(indexes.filter { $0 >= 0 && $0 < tableView.numberOfRows })
            if !validIndexes.isEmpty {
                tableView.selectRowIndexes(validIndexes, byExtendingSelection: false)
                if let first = validIndexes.first {
                    tableView.scrollRowToVisible(first)
                }
                return
            }
        }
        tableView.deselectAll(nil)
    }

    private func installKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    @objc(handleKeyDownEvent:)
    public func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let characters = event.charactersIgnoringModifiers,
              characters.utf16.count == 1,
              let key = characters.utf16.first else {
            return false
        }
        guard isTableFocused() else { return false }
        guard presentation.state.selectedRow != nil else { return false }

        if key == 0x0020 {
            presentation.onSpacePressed?()
            return true
        }

        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard !event.isARepeat,
              event.modifierFlags.intersection(disallowedModifiers).isEmpty else {
            return false
        }

        if key == UInt16(NSCarriageReturnCharacter) || key == UInt16(NSEnterCharacter) {
            presentation.onTableAction?(0) // BPFormulaeTableRequestPrimary
            return true
        }
        if key == UInt16(NSDeleteCharacter) || key == UInt16(NSDeleteFunctionKey) {
            presentation.onTableAction?(1) // BPFormulaeTableRequestUninstall
            return true
        }
        return false
    }

    private func isTableFocused() -> Bool {
        guard let window = viewController.view.window,
              !viewController.view.isHiddenOrHasHiddenAncestor,
              let responder = window.firstResponder as? NSView else {
            return false
        }
        return responder == viewController.view || responder.isDescendant(of: viewController.view)
    }
}

@MainActor
private final class BPInstalledTableBridgeCoordinator: NSObject {
    private static var patchedMenuTableClasses = Set<ObjectIdentifier>()
    weak var presentation: BPInstalledPackageListPresentation?

    init(presentation: BPInstalledPackageListPresentation) {
        self.presentation = presentation
    }

    func attachIfNeeded(from anchorView: NSView) {
        if let hostView = presentation?.hostView {
            attach(in: hostView)
            return
        }
        var root: NSView = anchorView
        while let parent = root.superview {
            root = parent
        }
        attach(in: root)
    }

    func attach(in root: NSView) {
        guard let tableView = Self.findTableView(in: root) else { return }
        Self.enableAppKitMenuStorageIfNeeded(on: tableView)
        if presentation?.tableView !== tableView {
            presentation?.tableView = tableView
            tableView.setAccessibilityLabel(NSLocalizedString("Formulae", comment: ""))
        }
        let allowsMulti = presentation?.state.mode.allowsMultipleSelection ?? false
        if tableView.allowsMultipleSelection != allowsMulti {
            tableView.allowsMultipleSelection = allowsMulti
        }
        if tableView.target !== self || tableView.doubleAction != #selector(handleDoubleClick(_:)) {
            tableView.target = self
            tableView.doubleAction = #selector(handleDoubleClick(_:))
        }
        if tableView.menu !== presentation?.contextMenu {
            tableView.menu = presentation?.contextMenu
        }
    }

    private static func enableAppKitMenuStorageIfNeeded(on tableView: NSTableView) {
        guard let cls: AnyClass = object_getClass(tableView) else { return }
        let classID = ObjectIdentifier(cls)
        guard !patchedMenuTableClasses.contains(classID) else { return }
        patchedMenuTableClasses.insert(classID)

        let getterSel = #selector(getter: NSView.menu)
        let setterSel = #selector(setter: NSView.menu)
        guard let nsViewGetter = class_getInstanceMethod(NSView.self, getterSel),
              let nsViewSetter = class_getInstanceMethod(NSView.self, setterSel),
              let clsGetter = class_getInstanceMethod(cls, getterSel),
              let clsSetter = class_getInstanceMethod(cls, setterSel),
              clsGetter != nsViewGetter || clsSetter != nsViewSetter else {
            return
        }

        typealias GetterIMP = @convention(c) (AnyObject, Selector) -> NSMenu?
        typealias SetterIMP = @convention(c) (AnyObject, Selector, NSMenu?) -> Void
        let superGet = unsafeBitCast(method_getImplementation(nsViewGetter), to: GetterIMP.self)
        let superSet = unsafeBitCast(method_getImplementation(nsViewSetter), to: SetterIMP.self)
        let origGet = unsafeBitCast(method_getImplementation(clsGetter), to: GetterIMP.self)

        let getBlock: @convention(block) (AnyObject) -> NSMenu? = { obj in
            if let menu = superGet(obj, getterSel) {
                return menu
            }
            return origGet(obj, getterSel)
        }
        let setBlock: @convention(block) (AnyObject, NSMenu?) -> Void = { obj, menu in
            superSet(obj, setterSel, menu)
        }

        method_setImplementation(clsGetter, imp_implementationWithBlock(getBlock))
        method_setImplementation(clsSetter, imp_implementationWithBlock(setBlock))
    }

    @objc private func handleDoubleClick(_ sender: NSTableView) {
        guard let presentation else { return }
        let row = sender.clickedRow
        guard row >= 0,
              row < sender.numberOfRows,
              row < presentation.state.displayedRows.count,
              sender.selectedRowIndexes.contains(row) else {
            return
        }
        if presentation.state.selectedRowIndex != row {
            _ = presentation.state.selectRow(at: row)
            presentation.notifySelectionChanged()
        }
        presentation.onTableAction?(0) // BPFormulaeTableRequestPrimary
    }

    private static func findTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView, !table.isHiddenOrHasHiddenAncestor {
            return table
        }
        for subview in view.subviews {
            if let found = findTableView(in: subview) {
                return found
            }
        }
        if let table = view as? NSTableView {
            return table
        }
        for subview in view.subviews {
            if let fallback = findAnyTableView(in: subview) {
                return fallback
            }
        }
        return nil
    }

    private static func findAnyTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView {
            return table
        }
        for subview in view.subviews {
            if let found = findAnyTableView(in: subview) {
                return found
            }
        }
        return nil
    }
}

@MainActor
private final class BPInstalledPackageHostingController: NSHostingController<BPInstalledPackageListView> {
    weak var presentation: BPInstalledPackageListPresentation?

    init(rootView: BPInstalledPackageListView, presentation: BPInstalledPackageListPresentation) {
        self.presentation = presentation
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        presentation?.ensureTableViewAttached()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        presentation?.ensureTableViewAttached()
    }
}

@MainActor
private final class BPInstalledTableBridgeAnchorView: NSView {
    weak var coordinator: BPInstalledTableBridgeCoordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.attachIfNeeded(from: self)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        coordinator?.attachIfNeeded(from: self)
    }

    override func layout() {
        super.layout()
        coordinator?.attachIfNeeded(from: self)
    }
}

@MainActor
private struct BPInstalledTableBridgeIntrospector: NSViewRepresentable {
    @ObservedObject var presentation: BPInstalledPackageListPresentation

    func makeCoordinator() -> BPInstalledTableBridgeCoordinator {
        presentation.bridgeCoordinator ?? BPInstalledTableBridgeCoordinator(presentation: presentation)
    }

    func makeNSView(context: Context) -> BPInstalledTableBridgeAnchorView {
        let view = BPInstalledTableBridgeAnchorView(frame: .zero)
        let coordinator = context.coordinator
        view.coordinator = coordinator
        DispatchQueue.main.async {
            coordinator.attachIfNeeded(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: BPInstalledTableBridgeAnchorView, context: Context) {
        let coordinator = context.coordinator
        nsView.coordinator = coordinator
        coordinator.attachIfNeeded(from: nsView)
        DispatchQueue.main.async {
            coordinator.attachIfNeeded(from: nsView)
        }
    }
}

@MainActor
private struct BPInstalledPackageListView: View {
    @ObservedObject var presentation: BPInstalledPackageListPresentation

    private var selectionSetBinding: Binding<Set<BPFormulaInformationIdentity>> {
        Binding(
            get: { presentation.state.selectedIDs },
            set: { newValue in
                guard !presentation.isSyncingTableSelection else { return }
                let oldSelection = presentation.state.selectedIDs
                presentation.state.select(ids: newValue)
                if presentation.state.selectedIDs != oldSelection {
                    presentation.notifySelectionChanged()
                }
            }
        )
    }

    private var sortOrderBinding: Binding<[KeyPathComparator<BPInstalledPackageRow>]> {
        Binding(
            get: { presentation.sortOrder },
            set: { newOrder in
                presentation.sortOrder = newOrder
                guard let first = newOrder.first else { return }
                let ascending = (first.order == .forward)
                let column: BPInstalledPackageSortColumn
                if first.keyPath == \BPInstalledPackageRow.name {
                    column = .name
                } else if first.keyPath == \BPInstalledPackageRow.latestVersion {
                    column = .latestVersion
                } else if first.keyPath == \BPInstalledPackageRow.statusRank {
                    column = .status
                } else {
                    column = .version
                }
                presentation.state.setSort(column: column, ascending: ascending)
                presentation.onSortChanged?(column.rawValue, ascending)
            }
        )
    }

    @ViewBuilder
    private func nameCell(_ row: BPInstalledPackageRow) -> some View {
        HStack(spacing: 5) {
            Text(row.name)
                .lineLimit(1)
                .accessibilityValue(row.name)
                .accessibilityIdentifier("package.row.\(row.name)")
            if row.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: NSFont.smallSystemFontSize))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(NSLocalizedString("Sidebar_Item_Pinned", comment: ""))
            }
        }
    }

    private func statusText(for statusRank: Int) -> String {
        switch statusRank {
        case 1:
            return NSLocalizedString("Formula_Status_Installed", comment: "")
        case 2:
            return NSLocalizedString("Formula_Status_Outdated", comment: "")
        default:
            return NSLocalizedString("Formula_Status_Not_Installed", comment: "")
        }
    }

    @ViewBuilder
    private func statusBadge(for statusRank: Int) -> some View {
        let text = statusText(for: statusRank)
        let tint: Color = (statusRank == 2) ? .orange : ((statusRank == 1) ? .green : .secondary)
        Text(text)
            .font(.caption)
            .fontWeight(statusRank == 2 ? .medium : .regular)
            .foregroundStyle(statusRank == 0 ? .secondary : .primary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(tint.opacity(statusRank == 0 ? 0.10 : 0.16))
            )
            .accessibilityValue(text)
    }

    @ViewBuilder
    private var modeTable: some View {
        let mode = presentation.state.mode
        if !mode.showsVersionColumn {
            Table(presentation.state.displayedRows, selection: selectionSetBinding, sortOrder: sortOrderBinding) {
                TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                    nameCell(row)
                }
            }
        } else if mode.showsLatestVersionColumn {
            Table(presentation.state.displayedRows, selection: selectionSetBinding, sortOrder: sortOrderBinding) {
                TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                    nameCell(row)
                }
                TableColumn(BPMainMenuLocalizedTitle("h5d-xc-Jih.headerCell.title", fallback: "Version"), value: \.version) { row in
                    Text(row.version)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityValue(row.version)
                }
                TableColumn(BPMainMenuLocalizedTitle("d93-10-421.headerCell.title", fallback: "Latest Version"), value: \.latestVersion) { row in
                    Text(row.latestVersion)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .accessibilityValue(row.latestVersion)
                }
            }
        } else if mode.showsStatusColumn && !mode.showsInstalledVersionColumn {
            Table(presentation.state.displayedRows, selection: selectionSetBinding, sortOrder: sortOrderBinding) {
                TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                    nameCell(row)
                }
                TableColumn(BPMainMenuLocalizedTitle("Be6-3F-p4b.headerCell.title", fallback: "Status"), value: \.statusRank) { row in
                    statusBadge(for: row.statusRank)
                }
            }
        } else if mode.showsStatusColumn {
            Table(presentation.state.displayedRows, selection: selectionSetBinding, sortOrder: sortOrderBinding) {
                TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                    nameCell(row)
                }
                TableColumn(BPMainMenuLocalizedTitle("h5d-xc-Jih.headerCell.title", fallback: "Version"), value: \.version) { row in
                    Text(row.version)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .accessibilityValue(row.version)
                }
                TableColumn(BPMainMenuLocalizedTitle("Be6-3F-p4b.headerCell.title", fallback: "Status"), value: \.statusRank) { row in
                    statusBadge(for: row.statusRank)
                }
            }
        } else {
            Table(presentation.state.displayedRows, selection: selectionSetBinding, sortOrder: sortOrderBinding) {
                TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                    nameCell(row)
                }
                TableColumn(BPMainMenuLocalizedTitle("h5d-xc-Jih.headerCell.title", fallback: "Version"), value: \.version) { row in
                    Text(row.version)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .accessibilityValue(row.version)
                }
            }
        }
    }

    var body: some View {
        modeTable
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .background(BPInstalledTableBridgeIntrospector(presentation: presentation))
    }
}

@MainActor
private final class BPUnifiedUpdatesPresentation: ObservableObject {
    @Published var state = BPUnifiedUpdatesState()
    var onSelectionChanged: (() -> Void)?
    var onUpgradeSelected: (([String], [String]) -> Void)?
    var onUpgradeAll: (() -> Void)?

    func triggerUpgradeSelected() {
        let formulae = state.selectedFormulaNames
        let casks = state.selectedCaskNames
        guard !formulae.isEmpty || !casks.isEmpty else { return }
        onUpgradeSelected?(formulae, casks)
    }

    func triggerUpgradeAll() {
        guard !state.eligibleRowIDs.isEmpty else { return }
        onUpgradeAll?()
    }
}

@MainActor
@objc(BPUnifiedUpdatesHost)
public final class BPUnifiedUpdatesHost: NSObject {
    private let presentation = BPUnifiedUpdatesPresentation()
    @objc public let viewController: NSViewController

    @objc public var selectedFormulaNames: [String] {
        presentation.state.selectedFormulaNames
    }

    @objc public var selectedCaskNames: [String] {
        presentation.state.selectedCaskNames
    }

    @objc public var rowCount: Int {
        presentation.state.formulaRows.count + presentation.state.caskRows.count
    }

    @objc public var selectedCount: Int {
        presentation.state.selectedIDs.count
    }

    @objc public var hasEligibleUpdates: Bool {
        !presentation.state.eligibleRowIDs.isEmpty
    }

    @objc public var hasFormulaUpdates: Bool {
        presentation.state.hasFormulaUpdates
    }

    @objc public var hasCaskUpdates: Bool {
        presentation.state.hasCaskUpdates
    }

    @objc public var isEmpty: Bool {
        presentation.state.isEmpty
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set { presentation.state.setFilterQuery(newValue) }
    }

    @objc public var onSelectionChanged: (() -> Void)? {
        get { presentation.onSelectionChanged }
        set { presentation.onSelectionChanged = newValue }
    }

    @objc public var onUpgradeSelected: (([String], [String]) -> Void)? {
        get { presentation.onUpgradeSelected }
        set { presentation.onUpgradeSelected = newValue }
    }

    @objc public var onUpgradeAll: (() -> Void)? {
        get { presentation.onUpgradeAll }
        set { presentation.onUpgradeAll = newValue }
    }

    public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPUnifiedUpdatesView(presentation: presentation))
        host.sizingOptions = []
        viewController = host
        super.init()
    }

    @objc public func selectAllEligible() {
        let previous = presentation.state.selectedIDs
        presentation.state.selectAllEligible()
        if presentation.state.selectedIDs != previous {
            presentation.onSelectionChanged?()
        }
    }

    @objc public func selectFormulaGroup() {
        let previous = presentation.state.selectedIDs
        presentation.state.selectEligibleFormulae()
        if presentation.state.selectedIDs != previous {
            presentation.onSelectionChanged?()
        }
    }

    @objc public func selectCaskGroup() {
        let previous = presentation.state.selectedIDs
        presentation.state.selectEligibleCasks()
        if presentation.state.selectedIDs != previous {
            presentation.onSelectionChanged?()
        }
    }

    @objc public func clearSelection() {
        let previous = presentation.state.selectedIDs
        presentation.state.clearSelection()
        if presentation.state.selectedIDs != previous {
            presentation.onSelectionChanged?()
        }
    }

    @objc public func upgradeSelected() {
        presentation.triggerUpgradeSelected()
    }

    @objc public func upgradeAll() {
        presentation.triggerUpgradeAll()
    }

    @objc(updateWithFormulaNames:formulaVersions:formulaLatestVersions:formulaPinnedFlags:caskNames:caskVersions:caskLatestVersions:caskPinnedFlags:)
    public func update(formulaNames: [String],
                       formulaVersions: [String],
                       formulaLatestVersions: [String],
                       formulaPinnedFlags: [NSNumber],
                       caskNames: [String],
                       caskVersions: [String],
                       caskLatestVersions: [String],
                       caskPinnedFlags: [NSNumber]) {
        var formulaRows: [BPUnifiedUpdateRow] = []
        formulaRows.reserveCapacity(formulaNames.count)
        for index in 0..<formulaNames.count {
            let version = index < formulaVersions.count ? formulaVersions[index] : ""
            let latest = index < formulaLatestVersions.count ? formulaLatestVersions[index] : ""
            let pinned = index < formulaPinnedFlags.count ? formulaPinnedFlags[index].boolValue : false
            formulaRows.append(BPUnifiedUpdateRow(
                name: formulaNames[index],
                cask: false,
                version: version,
                latestVersion: latest,
                isPinned: pinned))
        }

        var caskRows: [BPUnifiedUpdateRow] = []
        caskRows.reserveCapacity(caskNames.count)
        for index in 0..<caskNames.count {
            let version = index < caskVersions.count ? caskVersions[index] : ""
            let latest = index < caskLatestVersions.count ? caskLatestVersions[index] : ""
            let pinned = index < caskPinnedFlags.count ? caskPinnedFlags[index].boolValue : false
            caskRows.append(BPUnifiedUpdateRow(
                name: caskNames[index],
                cask: true,
                version: version,
                latestVersion: latest,
                isPinned: pinned))
        }

        let previous = presentation.state.selectedIDs
        presentation.state.replace(formulaRows: formulaRows, caskRows: caskRows)
        if presentation.state.selectedIDs != previous {
            presentation.onSelectionChanged?()
        }
    }
}

@MainActor
private struct BPUnifiedUpdatesView: View {
    @ObservedObject var presentation: BPUnifiedUpdatesPresentation

    private var formulaeGroupTitle: String {
        NSLocalizedString("Sidebar_Group_Formulae", comment: "")
    }

    private var casksGroupTitle: String {
        NSLocalizedString("Sidebar_Group_Casks", comment: "")
    }

    private var filterBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { presentation.state.setFilterQuery($0) }
        )
    }

    private func isSelectedBinding(for row: BPUnifiedUpdateRow) -> Binding<Bool> {
        Binding(
            get: { presentation.state.selectedIDs.contains(row.id) },
            set: { shouldSelect in
                guard row.isEligible else { return }
                let currentlySelected = presentation.state.selectedIDs.contains(row.id)
                guard shouldSelect != currentlySelected else { return }
                presentation.state.toggleSelection(for: row.id)
                presentation.onSelectionChanged?()
            }
        )
    }

    private func rowAccessibilityLabel(for row: BPUnifiedUpdateRow) -> String {
        let groupTitle = row.cask ? casksGroupTitle : formulaeGroupTitle
        var parts = [row.name, groupTitle]
        if !row.version.isEmpty || !row.latestVersion.isEmpty {
            parts.append("\(row.version) → \(row.latestVersion)")
        }
        if row.isPinned {
            parts.append(NSLocalizedString("Sidebar_Item_Pinned", comment: ""))
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func updateRowView(_ row: BPUnifiedUpdateRow) -> some View {
        let groupTitle = row.cask ? casksGroupTitle : formulaeGroupTitle
        let identifierPrefix = row.cask ? "unified.updates.row.cask" : "unified.updates.row.formula"
        let togglePrefix = row.cask ? "unified.updates.toggle.cask" : "unified.updates.toggle.formula"
        let spokenLabel = rowAccessibilityLabel(for: row)
        HStack(spacing: 8) {
            Toggle(isOn: isSelectedBinding(for: row)) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .accessibilityValue(row.name)
                        .accessibilityLabel(spokenLabel)
                        .accessibilityIdentifier("\(identifierPrefix).\(row.name)")
                    Text(groupTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.14))
                        )
                    if row.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: NSFont.smallSystemFontSize))
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("Sidebar_Item_Pinned", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .disabled(!row.isEligible)
            .accessibilityLabel(spokenLabel)
            .accessibilityIdentifier("\(togglePrefix).\(row.name)")

            Spacer()

            HStack(spacing: 4) {
                Text(row.version)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(row.latestVersion)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .padding(.vertical, 2)
    }

    var body: some View {
        if presentation.state.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("Empty_Outdated_Title", comment: ""))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("unified.updates.empty.title")
                Text(NSLocalizedString("Empty_Outdated_Message", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("unified.updates.empty.message")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .accessibilityIdentifier("unified.updates.empty")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Button(BPMainMenuLocalizedTitle("Ruw-6m-B2m.title", fallback: "Select All")) {
                        let previous = presentation.state.selectedIDs
                        presentation.state.selectAllEligible()
                        if presentation.state.selectedIDs != previous {
                            presentation.onSelectionChanged?()
                        }
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("unified.updates.selectAll")

                    if presentation.state.hasFormulaUpdates {
                        Button(formulaeGroupTitle) {
                            let previous = presentation.state.selectedIDs
                            presentation.state.selectEligibleFormulae()
                            if presentation.state.selectedIDs != previous {
                                presentation.onSelectionChanged?()
                            }
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("unified.updates.selectFormulae")
                    }

                    if presentation.state.hasCaskUpdates {
                        Button(casksGroupTitle) {
                            let previous = presentation.state.selectedIDs
                            presentation.state.selectEligibleCasks()
                            if presentation.state.selectedIDs != previous {
                                presentation.onSelectionChanged?()
                            }
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("unified.updates.selectCasks")
                    }

                    TextField(NSLocalizedString("Toolbar_Search", comment: ""), text: filterBinding)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(maxWidth: 180)
                        .accessibilityIdentifier("unified.updates.filter")

                    Spacer()

                    Button(NSLocalizedString("Toolbar_Update_Selected", comment: "")) {
                        presentation.triggerUpgradeSelected()
                    }
                    .controlSize(.small)
                    .disabled(presentation.state.selectedIDs.isEmpty)
                    .accessibilityIdentifier("unified.updates.upgradeSelected")

                    Button(NSLocalizedString("Dock_Upgrade_All_Outdated", comment: "")) {
                        presentation.triggerUpgradeAll()
                    }
                    .controlSize(.small)
                    .disabled(presentation.state.eligibleRowIDs.isEmpty)
                    .accessibilityIdentifier("unified.updates.upgradeAll")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                List {
                    let filteredFormulae = presentation.state.filteredFormulaRows
                    let filteredCasks = presentation.state.filteredCaskRows
                    if !filteredFormulae.isEmpty {
                        Section {
                            ForEach(filteredFormulae) { row in
                                updateRowView(row)
                            }
                        } header: {
                            Text(formulaeGroupTitle)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("unified.updates.section.formulae")
                        }
                    }

                    if !filteredCasks.isEmpty {
                        Section {
                            ForEach(filteredCasks) { row in
                                updateRowView(row)
                            }
                        } header: {
                            Text(casksGroupTitle)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("unified.updates.section.casks")
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .accessibilityIdentifier("unified.updates.list")
            }
        }
    }
}

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

// MARK: - Shared AppKit View Containers for Streaming Logs & Tables

@MainActor
private struct BPNSViewContainerRepresentable: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        if view.superview !== container {
            view.removeFromSuperview()
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if view.superview !== nsView {
            view.removeFromSuperview()
            view.translatesAutoresizingMaskIntoConstraints = false
            nsView.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
                view.topAnchor.constraint(equalTo: nsView.topAnchor),
                view.bottomAnchor.constraint(equalTo: nsView.bottomAnchor)
            ])
        }
    }
}

@MainActor
private struct BPTextViewContainerRepresentable: NSViewRepresentable {
    let textView: NSTextView

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        embedTextView(in: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        embedTextView(in: nsView)
    }

    private func embedTextView(in container: NSView) {
        let scrollView: NSScrollView
        if let existingScroll = textView.enclosingScrollView {
            scrollView = existingScroll
        } else {
            let created = NSScrollView(frame: .zero)
            created.hasVerticalScroller = true
            created.hasHorizontalScroller = false
            created.autohidesScrollers = true
            created.borderType = .bezelBorder
            created.drawsBackground = true
            textView.isEditable = false
            textView.isSelectable = true
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            created.documentView = textView
            scrollView = created
        }
        if scrollView.superview !== container {
            scrollView.removeFromSuperview()
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(scrollView)
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: container.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
    }
}

// MARK: - SwiftUI Empty State Host

@MainActor
@objc(BPEmptyStateHost)
public final class BPEmptyStateHost: NSObject {
    @objc public let viewController: NSViewController
    public let model: BPEmptyStateModel

    @objc(initWithSymbolName:title:message:)
    public init(symbolName: String, title: String, message: String) {
        let model = BPEmptyStateModel(symbolName: symbolName, title: title, message: message)
        self.model = model
        let host = NSHostingController(rootView: BPEmptyStateSwiftUIView(model: model))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }
}

@MainActor
private struct BPEmptyStateSwiftUIView: View {
    let model: BPEmptyStateModel

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: model.symbolName)
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(model.title)
                .font(.system(size: NSFont.systemFontSize + 3, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityValue(model.title)
            Text(model.message)
                .font(.system(size: NSFont.smallSystemFontSize))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .accessibilityValue(model.message)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.combinedAccessibilityLabel)
        .accessibilityValue(model.combinedAccessibilityLabel)
    }
}

// MARK: - SwiftUI Loading Overlay Host

@MainActor
@objc(BPLoadingHost)
public final class BPLoadingHost: NSObject {
    @objc public let viewController: NSViewController

    public override init() {
        let host = NSHostingController(rootView: BPLoadingSwiftUIView())
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }
}

@MainActor
private struct BPLoadingSwiftUIView: View {
    private var loadingTitle: String {
        Bundle.main.localizedString(forKey: "a1c-mR-c5p.title", value: "Loading", table: "Loading")
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(loadingTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityValue(loadingTitle)
                .accessibilityIdentifier("loading.title")
            ProgressView()
                .controlSize(.regular)
                .accessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
                .accessibilityIdentifier("loading.progress")
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SwiftUI Disabled / Recovery Overlay Host

@MainActor
private final class BPDisabledPresentation: ObservableObject {
    @Published var state = BPDisabledRecoveryState(
        title: NSLocalizedString("Homebrew wasn’t found", comment: ""),
        message: NSLocalizedString("Cakebrew couldn’t find Homebrew in your login shell’s PATH. Open brew.sh for installation instructions, or fix your shell configuration, then choose Try Again.", comment: ""),
        retryEnabled: true,
        isChecking: false
    )
    var onRetry: (() -> Void)?
    var onOpenInstructions: (() -> Void)?
}

@MainActor
@objc(BPDisabledHost)
public final class BPDisabledHost: NSObject {
    private let presentation = BPDisabledPresentation()
    @objc public let viewController: NSViewController

    @objc public var onRetry: (() -> Void)? {
        get { presentation.onRetry }
        set { presentation.onRetry = newValue }
    }

    @objc public var onOpenInstructions: (() -> Void)? {
        get { presentation.onOpenInstructions }
        set { presentation.onOpenInstructions = newValue }
    }

    public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPDisabledSwiftUIView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(updateWithTitle:message:retryEnabled:checking:)
    public func update(title: String, message: String, retryEnabled: Bool, checking: Bool) {
        presentation.state = BPDisabledRecoveryState(
            title: title,
            message: message,
            retryEnabled: retryEnabled,
            isChecking: checking
        )
    }
}

@MainActor
private struct BPDisabledSwiftUIView: View {
    @ObservedObject var presentation: BPDisabledPresentation

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: presentation.state.isChecking ? "magnifyingglass.circle" : "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)

            Text(presentation.state.title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .accessibilityValue(presentation.state.title)
                .accessibilityIdentifier("homebrew.recovery.title")

            Text(presentation.state.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .accessibilityValue(presentation.state.message)
                .accessibilityIdentifier("homebrew.recovery.message")

            HStack(spacing: 12) {
                Button(NSLocalizedString("Try Again", comment: "")) {
                    presentation.onRetry?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!presentation.state.retryEnabled)
                .accessibilityIdentifier("homebrew.retry")

                Button(NSLocalizedString("Open brew.sh", comment: "")) {
                    presentation.onOpenInstructions?()
                }
                .accessibilityIdentifier("homebrew.install")
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SwiftUI Console Tool Host (Doctor & Update)

@MainActor
private final class BPConsoleToolPresentation: ObservableObject {
    @Published var state: BPConsoleToolState
    let textView: NSTextView
    var onRun: (() -> Void)?
    var onClear: (() -> Void)?

    init(textView: NSTextView, state: BPConsoleToolState) {
        self.textView = textView
        self.state = state
    }
}

@MainActor
@objc(BPConsoleToolHost)
public final class BPConsoleToolHost: NSObject {
    private let presentation: BPConsoleToolPresentation
    @objc public let viewController: NSViewController

    @objc public var isRunning: Bool {
        get { presentation.state.isRunning }
        set { presentation.state.isRunning = newValue }
    }

    @objc public var onRun: (() -> Void)? {
        get { presentation.onRun }
        set { presentation.onRun = newValue }
    }

    @objc public var onClear: (() -> Void)? {
        get { presentation.onClear }
        set { presentation.onClear = newValue }
    }

    @objc(initWithTextView:title:subtitle:runButtonTitle:clearButtonTitle:)
    public init(textView: NSTextView,
                title: String,
                subtitle: String?,
                runButtonTitle: String,
                clearButtonTitle: String) {
        let state = BPConsoleToolState(
            title: title,
            subtitle: subtitle,
            runButtonTitle: runButtonTitle,
            clearButtonTitle: clearButtonTitle,
            isRunning: false
        )
        let presentation = BPConsoleToolPresentation(textView: textView, state: state)
        self.presentation = presentation
        let host = NSHostingController(rootView: BPConsoleToolView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }
}

@MainActor
private struct BPConsoleToolView: View {
    @ObservedObject var presentation: BPConsoleToolPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.state.title)
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityValue(presentation.state.title)
                    if let subtitle = presentation.state.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityValue(subtitle)
                    }
                }

                Spacer()

                if presentation.state.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
                }

                Button(presentation.state.clearButtonTitle) {
                    presentation.onClear?()
                }
                .controlSize(.small)
                .keyboardShortcut("k", modifiers: .command)

                Button(presentation.state.runButtonTitle) {
                    presentation.onRun?()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(presentation.state.isRunning)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            BPTextViewContainerRepresentable(textView: presentation.textView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SwiftUI Services Tool Host

@MainActor
private final class BPServicesPresentation: ObservableObject {
    let tableScrollView: NSView
    let detailsScrollView: NSView
    @Published var startEnabled = false
    @Published var stopEnabled = false
    @Published var restartEnabled = false
    @Published var revealEnabled = false
    @Published var logsEnabled = false
    @Published var copyEnabled = false

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onRestart: (() -> Void)?
    var onRevealFile: (() -> Void)?
    var onOpenLogs: (() -> Void)?
    var onCopyOutput: (() -> Void)?

    init(tableScrollView: NSView, detailsScrollView: NSView) {
        self.tableScrollView = tableScrollView
        self.detailsScrollView = detailsScrollView
    }
}

@MainActor
@objc(BPServicesHost)
public final class BPServicesHost: NSObject {
    private let presentation: BPServicesPresentation
    @objc public let viewController: NSViewController

    @objc public var onStart: (() -> Void)? {
        get { presentation.onStart }
        set { presentation.onStart = newValue }
    }

    @objc public var onStop: (() -> Void)? {
        get { presentation.onStop }
        set { presentation.onStop = newValue }
    }

    @objc public var onRestart: (() -> Void)? {
        get { presentation.onRestart }
        set { presentation.onRestart = newValue }
    }

    @objc public var onRevealFile: (() -> Void)? {
        get { presentation.onRevealFile }
        set { presentation.onRevealFile = newValue }
    }

    @objc public var onOpenLogs: (() -> Void)? {
        get { presentation.onOpenLogs }
        set { presentation.onOpenLogs = newValue }
    }

    @objc public var onCopyOutput: (() -> Void)? {
        get { presentation.onCopyOutput }
        set { presentation.onCopyOutput = newValue }
    }

    @objc(initWithTableScrollView:detailsScrollView:)
    public init(tableScrollView: NSView, detailsScrollView: NSView) {
        let presentation = BPServicesPresentation(
            tableScrollView: tableScrollView,
            detailsScrollView: detailsScrollView
        )
        self.presentation = presentation
        let host = NSHostingController(rootView: BPServicesView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(updateWithStartEnabled:stopEnabled:restartEnabled:revealEnabled:logsEnabled:copyEnabled:)
    public func update(startEnabled: Bool,
                       stopEnabled: Bool,
                       restartEnabled: Bool,
                       revealEnabled: Bool,
                       logsEnabled: Bool,
                       copyEnabled: Bool) {
        presentation.startEnabled = startEnabled
        presentation.stopEnabled = stopEnabled
        presentation.restartEnabled = restartEnabled
        presentation.revealEnabled = revealEnabled
        presentation.logsEnabled = logsEnabled
        presentation.copyEnabled = copyEnabled
    }
}

@MainActor
private struct BPServicesView: View {
    @ObservedObject var presentation: BPServicesPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("Services_Title", comment: ""))
                .font(.system(size: 16, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(NSLocalizedString("Services_Title", comment: ""))

            BPNSViewContainerRepresentable(view: presentation.tableScrollView)
                .frame(minHeight: 90, maxHeight: .infinity)

            HStack(spacing: 8) {
                Button(NSLocalizedString("Services_Start", comment: "")) {
                    presentation.onStart?()
                }
                .disabled(!presentation.startEnabled)

                Button(NSLocalizedString("Services_Stop", comment: "")) {
                    presentation.onStop?()
                }
                .disabled(!presentation.stopEnabled)

                Button(NSLocalizedString("Services_Restart", comment: "")) {
                    presentation.onRestart?()
                }
                .disabled(!presentation.restartEnabled)

                Spacer()
            }

            BPNSViewContainerRepresentable(view: presentation.detailsScrollView)
                .frame(height: 115)

            HStack(spacing: 6) {
                Button(NSLocalizedString("Services_Reveal_File", comment: "")) {
                    presentation.onRevealFile?()
                }
                .disabled(!presentation.revealEnabled)
                .accessibilityIdentifier("services.revealFile")

                Button(NSLocalizedString("Services_Open_Logs", comment: "")) {
                    presentation.onOpenLogs?()
                }
                .disabled(!presentation.logsEnabled)
                .accessibilityIdentifier("services.openLogs")

                Button(NSLocalizedString("Services_Copy_Output", comment: "")) {
                    presentation.onCopyOutput?()
                }
                .disabled(!presentation.copyEnabled)
                .accessibilityIdentifier("services.copyOutput")

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - SwiftUI Autoremove Sheet Host

@MainActor
private final class BPAutoremovePresentation: ObservableObject {
    @Published var state = BPAutoremoveSheetState(
        statusText: NSLocalizedString("Checking unused dependencies…", comment: ""),
        warningText: NSLocalizedString("Only the reviewed formulae will be submitted for removal. Homebrew will recheck its dependency rules. Do not run other Homebrew operations until this finishes: external changes cannot be checked atomically.", comment: ""),
        removeButtonTitle: NSLocalizedString("Remove Reviewed Dependencies", comment: ""),
        cancelButtonTitle: NSLocalizedString("Cancel", comment: ""),
        removeEnabled: false,
        cancelEnabled: true,
        isBusy: true
    )
    let outputTextView: NSTextView
    var onRemove: (() -> Void)?
    var onCancelOrClose: (() -> Void)?

    init(outputTextView: NSTextView) {
        self.outputTextView = outputTextView
    }
}

@MainActor
@objc(BPAutoremoveHost)
public final class BPAutoremoveHost: NSObject {
    private let presentation: BPAutoremovePresentation
    @objc public let viewController: NSViewController

    @objc public var onRemove: (() -> Void)? {
        get { presentation.onRemove }
        set { presentation.onRemove = newValue }
    }

    @objc public var onCancelOrClose: (() -> Void)? {
        get { presentation.onCancelOrClose }
        set { presentation.onCancelOrClose = newValue }
    }

    @objc(initWithOutputTextView:)
    public init(outputTextView: NSTextView) {
        let presentation = BPAutoremovePresentation(outputTextView: outputTextView)
        self.presentation = presentation
        let host = NSHostingController(rootView: BPAutoremoveView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(updateWithStatusText:removeEnabled:cancelTitle:cancelEnabled:busy:)
    public func update(statusText: String,
                       removeEnabled: Bool,
                       cancelTitle: String,
                       cancelEnabled: Bool,
                       busy: Bool) {
        presentation.state.statusText = statusText
        presentation.state.removeEnabled = removeEnabled
        presentation.state.cancelButtonTitle = cancelTitle
        presentation.state.cancelEnabled = cancelEnabled
        presentation.state.isBusy = busy
    }
}

@MainActor
private struct BPAutoremoveView: View {
    @ObservedObject var presentation: BPAutoremovePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(presentation.state.statusText)
                .font(.system(size: 14, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityValue(presentation.state.statusText)
                .accessibilityIdentifier("autoremove.status")

            Text(presentation.state.warningText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityValue(presentation.state.warningText)

            BPTextViewContainerRepresentable(textView: presentation.outputTextView)
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)

            HStack(spacing: 12) {
                Button(presentation.state.cancelButtonTitle) {
                    presentation.onCancelOrClose?()
                }
                .disabled(!presentation.state.cancelEnabled)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("autoremove.cancel")

                Button(presentation.state.removeButtonTitle) {
                    presentation.onRemove?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!presentation.state.removeEnabled)
                .accessibilityIdentifier("autoremove.remove")

                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - SwiftUI Bundle (Brewfile Import / Export) Sheet Host

private func BPBundleWindowLocalizedTitle(_ key: String, fallback: String) -> String {
    Bundle.main.localizedString(forKey: key, value: fallback, table: "BPBundleWindow")
}

@MainActor
private final class BPBundleOperationPresentation: ObservableObject {
    @Published var state = BPBundleSheetState(
        mode: .importing,
        headerTitle: BPBundleWindowLocalizedTitle("UHp-GH-2qP.title", fallback: "Homebrew Bundle"),
        subtitleText: BPBundleWindowLocalizedTitle("UQX-gO-pze.title", fallback: "Importing File"),
        statusText: BPBundleWindowLocalizedTitle("NRz-0t-Pn6.title", fallback: "Please wait while the file is imported."),
        detailText: "",
        actionButtonTitle: NSLocalizedString("Cancel", comment: ""),
        actionEnabled: true,
        isRunning: true,
        hasFinished: false,
        succeeded: false
    )
    let importTextView: NSTextView
    var onAction: (() -> Void)?

    init(importTextView: NSTextView) {
        self.importTextView = importTextView
    }
}

@MainActor
@objc(BPBundleOperationHost)
public final class BPBundleOperationHost: NSObject {
    private let presentation: BPBundleOperationPresentation
    @objc public let viewController: NSViewController

    @objc public var onAction: (() -> Void)? {
        get { presentation.onAction }
        set { presentation.onAction = newValue }
    }

    @objc(initWithImportTextView:)
    public init(importTextView: NSTextView) {
        let presentation = BPBundleOperationPresentation(importTextView: importTextView)
        self.presentation = presentation
        let host = NSHostingController(rootView: BPBundleOperationView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(configureImportWithStatusText:actionTitle:actionEnabled:running:)
    public func configureImport(statusText: String?,
                                actionTitle: String,
                                actionEnabled: Bool,
                                running: Bool) {
        let resolvedStatus = (statusText?.isEmpty == false)
            ? statusText!
            : BPBundleWindowLocalizedTitle("NRz-0t-Pn6.title", fallback: "Please wait while the file is imported.")
        presentation.state = BPBundleSheetState(
            mode: .importing,
            headerTitle: BPBundleWindowLocalizedTitle("UHp-GH-2qP.title", fallback: "Homebrew Bundle"),
            subtitleText: BPBundleWindowLocalizedTitle("UQX-gO-pze.title", fallback: "Importing File"),
            statusText: resolvedStatus,
            detailText: "",
            actionButtonTitle: actionTitle,
            actionEnabled: actionEnabled,
            isRunning: running,
            hasFinished: !running,
            succeeded: !running
        )
    }

    @objc(configureExportWithStatusText:detailText:actionTitle:actionEnabled:running:finished:succeeded:)
    public func configureExport(statusText: String?,
                                detailText: String?,
                                actionTitle: String?,
                                actionEnabled: Bool,
                                running: Bool,
                                finished: Bool,
                                succeeded: Bool) {
        let resolvedStatus = (statusText?.isEmpty == false)
            ? statusText!
            : BPBundleWindowLocalizedTitle("lO8-qv-x07.title", fallback: "Export Successful")
        let resolvedDetail = (detailText?.isEmpty == false)
            ? detailText!
            : BPBundleWindowLocalizedTitle("Vid-Aa-KXl.title", fallback: "Please wait while the file is generated.")
        let resolvedAction = (actionTitle?.isEmpty == false)
            ? actionTitle!
            : BPBundleWindowLocalizedTitle("xSx-yq-DSQ.title", fallback: "Close")
        presentation.state = BPBundleSheetState(
            mode: .exporting,
            headerTitle: BPBundleWindowLocalizedTitle("UHp-GH-2qP.title", fallback: "Homebrew Bundle"),
            subtitleText: BPBundleWindowLocalizedTitle("Kyw-ca-xgs.title", fallback: "Exporting File"),
            statusText: resolvedStatus,
            detailText: resolvedDetail,
            actionButtonTitle: resolvedAction,
            actionEnabled: actionEnabled,
            isRunning: running,
            hasFinished: finished,
            succeeded: succeeded
        )
    }
}

@MainActor
private struct BPBundleOperationView: View {
    @ObservedObject var presentation: BPBundleOperationPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(presentation.state.headerTitle)
                .font(.system(size: 16, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(presentation.state.headerTitle)

            if presentation.state.mode == .importing {
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.state.subtitleText)
                        .font(.body)
                        .accessibilityValue(presentation.state.subtitleText)

                    Text(presentation.state.statusText)
                        .font(.smallCaps(.caption)())
                        .foregroundStyle(.secondary)
                        .accessibilityValue(presentation.state.statusText)
                        .accessibilityIdentifier("brewfile.import.status")

                    BPTextViewContainerRepresentable(textView: presentation.importTextView)
                        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.state.subtitleText)
                        .font(.body)
                        .accessibilityValue(presentation.state.subtitleText)

                    if !presentation.state.hasFinished || !presentation.state.succeeded {
                        Text(presentation.state.detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityValue(presentation.state.detailText)
                            .accessibilityIdentifier("brewfile.export.detail")
                    }

                    Spacer(minLength: 8)

                    if presentation.state.hasFinished {
                        VStack(spacing: 8) {
                            Image(systemName: presentation.state.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(presentation.state.succeeded ? .green : .red)
                            Text(presentation.state.statusText)
                                .font(.headline)
                                .accessibilityValue(presentation.state.statusText)
                                .accessibilityIdentifier("brewfile.export.status")
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
            }

            HStack {
                if presentation.state.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
                        .accessibilityIdentifier(presentation.state.mode == .exporting ? "brewfile.export.progress" : "brewfile.import.progress")
                }

                Spacer()

                Button(presentation.state.actionButtonTitle) {
                    presentation.onAction?()
                }
                .disabled(!presentation.state.actionEnabled)
                .accessibilityIdentifier(presentation.state.mode == .importing ? "brewfile.import.action" : "brewfile.export.close")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - SwiftUI Formula Options Sheet Host

private func BPFormulaOptionsLocalizedTitle(_ key: String, fallback: String) -> String {
    Bundle.main.localizedString(forKey: key, value: fallback, table: "BPFormulaOptionsWindow")
}

@MainActor
private final class BPFormulaOptionsPresentation: ObservableObject {
    @Published var state = BPFormulaOptionsSheetState()
    var onOptionToggled: ((String, Bool) -> Void)?
    var onCancel: (() -> Void)?
    var onInstall: (() -> Void)?
}

@MainActor
@objc(BPFormulaOptionsHost)
public final class BPFormulaOptionsHost: NSObject {
    private let presentation = BPFormulaOptionsPresentation()
    @objc public let viewController: NSViewController

    @objc public var selectedOptionNames: [String] {
        presentation.state.selectedOptionNames
    }

    @objc public var onOptionToggled: ((String, Bool) -> Void)? {
        get { presentation.onOptionToggled }
        set { presentation.onOptionToggled = newValue }
    }

    @objc public var onCancel: (() -> Void)? {
        get { presentation.onCancel }
        set { presentation.onCancel = newValue }
    }

    @objc public var onInstall: (() -> Void)? {
        get { presentation.onInstall }
        set { presentation.onInstall = newValue }
    }

    public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPFormulaOptionsView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(configureWithFormulaName:optionNames:optionExplanations:)
    public func configure(formulaName: String,
                          optionNames: [String],
                          optionExplanations: [String]) {
        var rows: [BPFormulaOptionRow] = []
        rows.reserveCapacity(optionNames.count)
        for index in 0..<optionNames.count {
            let explanation = index < optionExplanations.count ? optionExplanations[index] : ""
            rows.append(BPFormulaOptionRow(name: optionNames[index], explanation: explanation, isApplied: false))
        }
        let helpText = rows.isEmpty
            ? NSLocalizedString("Formula_Options_NoOptions", comment: "")
            : NSLocalizedString("Formula_Options_ClickForDetails", comment: "")
        presentation.state = BPFormulaOptionsSheetState(
            formulaName: formulaName,
            headerTitle: BPFormulaOptionsLocalizedTitle("idS-tT-jie.title", fallback: "Picking Options for Formula:"),
            helpText: helpText,
            optionsColumnTitle: BPFormulaOptionsLocalizedTitle("XqV-53-e7D.headerCell.title", fallback: "Options"),
            descriptionPlaceholder: BPFormulaOptionsLocalizedTitle("G5n-5T-DoK.placeholderString", fallback: "Description for selected option."),
            cancelTitle: BPFormulaOptionsLocalizedTitle("dCD-PS-P4J.title", fallback: "Cancel"),
            installTitle: BPFormulaOptionsLocalizedTitle("hgj-Zo-s73.title", fallback: "Install"),
            options: rows,
            selectedOptionID: rows.first?.id
        )
    }

    @objc(setApplied:forOptionNamed:)
    public func setApplied(_ applied: Bool, forOptionNamed name: String) {
        presentation.state.setApplied(applied, forOptionID: name)
        presentation.onOptionToggled?(name, applied)
    }
}

@MainActor
private struct BPFormulaOptionsView: View {
    @ObservedObject var presentation: BPFormulaOptionsPresentation

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { presentation.state.selectedOptionID },
            set: { presentation.state.selectedOptionID = $0 }
        )
    }

    private func toggleBinding(for row: BPFormulaOptionRow) -> Binding<Bool> {
        Binding(
            get: { row.isApplied },
            set: { newValue in
                presentation.state.setApplied(newValue, forOptionID: row.id)
                presentation.onOptionToggled?(row.name, newValue)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(presentation.state.headerTitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .accessibilityValue(presentation.state.headerTitle)
                Text(presentation.state.formulaName)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityValue(presentation.state.formulaName)
                    .accessibilityIdentifier("formula.options.formulaName")
            }

            List(presentation.state.options, selection: selectionBinding) { row in
                HStack(spacing: 8) {
                    Toggle("", isOn: toggleBinding(for: row))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("formula.options.toggle.\(row.name)")
                    Text(row.name)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            presentation.state.selectedOptionID = row.id
                        }
                        .help(row.explanation)
                        .accessibilityLabel(row.explanation.isEmpty ? row.name : row.explanation)
                        .accessibilityValue(row.name)
                }
                .tag(Optional(row.id))
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 130, maxHeight: .infinity)
            .accessibilityLabel(NSLocalizedString("Formula_Options_VoiceOver", comment: ""))

            ScrollView {
                Text(presentation.state.selectedOptionDescription)
                    .font(.callout)
                    .foregroundStyle(presentation.state.selectedOptionID == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityLabel(NSLocalizedString("Formula_Options_VoiceOver_Description", comment: ""))
                    .accessibilityValue(presentation.state.selectedOptionDescription)
            }
            .padding(8)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            HStack {
                Button(presentation.state.cancelTitle) {
                    presentation.onCancel?()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("formula.options.cancel")

                Spacer()

                Text(presentation.state.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityValue(presentation.state.helpText)

                Spacer()

                Button(presentation.state.installTitle) {
                    presentation.onInstall?()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("formula.options.install")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - SwiftUI Installation / Operation Progress Sheet Host

private func BPInstallationLocalizedTitle(_ key: String, fallback: String) -> String {
    Bundle.main.localizedString(forKey: key, value: fallback, table: "BPInstallationWindow")
}

@MainActor
private final class BPInstallationPresentation: ObservableObject {
    @Published var state = BPInstallationSheetState(
        windowTitle: "",
        formulaNamesText: "",
        okTitle: BPInstallationLocalizedTitle("atZ-M7-fU1.title", fallback: "OK"),
        cancelTitle: NSLocalizedString("Cancel", comment: ""),
        isRunning: true,
        okEnabled: false,
        cancelEnabled: true
    )
    let recordTextView: NSTextView
    var onCancel: (() -> Void)?
    var onOK: (() -> Void)?

    init(recordTextView: NSTextView) {
        self.recordTextView = recordTextView
    }
}

@MainActor
@objc(BPInstallationHost)
public final class BPInstallationHost: NSObject {
    private let presentation: BPInstallationPresentation
    @objc public let viewController: NSViewController

    @objc public var onCancel: (() -> Void)? {
        get { presentation.onCancel }
        set { presentation.onCancel = newValue }
    }

    @objc public var onOK: (() -> Void)? {
        get { presentation.onOK }
        set { presentation.onOK = newValue }
    }

    @objc(initWithRecordTextView:)
    public init(recordTextView: NSTextView) {
        let presentation = BPInstallationPresentation(recordTextView: recordTextView)
        self.presentation = presentation
        let host = NSHostingController(rootView: BPInstallationView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(updateWithWindowTitle:formulaNames:running:okEnabled:cancelEnabled:)
    public func update(windowTitle: String,
                       formulaNames: String,
                       running: Bool,
                       okEnabled: Bool,
                       cancelEnabled: Bool) {
        presentation.state = BPInstallationSheetState(
            windowTitle: windowTitle,
            formulaNamesText: formulaNames,
            okTitle: BPInstallationLocalizedTitle("atZ-M7-fU1.title", fallback: "OK"),
            cancelTitle: NSLocalizedString("Cancel", comment: ""),
            isRunning: running,
            okEnabled: okEnabled,
            cancelEnabled: cancelEnabled
        )
    }
}

@MainActor
private struct BPInstallationView: View {
    @ObservedObject var presentation: BPInstallationPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(presentation.state.windowTitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .accessibilityValue(presentation.state.windowTitle)
                    .accessibilityIdentifier("installation.title")

                if !presentation.state.formulaNamesText.isEmpty {
                    Text(presentation.state.formulaNamesText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .accessibilityValue(presentation.state.formulaNamesText)
                        .accessibilityIdentifier("installation.target")
                }
            }

            BPTextViewContainerRepresentable(textView: presentation.recordTextView)
                .frame(maxWidth: .infinity, minHeight: 164, maxHeight: .infinity)

            HStack(spacing: 10) {
                if presentation.state.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
                }

                Spacer()

                Button(presentation.state.cancelTitle) {
                    presentation.onCancel?()
                }
                .disabled(!presentation.state.cancelEnabled)
                .accessibilityIdentifier("installation.cancel")

                Button(presentation.state.okTitle) {
                    presentation.onOK?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!presentation.state.okEnabled)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("installation.ok")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - SwiftUI Tahoe About Window Host

private func BPLocalizedWithFallback(_ key: String, fallback: String) -> String {
    let resolved = Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
    return (resolved.isEmpty || resolved == key) ? fallback : resolved
}

@MainActor
private final class BPAboutWindowPresentation: ObservableObject {
    @Published var state = BPAboutWindowState()
    let creditsTextView: NSTextView
    var onVisitWebsite: (() -> Void)?
    var onSelectTab: ((Int) -> Void)?

    init(creditsTextView: NSTextView) {
        self.creditsTextView = creditsTextView
    }
}

@MainActor
@objc(BPAboutWindowHost)
public final class BPAboutWindowHost: NSObject {
    private let presentation: BPAboutWindowPresentation
    @objc public let viewController: NSViewController

    @objc public var selectedTabIndex: Int {
        presentation.state.selectedTab.rawValue
    }

    @objc public var versionClipboardSummary: String {
        presentation.state.versionClipboardSummary
    }

    @objc public var onVisitWebsite: (() -> Void)? {
        get { presentation.onVisitWebsite }
        set { presentation.onVisitWebsite = newValue }
    }

    @objc public var onSelectTab: ((Int) -> Void)? {
        get { presentation.onSelectTab }
        set { presentation.onSelectTab = newValue }
    }

    @objc(initWithCreditsTextView:)
    public init(creditsTextView: NSTextView) {
        let presentation = BPAboutWindowPresentation(creditsTextView: creditsTextView)
        self.presentation = presentation
        let host = NSHostingController(rootView: BPAboutWindowView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(configureWithAppName:appVersion:appCopyright:hasAcknowledgements:)
    public func configure(appName: String,
                          appVersion: String,
                          appCopyright: String,
                          hasAcknowledgements: Bool) {
        presentation.state = BPAboutWindowState(
            appName: appName.isEmpty ? "Cakebrew" : appName,
            appVersion: appVersion,
            appCopyright: appCopyright,
            selectedTab: presentation.state.selectedTab,
            hasAcknowledgements: hasAcknowledgements
        )
    }

    @objc(selectTabAtIndex:)
    public func selectTab(at index: Int) {
        let tab = BPAboutWindowTab(rawValue: index) ?? .credits
        presentation.state.selectedTab = tab
        presentation.onSelectTab?(tab.rawValue)
    }

    @objc
    @discardableResult
    public func copyVersionInfoToPasteboard() -> String {
        let summary = presentation.state.versionClipboardSummary
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        return summary
    }
}

@MainActor
private struct BPAboutWindowView: View {
    @ObservedObject var presentation: BPAboutWindowPresentation

    private var selectedTabBinding: Binding<BPAboutWindowTab> {
        Binding(
            get: { presentation.state.selectedTab },
            set: { newTab in
                presentation.state.selectedTab = newTab
                presentation.onSelectTab?(newTab.rawValue)
            }
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(presentation.state.appName)
                            .font(.system(size: 22, weight: .bold))
                            .accessibilityIdentifier("about.appName")

                        if !presentation.state.appVersion.isEmpty {
                            Text(presentation.state.appVersion)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.14))
                                )
                                .accessibilityIdentifier("about.appVersion")
                        }
                    }

                    if !presentation.state.appCopyright.isEmpty {
                        Text(presentation.state.appCopyright)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .accessibilityIdentifier("about.appCopyright")
                    }
                }

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            )

            if presentation.state.hasAcknowledgements {
                Picker("", selection: selectedTabBinding) {
                    Text(BPLocalizedWithFallback("About_Credits", fallback: "Credits"))
                        .tag(BPAboutWindowTab.credits)
                    Text(BPLocalizedWithFallback("About_Acknowledgements", fallback: "Acknowledgements"))
                        .tag(BPAboutWindowTab.acknowledgements)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("about.tabPicker")
            }

            BPTextViewContainerRepresentable(textView: presentation.creditsTextView)
                .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(presentation.state.versionClipboardSummary, forType: .string)
                } label: {
                    Label(BPLocalizedWithFallback("About_Copy_Version", fallback: "Copy Version Info"), systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .accessibilityIdentifier("about.copyVersion")

                Spacer()

                Button {
                    presentation.onVisitWebsite?()
                } label: {
                    Label(BPLocalizedWithFallback("About_Visit_Website", fallback: "Visit Website"), systemImage: "safari")
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("about.visitWebsite")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - SwiftUI Brewfile Review Accessory Host

@MainActor
private final class BPBrewfileReviewPresentation: ObservableObject {
    @Published var state: BPBrewfileReviewState
    let entriesTextView: NSTextView

    init(entriesTextView: NSTextView, state: BPBrewfileReviewState) {
        self.entriesTextView = entriesTextView
        self.state = state
    }
}

@MainActor
@objc(BPBrewfileReviewHost)
public final class BPBrewfileReviewHost: NSObject {
    private let presentation: BPBrewfileReviewPresentation
    @objc public let viewController: NSViewController

    @objc public var totalEntryCount: Int {
        presentation.state.totalEntryCount
    }

    @objc public var installedCount: Int {
        presentation.state.installedCount
    }

    @objc public var missingCount: Int {
        presentation.state.missingCount
    }

    @objc public var notCheckedCount: Int {
        presentation.state.notCheckedCount
    }

    @objc public var canInstall: Bool {
        presentation.state.canInstall
    }

    @objc(initWithEntriesTextView:fileName:installedCount:missingCount:notCheckedCount:formulaCount:caskCount:tapCount:otherCount:canInstall:summaryText:)
    public init(entriesTextView: NSTextView,
                fileName: String,
                installedCount: Int,
                missingCount: Int,
                notCheckedCount: Int,
                formulaCount: Int,
                caskCount: Int,
                tapCount: Int,
                otherCount: Int,
                canInstall: Bool,
                summaryText: String) {
        let state = BPBrewfileReviewState(
            fileName: fileName,
            installedCount: installedCount,
            missingCount: missingCount,
            notCheckedCount: notCheckedCount,
            formulaCount: formulaCount,
            caskCount: caskCount,
            tapCount: tapCount,
            otherCount: otherCount,
            canInstall: canInstall,
            summaryText: summaryText
        )
        let presentation = BPBrewfileReviewPresentation(entriesTextView: entriesTextView, state: state)
        self.presentation = presentation
        let host = NSHostingController(rootView: BPBrewfileReviewView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }
}

@MainActor
private struct BPBrewfileReviewView: View {
    @ObservedObject var presentation: BPBrewfileReviewPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(presentation.state.fileName, systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier("brewfile.review.fileName")

                Spacer()

                statusPill(
                    count: presentation.state.installedCount,
                    label: BPLocalizedWithFallback("Installed", fallback: "Installed"),
                    color: .green
                )
                statusPill(
                    count: presentation.state.missingCount,
                    label: BPLocalizedWithFallback("Missing", fallback: "Missing"),
                    color: .orange
                )
                if presentation.state.notCheckedCount > 0 {
                    statusPill(
                        count: presentation.state.notCheckedCount,
                        label: BPLocalizedWithFallback("Not checked", fallback: "Not checked"),
                        color: .secondary
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            BPTextViewContainerRepresentable(textView: presentation.entriesTextView)
                .frame(maxWidth: .infinity, minHeight: 210, maxHeight: .infinity)
        }
        .frame(width: 570, height: 280)
    }

    @ViewBuilder
    private func statusPill(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

// MARK: - SwiftUI Command Palette Host (⌘K)

@MainActor
private final class BPCommandPalettePresentation: ObservableObject {
    @Published var state = BPCommandPaletteState()
    var onNavigateToSidebarRow: ((Int) -> Void)?
    var onPerformAction: ((String) -> Void)?
    var onSelectPackage: ((String, Bool) -> Void)?
    var onDismiss: (() -> Void)?

    @discardableResult
    func execute(_ item: BPCommandPaletteItem) -> Bool {
        switch item.kind {
        case .navigation:
            guard item.sidebarRow >= 0 else { return false }
            onNavigateToSidebarRow?(item.sidebarRow)
            onDismiss?()
            return true
        case .action:
            guard let actionID = item.actionIdentifier, !actionID.isEmpty else { return false }
            onPerformAction?(actionID)
            onDismiss?()
            return true
        case .package:
            guard let name = item.packageName, !name.isEmpty else { return false }
            onSelectPackage?(name, item.isCask)
            onDismiss?()
            return true
        }
    }
}

@MainActor
@objc(BPCommandPaletteHost)
public final class BPCommandPaletteHost: NSObject {
    private let presentation = BPCommandPalettePresentation()
    @objc public let viewController: NSViewController

    @objc public var query: String {
        get { presentation.state.query }
        set { presentation.state.query = newValue }
    }

    @objc public var filteredCount: Int {
        presentation.state.filteredItems.count
    }

    @objc public var selectedItemID: String? {
        presentation.state.selectedItem?.id
    }

    @objc public var onNavigateToSidebarRow: ((Int) -> Void)? {
        get { presentation.onNavigateToSidebarRow }
        set { presentation.onNavigateToSidebarRow = newValue }
    }

    @objc public var onPerformAction: ((String) -> Void)? {
        get { presentation.onPerformAction }
        set { presentation.onPerformAction = newValue }
    }

    @objc public var onSelectPackage: ((String, Bool) -> Void)? {
        get { presentation.onSelectPackage }
        set { presentation.onSelectPackage = newValue }
    }

    @objc public var onDismiss: (() -> Void)? {
        get { presentation.onDismiss }
        set { presentation.onDismiss = newValue }
    }

    public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPCommandPaletteView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc
    public func removeAllItems() {
        presentation.state.items = []
        presentation.state.query = ""
    }

    @objc(addNavigationItemWithID:title:subtitle:symbolName:sidebarRow:)
    public func addNavigationItem(id: String,
                                  title: String,
                                  subtitle: String,
                                  symbolName: String,
                                  sidebarRow: Int) {
        let item = BPCommandPaletteItem(
            id: id,
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            shortcutHint: nil,
            kind: .navigation,
            sidebarRow: sidebarRow
        )
        presentation.state.items.append(item)
    }

    @objc(addActionItemWithID:title:subtitle:symbolName:shortcutHint:)
    public func addActionItem(id: String,
                              title: String,
                              subtitle: String,
                              symbolName: String,
                              shortcutHint: String?) {
        let item = BPCommandPaletteItem(
            id: id,
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            shortcutHint: shortcutHint,
            kind: .action,
            actionIdentifier: id
        )
        presentation.state.items.append(item)
    }

    @objc(addPackageItemWithName:version:cask:)
    public func addPackageItem(name: String, version: String, cask: Bool) {
        guard !name.isEmpty else { return }
        let kindLabel = cask
            ? BPLocalizedWithFallback("Casks", fallback: "Casks")
            : BPLocalizedWithFallback("Formulae", fallback: "Formulae")
        let subtitle = version.isEmpty ? kindLabel : "\(kindLabel) • \(version)"
        let item = BPCommandPaletteItem(
            id: "pkg:\(cask ? "cask" : "formula"):\(name)",
            title: name,
            subtitle: subtitle,
            symbolName: cask ? "macwindow" : "shippingbox",
            shortcutHint: nil,
            kind: .package,
            packageName: name,
            isCask: cask
        )
        presentation.state.items.append(item)
    }

    @objc
    public func moveSelectionDown() {
        presentation.state.moveSelection(delta: 1)
    }

    @objc
    public func moveSelectionUp() {
        presentation.state.moveSelection(delta: -1)
    }

    @objc
    @discardableResult
    public func executeSelectedItem() -> Bool {
        guard let item = presentation.state.selectedItem else { return false }
        return presentation.execute(item)
    }

    @objc(executeItemWithID:)
    @discardableResult
    public func executeItem(withID id: String) -> Bool {
        guard let item = presentation.state.items.first(where: { $0.id == id }) else { return false }
        return presentation.execute(item)
    }
}

@MainActor
private struct BPCommandPaletteView: View {
    @ObservedObject var presentation: BPCommandPalettePresentation

    private var queryBinding: Binding<String> {
        Binding(
            get: { presentation.state.query },
            set: { presentation.state.query = $0 }
        )
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { presentation.state.selectedItemID },
            set: { presentation.state.selectedItemID = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    BPLocalizedWithFallback("Command_Palette_Placeholder", fallback: "Jump to a view, run a tool, or inspect a package…"),
                    text: queryBinding
                )
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .onSubmit {
                    _ = presentation.state.selectedItem.map { presentation.execute($0) }
                }
                .accessibilityIdentifier("commandPalette.searchField")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            List(presentation.state.filteredItems, selection: selectionBinding) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let shortcut = item.shortcutHint, !shortcut.isEmpty {
                        Text(shortcut)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    _ = presentation.execute(item)
                }
                .onTapGesture {
                    presentation.state.selectedItemID = item.id
                }
                .tag(Optional(item.id))
            }
            .listStyle(.inset)
            .frame(minHeight: 240, maxHeight: .infinity)
            .accessibilityIdentifier("commandPalette.list")

            HStack {
                Button(BPLocalizedWithFallback("Cancel", fallback: "Cancel")) {
                    presentation.onDismiss?()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("commandPalette.cancel")

                Spacer()

                Button(BPLocalizedWithFallback("Generic_OK", fallback: "OK")) {
                    _ = presentation.state.selectedItem.map { presentation.execute($0) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(presentation.state.selectedItem == nil)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("commandPalette.run")
            }
        }
        .padding(16)
        .frame(width: 520, height: 380)
    }
}

// MARK: - SwiftUI Tahoe Status Bar Host

@MainActor
private final class BPStatusBarPresentation: ObservableObject {
    @Published var state = BPStatusBarState()
    var onOpenCommandPalette: (() -> Void)?
    var onOpenUnifiedUpdates: (() -> Void)?
}

@MainActor
@objc(BPStatusBarHost)
public final class BPStatusBarHost: NSObject {
    private let presentation = BPStatusBarPresentation()
    @objc public let viewController: NSViewController

    @objc public var onOpenCommandPalette: (() -> Void)? {
        get { presentation.onOpenCommandPalette }
        set { presentation.onOpenCommandPalette = newValue }
    }

    @objc public var onOpenUnifiedUpdates: (() -> Void)? {
        get { presentation.onOpenUnifiedUpdates }
        set { presentation.onOpenUnifiedUpdates = newValue }
    }

    @objc public var message: String {
        get { presentation.state.message }
        set { presentation.state.message = newValue }
    }

    @objc public var isBusy: Bool {
        get { presentation.state.isBusy }
        set { presentation.state.isBusy = newValue }
    }

    @objc public var installedCount: Int {
        get { presentation.state.installedCount }
        set { presentation.state.installedCount = newValue }
    }

    @objc public var outdatedCount: Int {
        get { presentation.state.outdatedCount }
        set { presentation.state.outdatedCount = newValue }
    }

    @objc public var pinnedCount: Int {
        get { presentation.state.pinnedCount }
        set { presentation.state.pinnedCount = newValue }
    }

    @objc public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPStatusBarView(presentation: presentation))
        host.sizingOptions = []
        viewController = host
        super.init()
    }

    @objc(updateWithMessage:isBusy:installedCount:outdatedCount:pinnedCount:)
    public func update(message: String,
                       isBusy: Bool,
                       installedCount: Int,
                       outdatedCount: Int,
                       pinnedCount: Int) {
        presentation.state = BPStatusBarState(
            message: message,
            isBusy: isBusy,
            installedCount: installedCount,
            outdatedCount: outdatedCount,
            pinnedCount: pinnedCount
        )
    }

    @objc public func triggerCommandPalette() {
        presentation.onOpenCommandPalette?()
    }

    @objc public func triggerUnifiedUpdates() {
        presentation.onOpenUnifiedUpdates?()
    }
}

@MainActor
private struct BPStatusBarView: View {
    @ObservedObject var presentation: BPStatusBarPresentation

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.6)

            HStack(spacing: 10) {
                if presentation.state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                        .frame(width: 14, height: 14)
                        .accessibilityIdentifier("statusBar.activity")
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(presentation.state.message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("statusBar.message")

                Spacer(minLength: 8)

                if presentation.state.installedCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(presentation.state.installedCount)")
                            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .accessibilityIdentifier("statusBar.installedCount")
                }

                if presentation.state.outdatedCount > 0 {
                    Button {
                        presentation.onOpenUnifiedUpdates?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("\(presentation.state.outdatedCount)")
                                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        }
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.14))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("statusBar.outdatedButton")
                }

                Button {
                    presentation.onOpenCommandPalette?()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "command")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("K")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .help(BPLocalizedWithFallback("Command_Palette_Title", fallback: "Command Palette"))
                .accessibilityIdentifier("statusBar.commandPaletteButton")
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - SwiftUI Tahoe Sidebar Host & Operation Accessory Cards

@MainActor
private final class BPSidebarPresentation: ObservableObject {
    @Published var state = BPSidebarState()
    var onSelectRow: ((Int) -> Void)?
}

@MainActor
@objc(BPSidebarHost)
public final class BPSidebarHost: NSObject {
    private let presentation = BPSidebarPresentation()
    @objc public let viewController: NSViewController

    @objc public var onSelectRow: ((Int) -> Void)? {
        get { presentation.onSelectRow }
        set { presentation.onSelectRow = newValue }
    }

    @objc public var selectedRowIndex: Int {
        get { presentation.state.selectedRowIndex }
        set { presentation.state.selectedRowIndex = newValue }
    }

    @objc public var sectionCount: Int {
        presentation.state.sections.count
    }

    @objc public var selectableRowCount: Int {
        presentation.state.allRows.count
    }

    @objc public override init() {
        let presentation = self.presentation
        let host = NSHostingController(rootView: BPSidebarView(presentation: presentation))
        host.sizingOptions = []
        viewController = host
        super.init()
    }

    @objc public func removeAllSections() {
        presentation.state.sections.removeAll()
    }

    @objc(addSectionWithRowIndex:title:)
    public func addSection(rowIndex: Int, title: String) {
        presentation.state.sections.append(BPSidebarSectionState(rowIndex: rowIndex, title: title))
    }

    @objc(addRowToSectionAtRowIndex:rowIndex:title:groupTitle:symbolName:badgeCount:accessibilityIdentifier:accessibilityLabel:)
    public func addRow(toSectionAtRowIndex sectionRowIndex: Int,
                       rowIndex: Int,
                       title: String,
                       groupTitle: String,
                       symbolName: String,
                       badgeCount: Int,
                       accessibilityIdentifier: String,
                       accessibilityLabel: String) {
        guard let sectionIdx = presentation.state.sections.firstIndex(where: { $0.rowIndex == sectionRowIndex }) else {
            return
        }
        let row = BPSidebarRowState(
            rowIndex: rowIndex,
            title: title,
            groupTitle: groupTitle,
            symbolName: symbolName,
            badgeCount: badgeCount,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel
        )
        presentation.state.sections[sectionIdx].rows.append(row)
    }

    @objc(badgeCountForRowIndex:)
    public func badgeCount(forRowIndex rowIndex: Int) -> Int {
        presentation.state.badgeCount(forRowIndex: rowIndex)
    }

    @objc(selectRowAtIndex:)
    public func selectRow(atIndex rowIndex: Int) {
        presentation.state.selectedRowIndex = rowIndex
        presentation.onSelectRow?(rowIndex)
    }
}

@MainActor
private struct BPSidebarView: View {
    @ObservedObject var presentation: BPSidebarPresentation

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(presentation.state.sections) { section in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 2)

                        ForEach(section.rows) { row in
                            let isSelected = presentation.state.selectedRowIndex == row.rowIndex
                            Button {
                                presentation.state.selectedRowIndex = row.rowIndex
                                presentation.onSelectRow?(row.rowIndex)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: row.symbolName.isEmpty ? "folder" : row.symbolName)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                                        .frame(width: 16)

                                    Text(row.title)
                                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                                        .lineLimit(1)
                                        .accessibilityIdentifier(row.accessibilityIdentifier)
                                        .accessibilityLabel(row.accessibilityLabel.isEmpty ? row.title : row.accessibilityLabel)

                                    Spacer(minLength: 4)

                                    if row.badgeCount >= 0 {
                                        Text("\(row.badgeCount)")
                                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 1.5)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(isSelected ? Color.white.opacity(0.92) : Color.secondary.opacity(0.14))
                                            )
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isSelected ? Color.accentColor : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(8)
        }
        .accessibilityLabel(NSLocalizedString("Sidebar_VoiceOver_Sidebar", comment: ""))
    }
}

private struct BPAppKitTextFieldWrapper: NSViewRepresentable {
    let textField: NSTextField

    func makeNSView(context: Context) -> NSTextField {
        textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}
}

@MainActor
private final class BPTapInputPresentation: ObservableObject {
    @Published var state = BPTapInputState()
}

@MainActor
@objc(BPTapInputHost)
public final class BPTapInputHost: NSObject, NSTextFieldDelegate {
    private let presentation = BPTapInputPresentation()
    @objc public let inputField: NSTextField
    @objc public let viewController: NSViewController

    @objc public var repositoryName: String {
        get { presentation.state.repositoryName }
        set {
            inputField.stringValue = newValue
            presentation.state.repositoryName = newValue
        }
    }

    @objc public var isValidFormat: Bool {
        presentation.state.isValidFormat
    }

    @objc public override init() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "user/repo"
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.bezelStyle = .roundedBezel
        inputField = field

        let presentation = self.presentation
        let host = NSHostingController(
            rootView: BPTapInputCardView(presentation: presentation, inputField: field)
        )
        host.sizingOptions = []
        host.view.frame = NSRect(x: 0, y: 0, width: 320, height: 68)
        viewController = host
        super.init()
        field.delegate = self
    }

    public func controlTextDidChange(_ obj: Notification) {
        presentation.state.repositoryName = inputField.stringValue
    }
}

@MainActor
private struct BPTapInputCardView: View {
    @ObservedObject var presentation: BPTapInputPresentation
    let inputField: NSTextField

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BPAppKitTextFieldWrapper(textField: inputField)
                .frame(height: 24)

            HStack(spacing: 5) {
                if presentation.state.trimmedName.isEmpty {
                    Image(systemName: "building.columns")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("user/repo (e.g. homebrew/cask-fonts)")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if presentation.state.isValidFormat {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(presentation.state.trimmedName)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(NSLocalizedString("Message_Tap_Invalid_Title", comment: ""))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
            .accessibilityIdentifier("tap.input.validation")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 320, height: 68, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

@MainActor
private final class BPCleanupPreviewPresentation: ObservableObject {
    @Published var state: BPCleanupPreviewState

    init(state: BPCleanupPreviewState) {
        self.state = state
    }
}

@MainActor
@objc(BPCleanupPreviewHost)
public final class BPCleanupPreviewHost: NSObject {
    private let presentation: BPCleanupPreviewPresentation
    @objc public let viewController: NSViewController

    @objc public var itemCount: Int {
        presentation.state.itemCount
    }

    @objc public var reclaimableBytes: UInt64 {
        presentation.state.reclaimableBytes
    }

    @objc public var formattedByteCount: String {
        presentation.state.formattedByteCount
    }

    @objc(initWithItemCount:reclaimableBytes:formattedByteCount:samplePaths:)
    public init(itemCount: Int,
                reclaimableBytes: UInt64,
                formattedByteCount: String,
                samplePaths: [String]) {
        let state = BPCleanupPreviewState(
            itemCount: itemCount,
            reclaimableBytes: reclaimableBytes,
            formattedByteCount: formattedByteCount,
            samplePaths: samplePaths
        )
        let presentation = BPCleanupPreviewPresentation(state: state)
        self.presentation = presentation
        let host = NSHostingController(rootView: BPCleanupPreviewCardView(presentation: presentation))
        host.sizingOptions = []
        host.view.frame = NSRect(x: 0, y: 0, width: 340, height: 84)
        viewController = host
        super.init()
    }
}

@MainActor
private struct BPCleanupPreviewCardView: View {
    @ObservedObject var presentation: BPCleanupPreviewPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(
                    presentation.state.itemCount == 1
                        ? BPLocalizedWithFallback("Cleanup_Item_Count_One", fallback: "1 item")
                        : String(
                            format: BPLocalizedWithFallback("Cleanup_Item_Count_Other", fallback: "%lu items"),
                            UInt(max(0, presentation.state.itemCount))
                        )
                )
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .accessibilityIdentifier("cleanup.preview.itemCount")

                Spacer()

                if !presentation.state.formattedByteCount.isEmpty {
                    Text(presentation.state.formattedByteCount)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        )
                        .accessibilityIdentifier("cleanup.preview.byteCount")
                }
            }

            if let firstPath = presentation.state.samplePaths.first {
                Text((firstPath as NSString).lastPathComponent)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("cleanup.preview.samplePath")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 340, height: 84, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
