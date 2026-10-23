import AppKit
import ObjectiveC
import SwiftUI
import UserNotifications

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
private struct BPLogFilterBarView: View {
    @Binding var filterQuery: String
    let matchingLineCount: Int
    let totalLineCount: Int
    let filterFieldIdentifier: String
    let lineCountIdentifier: String
    let copyButtonIdentifier: String
    let copyEnabled: Bool
    let onCopyOutput: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(NSLocalizedString("Toolbar_Search", comment: ""), text: $filterQuery)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .accessibilityIdentifier(filterFieldIdentifier)
                if !filterQuery.isEmpty {
                    Button {
                        filterQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: 210)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            if totalLineCount > 0 {
                let countText = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "\(totalLineCount)"
                    : "\(matchingLineCount)/\(totalLineCount)"
                Text(countText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .accessibilityValue(countText)
                    .accessibilityIdentifier(lineCountIdentifier)
            }

            Spacer()

            Button {
                onCopyOutput()
            } label: {
                Label(NSLocalizedString("Services_Copy_Output", comment: ""), systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            .disabled(!copyEnabled)
            .accessibilityIdentifier(copyButtonIdentifier)
        }
    }
}

@MainActor
private struct BPFilteredLogOverlayView: View {
    let filteredText: String
    let accessibilityID: String

    var body: some View {
        ScrollView {
            Text(filteredText.isEmpty ? NSLocalizedString("Empty_Search_Title", comment: "") : filteredText)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(filteredText.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(10)
                .accessibilityValue(filteredText)
                .accessibilityIdentifier(accessibilityID)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

@MainActor
private final class BPConsoleToolPresentation: ObservableObject {
    @Published var state: BPConsoleToolState
    let textView: NSTextView
    var onRun: (() -> Void)?
    var onClear: (() -> Void)?
    var onCopyOutput: (() -> Void)?

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
        set {
            presentation.state.isRunning = newValue
            presentation.state.logText = presentation.textView.string
        }
    }

    @objc public var logText: String {
        get { presentation.state.logText }
        set { presentation.state.logText = newValue }
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set { presentation.state.filterQuery = newValue }
    }

    @objc public var warningCount: Int {
        presentation.state.warningCount
    }

    @objc public var errorCount: Int {
        presentation.state.errorCount
    }

    @objc public var diagnosticSeverityRawValue: Int {
        presentation.state.diagnosticSeverity.rawValue
    }

    @objc public var diagnosticSummaryText: String {
        presentation.state.diagnosticSummaryText
    }

    @objc public var matchingLineCount: Int {
        presentation.state.matchingLineCount
    }

    @objc public var totalLineCount: Int {
        presentation.state.totalLineCount
    }

    @objc public var onRun: (() -> Void)? {
        get { presentation.onRun }
        set { presentation.onRun = newValue }
    }

    @objc public var onClear: (() -> Void)? {
        get { presentation.onClear }
        set { presentation.onClear = newValue }
    }

    @objc public var onCopyOutput: (() -> Void)? {
        get { presentation.onCopyOutput }
        set { presentation.onCopyOutput = newValue }
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
            isRunning: false,
            logText: textView.string
        )
        let presentation = BPConsoleToolPresentation(textView: textView, state: state)
        self.presentation = presentation
        let host = NSHostingController(rootView: BPConsoleToolView(presentation: presentation))
        host.sizingOptions = []
        self.viewController = host
        super.init()
    }

    @objc(syncLogFromTextView)
    public func syncLogFromTextView() {
        presentation.state.logText = presentation.textView.string
    }

    @objc
    @discardableResult
    public func copyOutputToPasteboard() -> String {
        if presentation.state.logText.isEmpty && !presentation.textView.string.isEmpty {
            presentation.state.logText = presentation.textView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
        return text
    }
}

@MainActor
private struct BPConsoleToolView: View {
    @ObservedObject var presentation: BPConsoleToolPresentation

    private var filterBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { presentation.state.filterQuery = $0 }
        )
    }

    private var diagnosticColor: Color {
        switch presentation.state.diagnosticSeverity {
        case .idle:
            return .secondary
        case .running:
            return .accentColor
        case .healthy:
            return .green
        case .warnings:
            return .orange
        case .errors:
            return .red
        }
    }

    private var diagnosticSymbol: String {
        switch presentation.state.diagnosticSeverity {
        case .idle:
            return "terminal"
        case .running:
            return "clock.arrow.circlepath"
        case .healthy:
            return "checkmark.seal.fill"
        case .warnings:
            return "exclamationmark.triangle.fill"
        case .errors:
            return "xmark.octagon.fill"
        }
    }

    private func copyCurrentOutput() {
        if presentation.state.logText.isEmpty && !presentation.textView.string.isEmpty {
            presentation.state.logText = presentation.textView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(presentation.state.title)
                            .font(.system(size: 16, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityValue(presentation.state.title)

                        if presentation.state.diagnosticSeverity != .idle {
                            HStack(spacing: 4) {
                                Image(systemName: diagnosticSymbol)
                                    .font(.caption2)
                                Text(presentation.state.diagnosticSummaryText)
                                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                            }
                            .foregroundStyle(diagnosticColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(diagnosticColor.opacity(0.14))
                            )
                            .accessibilityValue(presentation.state.diagnosticSummaryText)
                            .accessibilityIdentifier("console.diagnostic.badge")
                        }
                    }
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

            BPLogFilterBarView(
                filterQuery: filterBinding,
                matchingLineCount: presentation.state.matchingLineCount,
                totalLineCount: presentation.state.totalLineCount,
                filterFieldIdentifier: "console.filterField",
                lineCountIdentifier: "console.lineCount",
                copyButtonIdentifier: "console.copyOutput",
                copyEnabled: !presentation.state.logText.isEmpty || !presentation.textView.string.isEmpty,
                onCopyOutput: copyCurrentOutput
            )
            .padding(.horizontal, 14)

            ZStack {
                BPTextViewContainerRepresentable(textView: presentation.textView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !presentation.state.trimmedFilterQuery.isEmpty {
                    BPFilteredLogOverlayView(
                        filteredText: presentation.state.filteredOutputText,
                        accessibilityID: "console.filteredOutput"
                    )
                }
            }
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
    @Published var state = BPServicesState()
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
    var onFilterChanged: (() -> Void)?

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

    @objc public var statusFilterRawValue: Int {
        get { presentation.state.statusFilter.rawValue }
        set {
            let filter = BPServiceStatusFilter(rawValue: newValue) ?? .all
            presentation.state.statusFilter = filter
            presentation.onFilterChanged?()
        }
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set {
            presentation.state.filterQuery = newValue
            presentation.onFilterChanged?()
        }
    }

    @objc public var runningCount: Int {
        presentation.state.runningCount
    }

    @objc public var stoppedCount: Int {
        presentation.state.stoppedCount
    }

    @objc public var errorCount: Int {
        presentation.state.errorCount
    }

    @objc public var totalCount: Int {
        presentation.state.totalCount
    }

    @objc public var serviceFilePath: String {
        get { presentation.state.serviceFilePath }
        set { presentation.state.serviceFilePath = newValue }
    }

    @objc public var logFilePath: String {
        get { presentation.state.logFilePath }
        set { presentation.state.logFilePath = newValue }
    }

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

    @objc public var onFilterChanged: (() -> Void)? {
        get { presentation.onFilterChanged }
        set { presentation.onFilterChanged = newValue }
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

    @objc(syncCountsWithRunning:stopped:error:)
    public func syncCounts(running: Int, stopped: Int, error: Int) {
        presentation.state.runningCount = running
        presentation.state.stoppedCount = stopped
        presentation.state.errorCount = error
    }

    @objc(syncPathsWithServiceFile:logFile:)
    public func syncPaths(serviceFile: String?, logFile: String?) {
        presentation.state.serviceFilePath = serviceFile ?? ""
        presentation.state.logFilePath = logFile ?? ""
    }

    @objc
    @discardableResult
    public func copyServiceFilePathToPasteboard() -> String {
        let path = presentation.state.serviceFilePath
        guard !path.isEmpty else { return "" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        return path
    }

    @objc
    @discardableResult
    public func copyLogPathToPasteboard() -> String {
        let path = presentation.state.logFilePath
        guard !path.isEmpty else { return "" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        return path
    }
}

@MainActor
private struct BPServicesView: View {
    @ObservedObject var presentation: BPServicesPresentation

    private var queryBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { newValue in
                presentation.state.filterQuery = newValue
                presentation.onFilterChanged?()
            }
        )
    }

    private func selectFilter(_ filter: BPServiceStatusFilter) {
        presentation.state.statusFilter = filter
        presentation.onFilterChanged?()
    }

    @ViewBuilder
    private func filterPill(filter: BPServiceStatusFilter,
                            title: String,
                            count: Int,
                            color: Color,
                            accessibilityID: String) -> some View {
        let isSelected = (presentation.state.statusFilter == filter)
        Button {
            selectFilter(filter)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                Text("\(count)")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
            }
            .foregroundStyle(isSelected ? .white : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? color : color.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(NSLocalizedString("Services_Title", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityValue(NSLocalizedString("Services_Title", comment: ""))

                Spacer()

                filterPill(
                    filter: .all,
                    title: NSLocalizedString("Services_Title", comment: ""),
                    count: presentation.state.totalCount,
                    color: .accentColor,
                    accessibilityID: "services.filter.all"
                )
                filterPill(
                    filter: .running,
                    title: NSLocalizedString("Services_Status_Started", comment: ""),
                    count: presentation.state.runningCount,
                    color: .green,
                    accessibilityID: "services.filter.running"
                )
                filterPill(
                    filter: .stopped,
                    title: NSLocalizedString("Services_Status_Stopped", comment: ""),
                    count: presentation.state.stoppedCount,
                    color: .secondary,
                    accessibilityID: "services.filter.stopped"
                )
                if presentation.state.errorCount > 0 || presentation.state.statusFilter == .error {
                    filterPill(
                        filter: .error,
                        title: NSLocalizedString("Services_Status_Error", comment: ""),
                        count: presentation.state.errorCount,
                        color: .red,
                        accessibilityID: "services.filter.error"
                    )
                }

                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(NSLocalizedString("Toolbar_Search", comment: ""), text: queryBinding)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .accessibilityIdentifier("services.searchField")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(width: 150)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }

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

                if !presentation.state.serviceFilePath.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(presentation.state.serviceFilePath, forType: .string)
                    } label: {
                        Label(URL(fileURLWithPath: presentation.state.serviceFilePath).lastPathComponent, systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                    .help(presentation.state.serviceFilePath)
                    .accessibilityIdentifier("services.copyServicePath")
                }

                if !presentation.state.logFilePath.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(presentation.state.logFilePath, forType: .string)
                    } label: {
                        Label(URL(fileURLWithPath: presentation.state.logFilePath).lastPathComponent, systemImage: "doc.text")
                    }
                    .controlSize(.small)
                    .help(presentation.state.logFilePath)
                    .accessibilityIdentifier("services.copyLogPath")
                }

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
    var onCopyOutput: (() -> Void)?

    init(outputTextView: NSTextView) {
        self.outputTextView = outputTextView
    }
}

@MainActor
@objc(BPAutoremoveHost)
public final class BPAutoremoveHost: NSObject {
    private let presentation: BPAutoremovePresentation
    @objc public let viewController: NSViewController

    @objc public var candidateCount: Int {
        get { presentation.state.candidateCount }
        set { presentation.state.candidateCount = newValue }
    }

    @objc public var logText: String {
        get { presentation.state.logText }
        set { presentation.state.logText = newValue }
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set { presentation.state.filterQuery = newValue }
    }

    @objc public var matchingLineCount: Int {
        presentation.state.matchingLineCount
    }

    @objc public var totalLineCount: Int {
        presentation.state.totalLineCount
    }

    @objc public var onRemove: (() -> Void)? {
        get { presentation.onRemove }
        set { presentation.onRemove = newValue }
    }

    @objc public var onCancelOrClose: (() -> Void)? {
        get { presentation.onCancelOrClose }
        set { presentation.onCancelOrClose = newValue }
    }

    @objc public var onCopyOutput: (() -> Void)? {
        get { presentation.onCopyOutput }
        set { presentation.onCopyOutput = newValue }
    }

    @objc(initWithOutputTextView:)
    public init(outputTextView: NSTextView) {
        let presentation = BPAutoremovePresentation(outputTextView: outputTextView)
        presentation.state.logText = outputTextView.string
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
        presentation.state.logText = presentation.outputTextView.string
    }

    @objc(syncLogFromTextView)
    public func syncLogFromTextView() {
        presentation.state.logText = presentation.outputTextView.string
    }

    @objc
    @discardableResult
    public func copyOutputToPasteboard() -> String {
        if presentation.state.logText.isEmpty && !presentation.outputTextView.string.isEmpty {
            presentation.state.logText = presentation.outputTextView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
        return text
    }
}

@MainActor
private struct BPAutoremoveView: View {
    @ObservedObject var presentation: BPAutoremovePresentation

    private var filterBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { presentation.state.filterQuery = $0 }
        )
    }

    private func copyCurrentOutput() {
        if presentation.state.logText.isEmpty && !presentation.outputTextView.string.isEmpty {
            presentation.state.logText = presentation.outputTextView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(presentation.state.statusText)
                    .font(.system(size: 14, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityValue(presentation.state.statusText)
                    .accessibilityIdentifier("autoremove.status")

                if presentation.state.candidateCount > 0 {
                    Text("\(presentation.state.candidateCount)")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.14))
                        )
                        .accessibilityValue("\(presentation.state.candidateCount)")
                        .accessibilityIdentifier("autoremove.candidateBadge")
                }

                Spacer()
            }

            Text(presentation.state.warningText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityValue(presentation.state.warningText)

            BPLogFilterBarView(
                filterQuery: filterBinding,
                matchingLineCount: presentation.state.matchingLineCount,
                totalLineCount: presentation.state.totalLineCount,
                filterFieldIdentifier: "autoremove.filterField",
                lineCountIdentifier: "autoremove.lineCount",
                copyButtonIdentifier: "autoremove.copyOutput",
                copyEnabled: !presentation.state.logText.isEmpty || !presentation.outputTextView.string.isEmpty,
                onCopyOutput: copyCurrentOutput
            )

            ZStack {
                BPTextViewContainerRepresentable(textView: presentation.outputTextView)
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)

                if !presentation.state.trimmedFilterQuery.isEmpty {
                    BPFilteredLogOverlayView(
                        filteredText: presentation.state.filteredOutputText,
                        accessibilityID: "autoremove.filteredOutput"
                    )
                }
            }

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
    var onCopyOutput: (() -> Void)?

    init(importTextView: NSTextView) {
        self.importTextView = importTextView
    }
}

@MainActor
@objc(BPBundleOperationHost)
public final class BPBundleOperationHost: NSObject {
    private let presentation: BPBundleOperationPresentation
    @objc public let viewController: NSViewController

    @objc public var logText: String {
        get { presentation.state.logText }
        set { presentation.state.logText = newValue }
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set { presentation.state.filterQuery = newValue }
    }

    @objc public var matchingLineCount: Int {
        presentation.state.matchingLineCount
    }

    @objc public var totalLineCount: Int {
        presentation.state.totalLineCount
    }

    @objc public var onAction: (() -> Void)? {
        get { presentation.onAction }
        set { presentation.onAction = newValue }
    }

    @objc public var onCopyOutput: (() -> Void)? {
        get { presentation.onCopyOutput }
        set { presentation.onCopyOutput = newValue }
    }

    @objc(initWithImportTextView:)
    public init(importTextView: NSTextView) {
        let presentation = BPBundleOperationPresentation(importTextView: importTextView)
        presentation.state.logText = importTextView.string
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
            succeeded: !running,
            logText: presentation.importTextView.string,
            filterQuery: presentation.state.filterQuery
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
            succeeded: succeeded,
            logText: presentation.state.logText,
            filterQuery: presentation.state.filterQuery
        )
    }

    @objc(syncLogFromTextView)
    public func syncLogFromTextView() {
        presentation.state.logText = presentation.importTextView.string
    }

    @objc
    @discardableResult
    public func copyOutputToPasteboard() -> String {
        if presentation.state.logText.isEmpty && !presentation.importTextView.string.isEmpty {
            presentation.state.logText = presentation.importTextView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
        return text
    }
}

@MainActor
private struct BPBundleOperationView: View {
    @ObservedObject var presentation: BPBundleOperationPresentation

    private var filterBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { presentation.state.filterQuery = $0 }
        )
    }

    private func copyCurrentOutput() {
        if presentation.state.logText.isEmpty && !presentation.importTextView.string.isEmpty {
            presentation.state.logText = presentation.importTextView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
    }

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

                    BPLogFilterBarView(
                        filterQuery: filterBinding,
                        matchingLineCount: presentation.state.matchingLineCount,
                        totalLineCount: presentation.state.totalLineCount,
                        filterFieldIdentifier: "brewfile.import.filterField",
                        lineCountIdentifier: "brewfile.import.lineCount",
                        copyButtonIdentifier: "brewfile.import.copyOutput",
                        copyEnabled: !presentation.state.logText.isEmpty || !presentation.importTextView.string.isEmpty,
                        onCopyOutput: copyCurrentOutput
                    )

                    ZStack {
                        BPTextViewContainerRepresentable(textView: presentation.importTextView)
                            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)

                        if !presentation.state.trimmedFilterQuery.isEmpty {
                            BPFilteredLogOverlayView(
                                filteredText: presentation.state.filteredOutputText,
                                accessibilityID: "brewfile.import.filteredOutput"
                            )
                        }
                    }
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

    @objc public var appliedOptionCount: Int {
        presentation.state.appliedOptionCount
    }

    @objc public var filteredOptionCount: Int {
        presentation.state.filteredOptions.count
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set { presentation.state.filterQuery = newValue }
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

    @objc
    public func clearAllAppliedOptions() {
        let previouslyApplied = presentation.state.selectedOptionNames
        presentation.state.clearAllApplied()
        for name in previouslyApplied {
            presentation.onOptionToggled?(name, false)
        }
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

    private var filterBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { presentation.state.filterQuery = $0 }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(presentation.state.headerTitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .accessibilityValue(presentation.state.headerTitle)
                Text(presentation.state.formulaName)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityValue(presentation.state.formulaName)
                    .accessibilityIdentifier("formula.options.formulaName")

                if presentation.state.appliedOptionCount > 0 {
                    Text("\(presentation.state.appliedOptionCount)")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        )
                        .accessibilityValue("\(presentation.state.appliedOptionCount)")
                        .accessibilityIdentifier("formula.options.appliedBadge")
                }

                Spacer()

                if !presentation.state.options.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(NSLocalizedString("Toolbar_Search", comment: ""), text: filterBinding)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .accessibilityIdentifier("formula.options.searchField")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .frame(width: 140)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
            }

            List(presentation.state.filteredOptions, selection: selectionBinding) { row in
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
    var onCopyOutput: (() -> Void)?

    init(recordTextView: NSTextView) {
        self.recordTextView = recordTextView
    }
}

@MainActor
@objc(BPInstallationHost)
public final class BPInstallationHost: NSObject {
    private let presentation: BPInstallationPresentation
    @objc public let viewController: NSViewController

    @objc public var logText: String {
        get { presentation.state.logText }
        set { presentation.state.logText = newValue }
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set { presentation.state.filterQuery = newValue }
    }

    @objc public var matchingLineCount: Int {
        presentation.state.matchingLineCount
    }

    @objc public var totalLineCount: Int {
        presentation.state.totalLineCount
    }

    @objc public var onCancel: (() -> Void)? {
        get { presentation.onCancel }
        set { presentation.onCancel = newValue }
    }

    @objc public var onOK: (() -> Void)? {
        get { presentation.onOK }
        set { presentation.onOK = newValue }
    }

    @objc public var onCopyOutput: (() -> Void)? {
        get { presentation.onCopyOutput }
        set { presentation.onCopyOutput = newValue }
    }

    @objc(initWithRecordTextView:)
    public init(recordTextView: NSTextView) {
        let presentation = BPInstallationPresentation(recordTextView: recordTextView)
        presentation.state.logText = recordTextView.string
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
            cancelEnabled: cancelEnabled,
            logText: presentation.recordTextView.string,
            filterQuery: presentation.state.filterQuery
        )
    }

    @objc(syncLogFromTextView)
    public func syncLogFromTextView() {
        presentation.state.logText = presentation.recordTextView.string
    }

    @objc
    @discardableResult
    public func copyOutputToPasteboard() -> String {
        if presentation.state.logText.isEmpty && !presentation.recordTextView.string.isEmpty {
            presentation.state.logText = presentation.recordTextView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
        return text
    }
}

@MainActor
private struct BPInstallationView: View {
    @ObservedObject var presentation: BPInstallationPresentation

    private var filterBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { presentation.state.filterQuery = $0 }
        )
    }

    private func copyCurrentOutput() {
        if presentation.state.logText.isEmpty && !presentation.recordTextView.string.isEmpty {
            presentation.state.logText = presentation.recordTextView.string
        }
        let text = presentation.state.filteredOutputText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        presentation.onCopyOutput?()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

                Spacer()
            }

            BPLogFilterBarView(
                filterQuery: filterBinding,
                matchingLineCount: presentation.state.matchingLineCount,
                totalLineCount: presentation.state.totalLineCount,
                filterFieldIdentifier: "installation.filterField",
                lineCountIdentifier: "installation.lineCount",
                copyButtonIdentifier: "installation.copyOutput",
                copyEnabled: !presentation.state.logText.isEmpty || !presentation.recordTextView.string.isEmpty,
                onCopyOutput: copyCurrentOutput
            )

            ZStack {
                BPTextViewContainerRepresentable(textView: presentation.recordTextView)
                    .frame(maxWidth: .infinity, minHeight: 154, maxHeight: .infinity)

                if !presentation.state.trimmedFilterQuery.isEmpty {
                    BPFilteredLogOverlayView(
                        filteredText: presentation.state.filteredOutputText,
                        accessibilityID: "installation.filteredOutput"
                    )
                }
            }

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

    @objc public var statusFilterRawValue: Int {
        get { presentation.state.statusFilter.rawValue }
        set { presentation.state.statusFilter = BPBrewfileEntryFilter(rawValue: newValue) ?? .all }
    }

    @objc public var filterQuery: String {
        get { presentation.state.filterQuery }
        set { presentation.state.filterQuery = newValue }
    }

    @objc public var matchingEntryCount: Int {
        presentation.state.matchingEntryCount
    }

    @objc public var entriesTextView: NSTextView {
        presentation.entriesTextView
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

    @objc
    @discardableResult
    public func copySummaryToPasteboard() -> String {
        let text = presentation.state.filteredSummaryText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return text
    }
}

@MainActor
private struct BPBrewfileReviewView: View {
    @ObservedObject var presentation: BPBrewfileReviewPresentation

    private var filterBinding: Binding<String> {
        Binding(
            get: { presentation.state.filterQuery },
            set: { presentation.state.filterQuery = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(presentation.state.fileName, systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier("brewfile.review.fileName")

                Spacer()

                filterPillButton(
                    filter: .all,
                    count: presentation.state.totalEntryCount,
                    label: BPLocalizedWithFallback("Brewfile", fallback: "All"),
                    color: .accentColor,
                    accessibilityID: "brewfile.review.filter.all"
                )
                filterPillButton(
                    filter: .installed,
                    count: presentation.state.installedCount,
                    label: BPLocalizedWithFallback("Installed", fallback: "Installed"),
                    color: .green,
                    accessibilityID: "brewfile.review.filter.installed"
                )
                filterPillButton(
                    filter: .missing,
                    count: presentation.state.missingCount,
                    label: BPLocalizedWithFallback("Missing", fallback: "Missing"),
                    color: .orange,
                    accessibilityID: "brewfile.review.filter.missing"
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

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(NSLocalizedString("Toolbar_Search", comment: ""), text: filterBinding)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .accessibilityIdentifier("brewfile.review.searchField")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: 200)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

                Spacer()

                Button {
                    let text = presentation.state.filteredSummaryText
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label(NSLocalizedString("Services_Copy_Output", comment: ""), systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(presentation.state.summaryText.isEmpty)
                .accessibilityIdentifier("brewfile.review.copySummary")
            }

            ZStack {
                BPTextViewContainerRepresentable(textView: presentation.entriesTextView)
                    .frame(maxWidth: .infinity, minHeight: 185, maxHeight: .infinity)

                if presentation.state.isFiltering {
                    BPFilteredLogOverlayView(
                        filteredText: presentation.state.filteredSummaryText,
                        accessibilityID: "brewfile.review.filteredEntries"
                    )
                }
            }
        }
        .frame(width: 570, height: 296)
    }

    @ViewBuilder
    private func filterPillButton(filter: BPBrewfileEntryFilter,
                                  count: Int,
                                  label: String,
                                  color: Color,
                                  accessibilityID: String) -> some View {
        let isSelected = (presentation.state.statusFilter == filter)
        Button {
            presentation.state.statusFilter = filter
        } label: {
            HStack(spacing: 4) {
                Text("\(count)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                Text(label)
                    .font(.caption)
            }
            .foregroundStyle(isSelected ? .white : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSelected ? color : color.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
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

// MARK: - Swift 6 AppKit & Presentation Views / Window Controllers

@objc(BPStyle)
public final class BPStyle: NSObject {
    @objc public static func defaultFixedWidthFont() -> NSFont {
        return NSFont.monospacedSystemFont(ofSize: 12.0, weight: .regular)
    }

    @objc public static func toolbarSize() -> NSToolbar.SizeMode {
        return .default
    }

    @objc public static func toolbarImageForInstall() -> NSImage? {
        return appropriateIconForToolbar(name: "download", symbol: "plus.circle.fill")
    }

    @objc public static func toolbarImageForUninstall() -> NSImage? {
        return appropriateIconForToolbar(name: "delete", symbol: "xmark.circle.fill")
    }

    @objc public static func toolbarImageForTap() -> NSImage? {
        return appropriateIconForToolbar(name: "download", symbol: "plus.circle.fill")
    }

    @objc public static func toolbarImageForUntap() -> NSImage? {
        return appropriateIconForToolbar(name: "delete", symbol: "xmark.circle.fill")
    }

    @objc public static func toolbarImageForUpdate() -> NSImage? {
        return appropriateIconForToolbar(name: "reload", symbol: "arrow.triangle.2.circlepath.circle.fill")
    }

    @objc public static func toolbarImageForMoreInformation() -> NSImage? {
        return appropriateIconForToolbar(name: "label", symbol: "info.circle.fill")
    }

    @objc public static func toolbarImageForUpgrade() -> NSImage? {
        return appropriateIconForToolbar(name: "globe", symbol: "globe")
    }

    @objc public static func toolbarImageForCancel() -> NSImage? {
        return appropriateIconForToolbar(name: "cancel", symbol: "stop.circle")
    }

    private static func appropriateIconForToolbar(name: String, symbol: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: name) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(scale: .medium)
        let configured = image.withSymbolConfiguration(config) ?? image
        configured.isTemplate = true
        return configured
    }

    @objc public static func popoverTitleColor() -> NSColor {
        return .textColor
    }

    @objc public static func popoverTextViewColor() -> NSColor {
        return .textColor
    }
}

@objc(BPDockMenuItem)
public enum BPDockMenuItem: Int {
    case checkForUpdates = 1
    case upgradeAllOutdated = 2
    case showOutdated = 3
}

@objc(BPDockMenu)
public final class BPDockMenu: NSObject {
    @objc public static func menuItemAction() -> Selector {
        return NSSelectorFromString("performDockMenuAction:")
    }

    @objc(dockMenuWithTarget:enabled:)
    public static func dockMenu(withTarget target: AnyObject?, enabled: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let items: [BPDockMenuItem] = [.checkForUpdates, .upgradeAllOutdated, .showOutdated]
        for item in items {
            let menuItem = NSMenuItem(
                title: title(for: item),
                action: menuItemAction(),
                keyEquivalent: ""
            )
            menuItem.tag = item.rawValue
            menuItem.target = target
            menuItem.isEnabled = enabled
            menu.addItem(menuItem)
        }
        return menu
    }

    @objc(localizationKeyForItem:)
    public static func localizationKey(for item: BPDockMenuItem) -> String? {
        switch item {
        case .checkForUpdates:    return "Dock_Check_For_Updates"
        case .upgradeAllOutdated: return "Dock_Upgrade_All_Outdated"
        case .showOutdated:       return "Dock_Show_Outdated"
        @unknown default:         return nil
        }
    }

    private static func title(for item: BPDockMenuItem) -> String {
        guard let key = localizationKey(for: item) else { return "" }
        return NSLocalizedString(key, comment: "")
    }

    @objc(controllerActionForItem:)
    public static func controllerAction(for item: BPDockMenuItem) -> Selector? {
        switch item {
        case .checkForUpdates:    return NSSelectorFromString("updateHomebrew:")
        case .upgradeAllOutdated: return NSSelectorFromString("upgradeAllOutdatedFormulae:")
        case .showOutdated:       return NSSelectorFromString("showUnifiedUpdates:")
        @unknown default:         return nil
        }
    }
}

@objc(BPBackgroundView)
public final class BPBackgroundView: NSView {
    @objc public var backgroundColor: NSColor?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        if backgroundColor == nil {
            backgroundColor = .controlColor
            wantsLayer = true
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        backgroundColor?.setFill()
        dirtyRect.fill()
    }
}

@MainActor
@objc(BPLoadingView)
public final class BPLoadingView: NSView {
    @objc public var view: NSView?
    @objc public weak var progressIndicator: NSProgressIndicator?
    @objc public var loadingHost: BPLoadingHost?

    public override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            progressIndicator?.startAnimation(self)
        }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        let host = BPLoadingHost()
        self.loadingHost = host
        let hostView = host.viewController.view
        hostView.frame = bounds
        hostView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostView)
        self.view = hostView
        NSLayoutConstraint.activate([
            hostView.topAnchor.constraint(equalTo: topAnchor),
            hostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostView.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
}

@MainActor
@objc(BPEmptyStateView)
public final class BPEmptyStateView: NSView {
    private static let emptyStateViewTag = 0x43424553
    @objc public var host: BPEmptyStateHost?

    @objc(presentState:overView:)
    public static func presentState(_ state: BPEmptyState?, over container: NSView?) {
        guard let container else { return }
        for subview in container.subviews where subview.tag == emptyStateViewTag {
            subview.removeFromSuperview()
        }
        guard let state else { return }

        let title = NSLocalizedString(state.titleKey, comment: "")
        let message = NSLocalizedString(state.messageKey, comment: "")

        let view = BPEmptyStateView(frame: container.bounds)
        view.translatesAutoresizingMaskIntoConstraints = false
        let emptyHost = BPEmptyStateHost(
            symbolName: state.symbolName.isEmpty ? "tray" : state.symbolName,
            title: title,
            message: message
        )
        view.host = emptyHost

        let hostView = emptyHost.viewController.view
        hostView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostView)
        container.addSubview(view)

        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.staticText)
        view.setAccessibilityLabel("\(title). \(message)")

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostView.topAnchor.constraint(equalTo: view.topAnchor),
            hostView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    public override var tag: Int {
        return Self.emptyStateViewTag
    }

    public override var isOpaque: Bool {
        return false
    }
}

private final class BPAutoScrollBuffer: @unchecked Sendable {
    let lock = NSLock()
    let pending = NSMutableString()
    var flushScheduled = false
}

@MainActor
@objc(BPAutoScrollTextView)
public final class BPAutoScrollTextView: NSTextView {
    nonisolated private static let maxScrollback = 2 * 1024 * 1024
    nonisolated private static let trimTargetLength = Int(1.5 * 1024.0 * 1024.0)
    private let buffer = BPAutoScrollBuffer()

    @objc nonisolated public static var maximumScrollbackLength: UInt {
        return UInt(maxScrollback)
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override var string: String {
        get { super.string }
        set {
            super.string = newValue
            scrollToEndOfDocument(self)
        }
    }

    @objc(appendOutput:)
    nonisolated public func appendOutput(_ chunk: String?) {
        guard let chunk, !chunk.isEmpty else { return }
        var needsFlush = false
        buffer.lock.lock()
        buffer.pending.append(chunk)
        if !buffer.flushScheduled {
            buffer.flushScheduled = true
            needsFlush = true
        }
        buffer.lock.unlock()

        guard needsFlush else { return }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.flushPendingOutput()
            }
        } else {
            DispatchQueue.main.async {
                self.flushPendingOutput()
            }
        }
    }

    @objc public func clearOutput() {
        buffer.lock.lock()
        buffer.pending.setString("")
        buffer.lock.unlock()
        self.string = ""
    }

    @objc public func flushPendingOutput() {
        buffer.lock.lock()
        let chunk = buffer.pending.copy() as? String ?? ""
        buffer.pending.setString("")
        buffer.flushScheduled = false
        buffer.lock.unlock()

        guard !chunk.isEmpty, let storage = self.textStorage else { return }
        let chunkNS = chunk as NSString
        storage.beginEditing()
        let appendedRange = NSRange(location: storage.length, length: chunkNS.length)
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: chunk)
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: appendedRange)
        trimScrollback(in: storage)
        storage.endEditing()

        scrollRangeToVisible(NSRange(location: storage.length, length: 0))
    }

    private func trimScrollback(in storage: NSTextStorage) {
        guard storage.length > Self.maxScrollback else { return }
        var excess = storage.length - Self.trimTargetLength
        let nsString = storage.string as NSString
        let searchLength = min(4096, storage.length - excess)
        let newline = nsString.range(of: "\n", options: [], range: NSRange(location: excess, length: searchLength))
        if newline.location != NSNotFound {
            excess = NSMaxRange(newline)
        }
        storage.replaceCharacters(in: NSRange(location: 0, length: excess), with: "")
    }
}

@MainActor
@objc(DCOAboutWindowController)
public final class DCOAboutWindowController: NSWindowController {
    @objc public var infoView: NSView?
    @objc public var visitWebsiteButton: NSButton?
    @objc public var acknowledgementsButton: NSButton?
    @objc public private(set) var creditsTextView: NSTextView?
    @objc public private(set) var aboutHost: BPAboutWindowHost?
    @objc public var appAcknowledgements: NSAttributedString?

    @objc public var appName: String?
    @objc public var appVersion: String?
    @objc public var appCopyright: String?
    @objc public var appCredits: NSAttributedString?
    @objc public var appWebsiteURL: URL?

    @objc public var acknowledgementsPath: String? {
        didSet {
            loadAppAcknowledgements()
            if acknowledgementsPath == nil {
                acknowledgementsButton?.removeFromSuperview()
            }
            if let aboutHost {
                aboutHost.configure(
                    appName: appName ?? "Cakebrew",
                    appVersion: appVersion ?? "",
                    appCopyright: appCopyright ?? "",
                    hasAcknowledgements: ((acknowledgementsPath?.isEmpty == false) || (appAcknowledgements?.length ?? 0) > 0)
                )
            }
        }
    }

    @objc public static func nibName() -> String {
        return "DCOAboutWindow"
    }

    public init() {
        super.init(window: nil)
    }

    public override init(window: NSWindow?) {
        super.init(window: window)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override var windowNibName: NSNib.Name? {
        return NSNib.Name(Self.nibName())
    }

    public override func loadWindow() {
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
    }

    public override func windowDidLoad() {
        super.windowDidLoad()

        let bundleDict = Bundle.main.infoDictionary ?? [:]
        let resourceBundle = Bundle(for: Self.self)

        if appName == nil {
            appName = (bundleDict["CFBundleName"] as? String) ?? "Cakebrew"
        }

        if appVersion == nil {
            let version = (bundleDict["CFBundleVersion"] as? String) ?? "1"
            let shortVersion = (bundleDict["CFBundleShortVersionString"] as? String) ?? "1.0"
            appVersion = String(format: NSLocalizedString("Version %@ (Build %@)", comment: ""), shortVersion, version)
        }

        if appCopyright == nil {
            appCopyright = (bundleDict["NSHumanReadableCopyright"] as? String) ?? ""
        }

        if let button = visitWebsiteButton, !button.title.isEmpty, button.title.contains("%@"), let appName {
            button.title = String(format: button.title, appName)
        }

        if acknowledgementsPath == nil {
            acknowledgementsPath = Bundle.main.path(forResource: "Acknowledgements", ofType: "rtf")
                ?? resourceBundle.path(forResource: "Acknowledgements", ofType: "rtf")
        } else {
            loadAppAcknowledgements()
        }

        if appCredits == nil {
            loadAppCredits()
        }

        let textView = creditsTextView ?? NSTextView(frame: NSRect(x: 0, y: 0, width: 440, height: 180))
        self.creditsTextView = textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.setAccessibilityIdentifier("about.textView")
        applyDisplayedAttributedText(appCredits)

        let host = BPAboutWindowHost(creditsTextView: textView)
        host.configure(
            appName: appName ?? "Cakebrew",
            appVersion: appVersion ?? "",
            appCopyright: appCopyright ?? "",
            hasAcknowledgements: ((acknowledgementsPath?.isEmpty == false) || (appAcknowledgements?.length ?? 0) > 0)
        )
        host.onVisitWebsite = { [weak self] in
            self?.visitWebsite(nil)
        }
        host.onSelectTab = { [weak self] tabIndex in
            guard let self else { return }
            let targetText: NSAttributedString?
            if tabIndex == 1, let ack = self.appAcknowledgements, ack.length > 0 {
                targetText = ack
            } else {
                targetText = self.appCredits
            }
            self.applyDisplayedAttributedText(targetText)
        }
        self.aboutHost = host

        if let contentView = window?.contentView {
            for subview in contentView.subviews {
                subview.removeFromSuperview()
            }
            let hostView = host.viewController.view
            hostView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(hostView)
            NSLayoutConstraint.activate([
                hostView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
    }

    private func applyDisplayedAttributedText(_ attributedText: NSAttributedString?) {
        guard let storage = creditsTextView?.textStorage else { return }
        if let attributedText {
            storage.setAttributedString(attributedText)
        } else {
            creditsTextView?.string = ""
        }
    }

    private func normalizedAttributedString(fromRTFURL url: URL?) -> NSAttributedString? {
        guard let url,
              let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) else {
            return nil
        }
        let mutableText = NSMutableAttributedString(attributedString: attributed)
        attributed.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributed.length), options: []) { value, range, _ in
            if value == nil && range.length > 0 {
                mutableText.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
            }
        }
        return mutableText
    }

    private func loadAppCredits() {
        let creditsURL = Bundle.main.url(forResource: "Credits", withExtension: "rtf")
            ?? Bundle(for: Self.self).url(forResource: "Credits", withExtension: "rtf")
        if let credits = normalizedAttributedString(fromRTFURL: creditsURL) {
            appCredits = credits
        }
    }

    private func loadAppAcknowledgements() {
        let ackURL: URL?
        if let path = acknowledgementsPath, !path.isEmpty {
            ackURL = URL(fileURLWithPath: path)
        } else {
            ackURL = Bundle.main.url(forResource: "Acknowledgements", withExtension: "rtf")
                ?? Bundle(for: Self.self).url(forResource: "Acknowledgements", withExtension: "rtf")
        }
        if let ack = normalizedAttributedString(fromRTFURL: ackURL) {
            appAcknowledgements = ack
        }
    }

    @objc(visitWebsite:)
    public func visitWebsite(_ sender: Any?) {
        if let appWebsiteURL {
            NSWorkspace.shared.open(appWebsiteURL)
        }
    }

    @objc(showAcknowledgements:)
    public func showAcknowledgements(_ sender: Any?) {
        if let aboutHost, let ack = appAcknowledgements, ack.length > 0 {
            aboutHost.selectTab(at: 1)
            return
        }
        if let path = acknowledgementsPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
}

extension NSLayoutConstraint {
    @objc(activate:)
    public static func bp_activate(_ constraints: [NSLayoutConstraint]) {
        NSLayoutConstraint.activate(constraints)
    }
}

@MainActor
@objc(BPMainWindowController)
public final class BPMainWindowController: NSWindowController {
    @objc public weak var sidebarView: NSScrollView?
    @objc public weak var windowContentView: NSView?
    @objc public private(set) var splitViewController: NSSplitViewController?

    @objc(toggleSidebar:)
    public func toggleSidebar(_ sender: Any?) {
        splitViewController?.toggleSidebar(sender)
    }

    @objc public func setUpViews() {
        guard let window = self.window else { return }
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic

        let splitVC = NSSplitViewController(nibName: nil, bundle: nil)
        splitVC.addSplitViewItem(makeSidebarSplitViewItem())
        splitVC.addSplitViewItem(makeContentSplitViewItem())
        self.splitViewController = splitVC

        let splitControllerView = splitVC.view
        guard let contentView = window.contentView else { return }

        splitControllerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(splitControllerView)

        NSLayoutConstraint.activate([
            splitControllerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitControllerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitControllerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitControllerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @objc(setContentViewHidden:)
    public func setContentViewHidden(_ hide: Bool) {
        windowContentView?.isHidden = hide
    }

    private func makeSidebarSplitViewItem() -> NSSplitViewItem {
        let vc = NSViewController(nibName: nil, bundle: nil)
        if let sidebarView {
            vc.view = sidebarView
        }
        let item = NSSplitViewItem(sidebarWithViewController: vc)
        item.minimumThickness = 190.0
        item.maximumThickness = 280.0
        return item
    }

    private func makeContentSplitViewItem() -> NSSplitViewItem {
        let vc = NSViewController(nibName: nil, bundle: nil)
        if let windowContentView {
            vc.view = windowContentView
        }
        return NSSplitViewItem(viewController: vc)
    }
}

@MainActor
@objc(BPDisabledView)
public final class BPDisabledView: NSView {
    @objc public var view: NSView?
    @objc public weak var titleField: NSTextField?
    @objc public weak var messageField: NSTextField?
    @objc public weak var retryButton: NSButton?
    @objc public weak var installButton: NSButton?
    @objc public var disabledHost: BPDisabledHost?
    @objc public var retryEnabled: Bool = true
    @objc public var retryHandler: (() -> Void)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        retryEnabled = true
        let host = BPDisabledHost()
        host.onRetry = { [weak self] in
            self?.retry(nil)
        }
        host.onOpenInstructions = { [weak self] in
            self?.openInstallationInstructions(nil)
        }
        self.disabledHost = host

        let hostView = host.viewController.view
        hostView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostView)
        self.view = hostView

        NSLayoutConstraint.activate([
            hostView.topAnchor.constraint(equalTo: topAnchor),
            hostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostView.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @objc(showDiscoveryResult:checking:)
    public func showDiscoveryResult(_ result: Int, checking: Bool) {
        self.retryEnabled = !checking
        self.retryButton?.isEnabled = !checking
        let title: String
        let message: String
        if checking {
            title = NSLocalizedString("Checking for Homebrew…", comment: "")
            message = NSLocalizedString("Cakebrew is checking your login shell for Homebrew. This may take a moment.", comment: "")
        } else {
            switch result {
            case 2: // BPHomebrewDiscoveryMissing
                title = NSLocalizedString("Homebrew wasn’t found", comment: "")
                message = NSLocalizedString("Cakebrew couldn’t find Homebrew in your login shell’s PATH. Open brew.sh for installation instructions, or fix your shell configuration, then choose Try Again.", comment: "")
            case 3: // BPHomebrewDiscoveryInvalidShell
                title = NSLocalizedString("Your login shell is unavailable", comment: "")
                message = NSLocalizedString("Cakebrew needs an executable login shell listed in /etc/shells. Check your shell configuration, then choose Try Again. Homebrew installation instructions are available at brew.sh.", comment: "")
            default:
                title = NSLocalizedString("Homebrew couldn’t be checked", comment: "")
                message = NSLocalizedString("Your login shell didn’t return a usable Homebrew executable. Check its startup configuration and PATH, then choose Try Again. Installation instructions are available at brew.sh.", comment: "")
            }
        }
        titleField?.stringValue = title
        messageField?.stringValue = message
        disabledHost?.update(title: title, message: message, retryEnabled: !checking, checking: checking)
    }

    @objc(retry:)
    public func retry(_ sender: Any?) {
        if retryEnabled {
            retryHandler?()
        }
    }

    @objc(openInstallationInstructions:)
    public func openInstallationInstructions(_ sender: Any?) {
        if let url = URL(string: "https://brew.sh") {
            NSWorkspace.shared.open(url)
        }
    }
}

@objc(BPToolbarMode)
public enum BPToolbarMode: UInt {
    case initial = 0
    case `default` = 1
    case install = 2
    case uninstall = 3
    case updateSingle = 4
    case updateMany = 5
    case tap = 6
    case untap = 7
}

@MainActor
@objc(BPToolbar)
public final class BPToolbar: NSToolbar, NSToolbarDelegate, NSSearchFieldDelegate {
    private static let toolbarIdentifier = NSToolbar.Identifier("toolbarIdentifier")
    private static let itemHomebrewUpdateIdentifier = NSToolbarItem.Identifier("toolbarItemHomebrewUpdate")
    private static let itemInformationIdentifier = NSToolbarItem.Identifier("toolbarItemInformation")
    private static let itemSearchIdentifier = NSToolbarItem.Identifier("toolbarItemSearch")
    private static let itemMultiActionIdentifier = NSToolbarItem.Identifier("toolbarItemMultiAction")
    private static let itemCancelReloadIdentifier = NSToolbarItem.Identifier("toolbarItemCancelReload")

    @objc public weak var controller: AnyObject?
    @objc public var currentMode: BPToolbarMode = .initial
    @objc private(set) public var searchField: NSSearchField?

    private var _showsCancelReload: Bool = false
    @objc public var showsCancelReload: Bool {
        get { _showsCancelReload }
        set {
            guard _showsCancelReload != newValue else { return }
            _showsCancelReload = newValue
            if newValue {
                insertItem(withItemIdentifier: Self.itemCancelReloadIdentifier, at: Int(Self.cancelReloadItemIndex()))
            } else if let idx = items.firstIndex(where: { $0.itemIdentifier == Self.itemCancelReloadIdentifier }) {
                removeItem(at: idx)
            }
            validateVisibleItems()
        }
    }

    private lazy var homebrewUpdateItem: NSToolbarItem = {
        makeToolbarItem(
            identifier: Self.itemHomebrewUpdateIdentifier,
            image: BPStyle.toolbarImageForUpgrade(),
            label: NSLocalizedString("Toolbar_Homebrew_Update", comment: ""),
            action: NSSelectorFromString("updateHomebrew:")
        )
    }()

    private lazy var cancelReloadItem: NSToolbarItem = {
        makeToolbarItem(
            identifier: Self.itemCancelReloadIdentifier,
            image: BPStyle.toolbarImageForCancel(),
            label: NSLocalizedString("Toolbar_Cancel_Reload", comment: ""),
            action: NSSelectorFromString("cancelReload:")
        )
    }()

    private lazy var informationItem: NSToolbarItem = {
        makeToolbarItem(
            identifier: Self.itemInformationIdentifier,
            image: BPStyle.toolbarImageForMoreInformation(),
            label: NSLocalizedString("Toolbar_More_Information", comment: ""),
            action: NSSelectorFromString("showFormulaInfo:")
        )
    }()

    private lazy var multiActionItem: NSToolbarItem = {
        makeToolbarItem(
            identifier: Self.itemMultiActionIdentifier,
            image: nil,
            label: nil,
            action: nil
        )
    }()

    private lazy var searchToolbarItem: NSSearchToolbarItem = {
        let item = NSSearchToolbarItem(itemIdentifier: Self.itemSearchIdentifier)
        let label = NSLocalizedString("Toolbar_Search", comment: "")
        item.label = label
        item.paletteLabel = label
        item.autovalidates = false

        let field = NSSearchField(frame: .zero)
        field.delegate = self
        field.isContinuous = true
        field.recentsAutosaveName = "RecentSearches"
        self.searchField = field

        item.searchField = field
        item.action = #selector(submitSearch(_:))
        return item
    }()

    private lazy var customItemsMap: [NSToolbarItem.Identifier: NSToolbarItem] = {
        [
            Self.itemHomebrewUpdateIdentifier: homebrewUpdateItem,
            Self.itemInformationIdentifier: informationItem,
            Self.itemSearchIdentifier: searchToolbarItem,
            Self.itemMultiActionIdentifier: multiActionItem,
            Self.itemCancelReloadIdentifier: cancelReloadItem
        ]
    }()

    @objc(initWithIdentifier:)
    public override init(identifier: NSToolbar.Identifier) {
        super.init(identifier: Self.toolbarIdentifier)
        self.sizeMode = BPStyle.toolbarSize()
        self.currentMode = .initial
        configure(for: .default)
        lockItems()
    }

    @objc(configureForMode:)
    public func configure(for mode: BPToolbarMode) {
        guard currentMode != mode else { return }
        currentMode = mode

        if mode == .tap || mode == .untap || mode == .updateMany || mode == .default {
            reconfigureItem(informationItem, image: nil, label: nil, action: nil)
        } else {
            reconfigureItem(
                informationItem,
                image: BPStyle.toolbarImageForMoreInformation(),
                label: NSLocalizedString("Toolbar_More_Information", comment: ""),
                action: NSSelectorFromString("showFormulaInfo:")
            )
        }

        switch mode {
        case .default:
            reconfigureItem(multiActionItem, image: nil, label: nil, action: nil)
        case .install:
            reconfigureItem(
                multiActionItem,
                image: BPStyle.toolbarImageForInstall(),
                label: NSLocalizedString("Toolbar_Install_Formula", comment: ""),
                action: NSSelectorFromString("installFormula:")
            )
        case .uninstall:
            reconfigureItem(
                multiActionItem,
                image: BPStyle.toolbarImageForUninstall(),
                label: NSLocalizedString("Toolbar_Uninstall_Formula", comment: ""),
                action: NSSelectorFromString("uninstallFormula:")
            )
        case .tap:
            reconfigureItem(
                multiActionItem,
                image: BPStyle.toolbarImageForTap(),
                label: NSLocalizedString("Toolbar_Tap_Repo", comment: ""),
                action: NSSelectorFromString("tapRepository:")
            )
        case .untap:
            reconfigureItem(
                multiActionItem,
                image: BPStyle.toolbarImageForUntap(),
                label: NSLocalizedString("Toolbar_Untap_Repo", comment: ""),
                action: NSSelectorFromString("untapRepository:")
            )
        case .updateSingle:
            reconfigureItem(
                multiActionItem,
                image: BPStyle.toolbarImageForUpdate(),
                label: NSLocalizedString("Toolbar_Update_Formula", comment: ""),
                action: NSSelectorFromString("upgradeSelectedFormulae:")
            )
        case .updateMany:
            reconfigureItem(
                multiActionItem,
                image: BPStyle.toolbarImageForUpdate(),
                label: NSLocalizedString("Toolbar_Update_Selected", comment: ""),
                action: NSSelectorFromString("upgradeSelectedFormulae:")
            )
        case .initial:
            break
        @unknown default:
            break
        }
        validateVisibleItems()
    }

    private func updateToolbarItems(withTarget target: AnyObject?) {
        for (key, item) in customItemsMap {
            if key == Self.itemSearchIdentifier, let searchItem = item as? NSSearchToolbarItem {
                self.searchField = searchItem.searchField
                self.searchField?.delegate = self
                searchItem.target = (target != nil) ? self : nil
                searchItem.isEnabled = (target != nil)
                searchItem.searchField.isEnabled = (target != nil)
                continue
            }
            if key == Self.itemCancelReloadIdentifier {
                item.target = controller
                item.isEnabled = (controller != nil)
                continue
            }
            item.target = target
            item.isEnabled = (target != nil && item.action != nil)
        }
    }

    @objc public func lockItems() {
        updateToolbarItems(withTarget: nil)
        validateVisibleItems()
    }

    @objc public func unlockItems() {
        updateToolbarItems(withTarget: controller)
        validateVisibleItems()
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        return customItemsMap[itemIdentifier]
    }

    @objc public static func cancelReloadItemIdentifier() -> String {
        return itemCancelReloadIdentifier.rawValue
    }

    @objc public static func cancelReloadItemIndex() -> UInt {
        return 5
    }

    @objc(defaultItemIdentifiersShowingCancel:)
    public static func defaultItemIdentifiers(showingCancel: Bool) -> [String] {
        var identifiers: [String] = [
            NSToolbarItem.Identifier.toggleSidebar.rawValue,
            NSToolbarItem.Identifier.flexibleSpace.rawValue,
            itemHomebrewUpdateIdentifier.rawValue,
            NSToolbarItem.Identifier.sidebarTrackingSeparator.rawValue,
            NSToolbarItem.Identifier.flexibleSpace.rawValue,
            itemMultiActionIdentifier.rawValue,
            itemInformationIdentifier.rawValue,
            itemSearchIdentifier.rawValue
        ]
        if showingCancel {
            identifiers.insert(itemCancelReloadIdentifier.rawValue, at: Int(cancelReloadItemIndex()))
        }
        return identifiers
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return Self.defaultItemIdentifiers(showingCancel: showsCancelReload).map { NSToolbarItem.Identifier($0) }
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .space,
            .flexibleSpace,
            .sidebarTrackingSeparator,
            .toggleSidebar,
            Self.itemHomebrewUpdateIdentifier,
            Self.itemInformationIdentifier,
            Self.itemSearchIdentifier,
            Self.itemMultiActionIdentifier,
            Self.itemCancelReloadIdentifier
        ]
    }

    private func makeToolbarItem(identifier: NSToolbarItem.Identifier, image: NSImage?, label: String?, action: Selector?) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = image
        item.isBordered = true
        item.target = controller
        item.label = label ?? ""
        item.paletteLabel = label ?? ""
        item.action = action
        item.autovalidates = true
        item.toolTip = label
        return item
    }

    private func reconfigureItem(_ item: NSToolbarItem, image: NSImage?, label: String?, action: Selector?) {
        precondition(Thread.isMainThread)
        item.image = image
        item.isBordered = (image != nil)
        item.isEnabled = (action != nil)
        item.target = controller
        item.action = action
        item.label = label ?? ""
        item.toolTip = label
    }

    @objc public func makeSearchFieldFirstResponder() {
        let searchView = searchToolbarItem.searchField
        searchView.window?.makeFirstResponder(searchView)
    }

    @objc(submitSearch:)
    public func submitSearch(_ field: NSSearchField) {
        _ = controller?.perform(NSSelectorFromString("performSearchWithString:"), with: field.stringValue)
    }

    public func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSSearchField {
            submitSearch(field)
        }
    }
}

// MARK: - Objective-C AppKit & Helper Runtime Bridges

@objc private protocol BPAppDelegateObjCBridge: NSObjectProtocol {
    var window: NSWindow? { get }
    var isRunningBackgroundTask: Bool {
        @objc(isRunningBackgroundTask) get
        @objc(setRunningBackgroundTask:) set
    }
    var brewfileImportTarget: AnyObject? { get }
    @objc(displayBackgroundWarning)
    func displayBackgroundWarning()
    @objc(requestUserAttentionWithMessageTitle:andDescription:)
    func requestUserAttention(withMessageTitle title: String, andDescription desc: String)
    @objc(updateMenuBarExtra)
    func updateMenuBarExtra()
    @objc(checkForAppUpdates:)
    func checkForAppUpdates(_ sender: Any?)
}

@objc private protocol BPBrewfileImportingObjCBridge: NSObjectProtocol {
    @objc(importBrewfileAtURL:)
    func importBrewfile(at url: URL)
}

@objc private protocol BPHelperRegistrationObjCBridge: NSObjectProtocol {
    @objc(currentState)
    func currentState() -> Int
    @objc(registerReturningError:)
    func registerReturningError(_ error: NSErrorPointer) -> Bool
}

@objc private protocol BPHelperRegistrationClassObjCBridge: NSObjectProtocol {
    @objc(sharedRegistration)
    func sharedRegistration() -> AnyObject?
    @objc(localizedDescriptionForState:)
    func localizedDescription(forState state: Int) -> String
    @objc(stateOffersLoginItemsShortcut:)
    func stateOffersLoginItemsShortcut(_ state: Int) -> Bool
    @objc(openLoginItemsSettings)
    func openLoginItemsSettings()
}

@MainActor
@inline(__always)
private func bpSharedAppDelegate() -> BPAppDelegateObjCBridge? {
    guard let delegate = NSApplication.shared.delegate else { return nil }
    return unsafeBitCast(delegate as AnyObject, to: BPAppDelegateObjCBridge.self)
}

@inline(__always)
private func bpHelperRegistrationClass() -> BPHelperRegistrationClassObjCBridge? {
    guard let cls = NSClassFromString("BPHelperRegistration") else { return nil }
    return unsafeBitCast(cls as AnyObject, to: BPHelperRegistrationClassObjCBridge.self)
}

@inline(__always)
private func bpSharedHelperRegistration() -> BPHelperRegistrationObjCBridge? {
    guard let obj = bpHelperRegistrationClass()?.sharedRegistration() else { return nil }
    return unsafeBitCast(obj, to: BPHelperRegistrationObjCBridge.self)
}

// MARK: - Migrated Presenter, DataSource, Sidebar, Window & Controllers (Swift 6)

@MainActor
private var bpTapInputHostAssocKey: UInt8 = 0
@MainActor
private var bpCleanupPreviewHostAssocKey: UInt8 = 0
@MainActor
private var bpBrewfileReviewHostAssocKey: UInt8 = 0

@MainActor
@objc(BPPackageOperationPresenter)
public final class BPPackageOperationPresenter: NSObject {
    private static func operationLocalizedFormat(_ key: String, fallback: String) -> String {
        Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
    }

    @objc(installAlertForFormula:)
    public static func installAlert(forFormula formula: Any?) -> NSAlert? {
        guard let f = bpAsFormula(formula), let name = f.name, !name.isEmpty else { return nil }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Generic_Attention", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Generic_Yes", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        alert.informativeText = String(
            format: operationLocalizedFormat(
                "Confirmation_Install_Formula",
                fallback: "Are you sure you want to install the formula '%@'?"
            ),
            name
        )
        return alert
    }

    @objc(uninstallAlertForFormula:initialZapState:)
    public static func uninstallAlert(forFormula formula: Any?, initialZapState zapState: Bool) -> NSAlert? {
        guard let f = bpAsFormula(formula), let name = f.name, !name.isEmpty else { return nil }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Generic_Attention", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Generic_Yes", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        alert.informativeText = String(
            format: operationLocalizedFormat(
                "Confirmation_Uninstall_Formula",
                fallback: "Are you sure you want to uninstall the formula '%@'?"
            ),
            name
        )
        if f.cask {
            let zapCheckbox = NSButton(
                checkboxWithTitle: NSLocalizedString("Confirmation_Uninstall_Cask_Zap", comment: ""),
                target: nil,
                action: nil
            )
            zapCheckbox.sizeToFit()
            zapCheckbox.state = zapState ? .on : .off
            alert.accessoryView = zapCheckbox
        }
        return alert
    }

    @objc(upgradeAlertForFormulae:)
    public static func upgradeAlert(forFormulae formulae: [Any]?) -> NSAlert? {
        guard let formulae, !formulae.isEmpty else { return nil }
        var names: [String] = []
        names.reserveCapacity(formulae.count)
        for item in formulae {
            if let f = bpAsFormula(item), let name = f.name, !name.isEmpty {
                names.append(name)
            }
        }
        guard !names.isEmpty else { return nil }
        let formulaNames = names.joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Message_Update_Formulae_Title", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Generic_Yes", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        alert.informativeText = String(
            format: operationLocalizedFormat(
                "Message_Update_Formulae_Body",
                fallback: "Are you sure you want to update these formulae: '%@'?"
            ),
            formulaNames
        )
        return alert
    }

    @objc(updatesReviewSummaryForSnapshot:)
    public static func updatesReviewSummary(forSnapshot snapshot: BPUpdatesSnapshot?) -> String? {
        guard let snapshot, snapshot.hasEligibleUpdates else { return nil }
        var sections: [String] = []
        if !snapshot.eligibleFormulae.isEmpty {
            sections.append(String(
                format: operationLocalizedFormat("Updates_Formula_Targets", fallback: "Formulae: %@"),
                snapshot.eligibleFormulae.joined(separator: ", ")
            ))
        }
        if !snapshot.eligibleCasks.isEmpty {
            sections.append(String(
                format: operationLocalizedFormat("Updates_Cask_Targets", fallback: "Casks: %@"),
                snapshot.eligibleCasks.joined(separator: ", ")
            ))
        }
        if !snapshot.excludedFormulae.isEmpty {
            sections.append(String(
                format: operationLocalizedFormat(
                    "Updates_Pinned_Formula_Exclusions",
                    fallback: "Pinned formulae will be skipped: %@"
                ),
                snapshot.excludedFormulae.joined(separator: ", ")
            ))
        }
        if !snapshot.excludedCasks.isEmpty {
            sections.append(String(
                format: operationLocalizedFormat(
                    "Updates_Pinned_Cask_Exclusions",
                    fallback: "Pinned casks will be skipped: %@"
                ),
                snapshot.excludedCasks.joined(separator: ", ")
            ))
        }
        return sections.joined(separator: "\n\n")
    }

    @objc(upgradeAllAlertForSnapshot:)
    public static func upgradeAllAlert(forSnapshot snapshot: BPUpdatesSnapshot?) -> NSAlert? {
        guard let summary = updatesReviewSummary(forSnapshot: snapshot) else { return nil }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Updates_Confirm_Title", comment: "")
        alert.informativeText = NSLocalizedString("Updates_Review_Body", comment: "")
        let review = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 180))
        review.hasVerticalScroller = true
        review.borderType = .bezelBorder
        let targets = NSTextView(frame: review.contentView.bounds)
        targets.isEditable = false
        targets.isSelectable = true
        targets.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        targets.textContainerInset = NSSize(width: 8, height: 8)
        targets.textContainer?.widthTracksTextView = true
        targets.autoresizingMask = [.width]
        targets.isVerticallyResizable = true
        targets.isHorizontallyResizable = false
        targets.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        targets.string = summary
        targets.setAccessibilityIdentifier("updates.targets")
        targets.setAccessibilityLabel(NSLocalizedString("Updates_Review_Targets", comment: ""))
        review.documentView = targets
        alert.accessoryView = review
        alert.addButton(withTitle: NSLocalizedString("Updates_Confirm_Action", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        alert.buttons.first?.setAccessibilityIdentifier("updates.confirm")
        return alert
    }

    @objc public static func updatesChangedAlert() -> NSAlert {
        let changed = NSAlert()
        changed.messageText = NSLocalizedString("Updates_Changed_Title", comment: "")
        changed.informativeText = NSLocalizedString("Updates_Changed_Body", comment: "")
        changed.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
        return changed
    }

    @objc public static func tapInputAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Message_Tap_Title", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        alert.informativeText = NSLocalizedString("Message_Tap_Body", comment: "")

        let host = BPTapInputHost()
        objc_setAssociatedObject(alert, &bpTapInputHostAssocKey, host, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        alert.accessoryView = host.viewController.view
        return alert
    }

    @objc(tapInputHostForAlert:)
    public static func tapInputHost(for alert: NSAlert?) -> BPTapInputHost? {
        guard let alert else { return nil }
        return objc_getAssociatedObject(alert, &bpTapInputHostAssocKey) as? BPTapInputHost
    }

    @objc public static func invalidTapAlert() -> NSAlert {
        let error = NSAlert()
        error.messageText = NSLocalizedString("Message_Tap_Invalid_Title", comment: "")
        error.informativeText = NSLocalizedString("Message_Tap_Invalid_Body", comment: "")
        error.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
        return error
    }

    @objc(untapAlertForFormula:)
    public static func untapAlert(forFormula formula: Any?) -> NSAlert? {
        guard let f = bpAsFormula(formula), let name = f.name, !name.isEmpty else { return nil }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Message_Untap_Title", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        alert.informativeText = String(
            format: operationLocalizedFormat(
                "Message_Untap_Body",
                fallback: "Are you sure you want to untap the repository '%@'?"
            ),
            name
        )
        return alert
    }

    @objc(cleanupConfirmationBodyForPreview:)
    public static func cleanupConfirmationBody(for preview: BPCleanupPreview) -> String {
        let items = preview.itemCount == 1
            ? operationLocalizedFormat("Cleanup_Item_Count_One", fallback: "1 item")
            : String.localizedStringWithFormat(
                operationLocalizedFormat("Cleanup_Item_Count_Other", fallback: "%lu items"),
                UInt(preview.itemCount)
            )

        if preview.reclaimableBytes == 0 {
            return String.localizedStringWithFormat(
                operationLocalizedFormat(
                    "Confirmation_Cleanup_No_Size",
                    fallback: "Would remove %@ from Homebrew's cache and old installed versions.\n\nAre you sure you want to proceed?"
                ),
                items
            )
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        let size = formatter.string(fromByteCount: Int64(preview.reclaimableBytes))

        return String.localizedStringWithFormat(
            operationLocalizedFormat(
                "Confirmation_Cleanup",
                fallback: "Would remove %@ (%@) from Homebrew's cache and old installed versions.\n\nAre you sure you want to proceed?"
            ),
            items,
            size
        )
    }

    @objc(cleanupAlertForPreview:)
    public static func cleanupAlert(for preview: BPCleanupPreview) -> NSAlert {
        let alert = NSAlert()
        if preview.empty {
            alert.messageText = NSLocalizedString("Cleanup_Nothing_Title", comment: "")
            alert.informativeText = NSLocalizedString("Cleanup_Nothing_Body", comment: "")
            alert.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
            return alert
        }

        alert.messageText = NSLocalizedString("Generic_Attention", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Generic_Yes", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        alert.informativeText = cleanupConfirmationBody(for: preview)

        var formattedSize = ""
        if preview.reclaimableBytes > 0 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .binary
            formattedSize = formatter.string(fromByteCount: Int64(preview.reclaimableBytes))
        }
        let host = BPCleanupPreviewHost(
            itemCount: Int(preview.itemCount),
            reclaimableBytes: preview.reclaimableBytes,
            formattedByteCount: formattedSize,
            samplePaths: preview.paths
        )
        objc_setAssociatedObject(alert, &bpCleanupPreviewHostAssocKey, host, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        alert.accessoryView = host.viewController.view
        return alert
    }

    @objc(cleanupPreviewHostForAlert:)
    public static func cleanupPreviewHost(for alert: NSAlert?) -> BPCleanupPreviewHost? {
        guard let alert else { return nil }
        return objc_getAssociatedObject(alert, &bpCleanupPreviewHostAssocKey) as? BPCleanupPreviewHost
    }

    @objc(brewfileInventoriesForInstalledFormulae:installedCasks:repositories:)
    public static func brewfileInventories(
        forInstalledFormulae formulae: [Any]?,
        installedCasks casks: [Any]?,
        repositories: [Any]?
    ) -> [String: [String]] {
        var inventories: [String: [String]] = [:]
        if let formulae {
            inventories["brew"] = formulae.compactMap { bpAsFormula($0)?.name }
        }
        if let casks {
            inventories["cask"] = casks.compactMap { bpAsFormula($0)?.name }
        }
        if let repositories {
            inventories["tap"] = repositories.compactMap { bpAsFormula($0)?.name }
        }
        return inventories
    }

    @objc(resolvedSelectionForFormulaNames:caskNames:outdatedFormulae:outdatedCasks:)
    public static func resolvedSelection(
        forFormulaNames formulaNames: [Any],
        caskNames: [Any],
        outdatedFormulae: [Any]?,
        outdatedCasks: [Any]?
    ) -> [Any] {
        var result: [Any] = []
        let formulaCls = bpFormulaClass()

        var formulaByName: [String: AnyObject] = [:]
        if let outdatedFormulae {
            for item in outdatedFormulae {
                if let f = bpAsFormula(item), let name = f.name, !name.isEmpty {
                    formulaByName[name] = item as AnyObject
                }
            }
        }
        for rawName in formulaNames {
            guard let name = rawName as? String, !name.isEmpty else { continue }
            if let matched = formulaByName[name] {
                result.append(matched)
            } else if let fallback = formulaCls?.formula(withName: name), let f = bpAsFormula(fallback) {
                f.cask = false
                result.append(fallback)
            }
        }

        var caskByName: [String: AnyObject] = [:]
        if let outdatedCasks {
            for item in outdatedCasks {
                if let c = bpAsFormula(item), let name = c.name, !name.isEmpty {
                    caskByName[name] = item as AnyObject
                }
            }
        }
        for rawName in caskNames {
            guard let name = rawName as? String, !name.isEmpty else { continue }
            if let matched = caskByName[name] {
                result.append(matched)
            } else if let fallback = formulaCls?.formula(withName: name), let c = bpAsFormula(fallback) {
                c.cask = true
                result.append(fallback)
            }
        }

        return result
    }
}

@objc(BPFormulaeDataSource)
public final class BPFormulaeDataSource: NSObject, NSTableViewDataSource {
    private static let columnIdentifierName = "Name"
    private static let columnIdentifierVersion = "Version"
    private static let columnIdentifierLatestVersion = "LatestVersion"
    private static let columnIdentifierStatus = "Status"

    @objc public var mode: Int = 0 {
        didSet {
            refreshBackingArray()
        }
    }

    @objc public var sortDescriptors: [NSSortDescriptor]? {
        didSet {
            refreshBackingArray()
        }
    }

    @objc public var formulaeArray: [Any]?

    public convenience override init() {
        self.init(mode: 0)
    }

    @objc(initWithMode:)
    public init(mode aMode: Int) {
        self.mode = aMode
        super.init()
        refreshBackingArray()
    }

    @objc(nameCellValueForFormula:pinned:)
    public static func nameCellValue(forFormula formula: Any?, pinned: Bool) -> Any {
        let name = bpAsFormula(formula)?.name ?? ""
        if !pinned || name.isEmpty {
            return name as NSString
        }

        let value = NSMutableAttributedString(string: name + " ")
        if let pin = NSImage(
            systemSymbolName: "pin.fill",
            accessibilityDescription: NSLocalizedString("Sidebar_Item_Pinned", comment: "")
        ) {
            let config = NSImage.SymbolConfiguration(pointSize: NSFont.smallSystemFontSize, weight: .regular)
            let attachment = NSTextAttachment()
            attachment.image = pin.withSymbolConfiguration(config) ?? pin
            value.append(NSAttributedString(attachment: attachment))
        }
        return value
    }

    public func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        self.sortDescriptors = tableView.sortDescriptors
        let descriptor = tableView.sortDescriptors.first
        BPPreferences.sortColumnIdentifier = descriptor?.key
        BPPreferences.sortAscending = descriptor?.ascending ?? true
        tableView.reloadData()
    }

    @objc public func refreshBackingArray() {
        guard let manager = bpSharedHomebrewManager() else {
            formulaeArray = []
            return
        }
        switch mode {
        case 0: // kBPListAll
            formulaeArray = manager.allFormulae
        case 1: // kBPListInstalled
            formulaeArray = manager.installedFormulae
        case 2: // kBPListLeaves
            formulaeArray = manager.leavesFormulae
        case 6: // kBPListPinned
            formulaeArray = manager.pinnedFormulae
        case 7: // kBPListInstalledCasks
            formulaeArray = manager.installedCasks
        case 8: // kBPListOutdatedCasks
            formulaeArray = manager.outdatedCasks
        case 9: // kBPListAllCasks
            formulaeArray = manager.allCasks
        case 3: // kBPListOutdated
            formulaeArray = manager.outdatedFormulae
        case 4: // kBPListSearch
            formulaeArray = manager.searchFormulae
        case 5: // kBPListRepositories
            formulaeArray = manager.repositoriesFormulae
        default:
            break
        }

        if let sortDescriptors, !sortDescriptors.isEmpty {
            formulaeArray = Self.formulae(formulaeArray, sortedBy: sortDescriptors)
        }
    }

    public func numberOfRows(in aTableView: NSTableView) -> Int {
        formulaeArray?.count ?? 0
    }

    @objc(formulaAtIndex:)
    public func formula(at index: Int) -> Any? {
        guard let array = formulaeArray, index >= 0, index < array.count else { return nil }
        return array[index]
    }

    @objc(indexOfFormulaNamed:)
    public func indexOfFormula(named name: String?) -> Int {
        indexOfFormula(named: name, cask: false)
    }

    @objc(indexOfFormulaNamed:cask:)
    public func indexOfFormula(named name: String?, cask: Bool) -> Int {
        guard let name, !name.isEmpty, let array = formulaeArray else { return -1 }
        for (idx, item) in array.enumerated() {
            if let f = bpAsFormula(item), f.cask == cask, f.name == name {
                return idx
            }
        }
        return -1
    }

    private static func compareFormula(_ lhsObj: Any, to rhsObj: Any, forKey key: String) -> ComparisonResult {
        guard let lhs = bpAsFormula(lhsObj), let rhs = bpAsFormula(rhsObj) else {
            return .orderedSame
        }
        if key == columnIdentifierName {
            return ((lhs.name ?? "") as NSString).localizedCaseInsensitiveCompare(rhs.name ?? "")
        }
        if key == columnIdentifierStatus {
            guard let manager = bpSharedHomebrewManager() else { return .orderedSame }
            let left = manager.status(forFormula: lhsObj as AnyObject)
            let right = manager.status(forFormula: rhsObj as AnyObject)
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        }

        let leftValue = (key == columnIdentifierLatestVersion ? lhs.shortLatestVersion : lhs.version) ?? ""
        let rightValue = (key == columnIdentifierLatestVersion ? rhs.shortLatestVersion : rhs.version) ?? ""
        if leftValue.isEmpty && rightValue.isEmpty { return .orderedSame }
        if leftValue.isEmpty { return .orderedAscending }
        if rightValue.isEmpty { return .orderedDescending }
        return (leftValue as NSString).localizedStandardCompare(rightValue)
    }

    @objc(formulae:sortedBy:)
    public static func formulae(_ formulae: [Any]?, sortedBy descriptors: [NSSortDescriptor]?) -> [Any] {
        guard let formulae else { return [] }
        guard let descriptor = descriptors?.first, let key = descriptor.key else {
            return formulae
        }
        let ascending = descriptor.ascending
        let positions = Array(0..<formulae.count)
        let ordered = positions.sorted { l, r in
            let cmp = compareFormula(formulae[l], to: formulae[r], forKey: key)
            if cmp == .orderedSame {
                return l < r
            }
            if ascending {
                return cmp == .orderedAscending
            } else {
                return cmp == .orderedDescending
            }
        }
        return ordered.map { formulae[$0] }
    }

    @objc(formulasAtIndexSet:)
    public func formulas(at indexSet: IndexSet) -> [Any]? {
        guard let array = formulaeArray,
              !indexSet.isEmpty,
              let last = indexSet.last,
              last < array.count else {
            return nil
        }
        return indexSet.map { array[$0] }
    }

    public func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let array = formulaeArray, row >= 0, row < array.count else { return "" }
        let columnIdentifier = tableColumn?.identifier.rawValue ?? ""
        let element = array[row]
        if columnIdentifier == Self.columnIdentifierName {
            if let f = bpAsFormula(element) {
                let pinned = bpSharedHomebrewManager()?.isFormulaPinned(element as AnyObject) ?? false
                return Self.nameCellValue(forFormula: f, pinned: pinned)
            }
            return element
        } else if columnIdentifier == Self.columnIdentifierVersion {
            if let f = bpAsFormula(element) {
                return f.version
            }
            return element
        } else if columnIdentifier == Self.columnIdentifierLatestVersion {
            if let f = bpAsFormula(element) {
                return f.shortLatestVersion
            }
            return element
        } else if columnIdentifier == Self.columnIdentifierStatus {
            if bpAsFormula(element) != nil {
                let status = bpSharedHomebrewManager()?.status(forFormula: element as AnyObject) ?? -1
                switch status {
                case 1: // kBPFormulaInstalled
                    return NSLocalizedString("Formula_Status_Installed", comment: "")
                case 0: // kBPFormulaNotInstalled
                    return NSLocalizedString("Formula_Status_Not_Installed", comment: "")
                case 2: // kBPFormulaOutdated
                    return NSLocalizedString("Formula_Status_Outdated", comment: "")
                default:
                    return ""
                }
            }
            return element
        }
        return ""
    }
}

@objc(BPSideBarControllerDelegate)
public protocol BPSideBarControllerDelegate: NSObjectProtocol {
    @objc func sourceListSelectionDidChange()
}

@objc(BPSidebarItem)
public final class BPSidebarItem: NSObject {
    @objc public var title: String?
    @objc public var identifier: String?
    @objc public var symbolName: String?
    @objc public var icon: NSImage?
    @objc public var badgeValue: NSNumber? = NSNumber(value: -1)
    @objc public private(set) var children: [BPSidebarItem] = []
    @objc public var accessibilityIdentifier: String?
    @objc public private(set) weak var parentItem: BPSidebarItem?

    @objc(itemWithTitle:identifier:)
    public static func item(withTitle title: String?, identifier: String?) -> BPSidebarItem {
        let item = BPSidebarItem()
        item.title = title
        item.identifier = identifier
        return item
    }

    @objc(addChildItem:)
    public func addChildItem(_ item: BPSidebarItem) {
        item.parentItem = self
        children.append(item)
    }

    @objc public func hasChildren() -> Bool {
        !children.isEmpty
    }
}

private func bpSpokenBadgeCount(_ badge: NSNumber) -> String {
    let format = NSLocalizedString("Sidebar_VoiceOver_Badge_Count", comment: "")
    if format.contains("%@") {
        return String(format: format, badge)
    }
    return badge.stringValue
}

private func bpSpokenSeparator() -> String {
    let separator = NSLocalizedString("Sidebar_VoiceOver_Separator", comment: "")
    return separator == "Sidebar_VoiceOver_Separator" ? ", " : separator
}

@MainActor
@objc(BPSidebarBadgeView)
public final class BPSidebarBadgeView: NSView {
    @objc public var badgeValue: UInt = 0 {
        didSet {
            if oldValue != badgeValue {
                invalidateIntrinsicContentSize()
                needsDisplay = true
            }
        }
    }

    @objc public var isEmphasized: Bool = false {
        didSet {
            if oldValue != isEmphasized {
                needsDisplay = true
            }
        }
    }

    @objc public var emphasized: Bool {
        get { isEmphasized }
        set { isEmphasized = newValue }
    }

    override public func isAccessibilityElement() -> Bool {
        true
    }

    override public func accessibilityRole() -> NSAccessibility.Role? {
        .staticText
    }

    override public func accessibilityValue() -> Any? {
        bpSpokenBadgeCount(NSNumber(value: badgeValue))
    }

    private var badgeText: String {
        "\(badgeValue)"
    }

    private func textAttributes(with color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .semibold),
            .foregroundColor: color
        ]
    }

    override public var intrinsicContentSize: NSSize {
        let textSize = (badgeText as NSString).size(withAttributes: textAttributes(with: .labelColor))
        return NSSize(width: ceil(textSize.width) + 14.0, height: 16.0)
    }

    override public func draw(_ dirtyRect: NSRect) {
        let backgroundColor: NSColor
        let borderColor: NSColor
        let textColor: NSColor
        if isEmphasized {
            backgroundColor = NSColor.white.withAlphaComponent(0.92)
            borderColor = NSColor.white.withAlphaComponent(0.98)
            textColor = NSColor.selectedContentBackgroundColor
        } else {
            backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.14)
            borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.24)
            textColor = NSColor.secondaryLabelColor
        }

        let pillHeight: CGFloat = 16.0
        let rawPill = NSRect(
            x: bounds.minX,
            y: bounds.midY - pillHeight / 2.0,
            width: bounds.width,
            height: pillHeight
        )
        let pill = rawPill.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(
            roundedRect: pill,
            xRadius: pill.height / 2.0,
            yRadius: pill.height / 2.0
        )
        backgroundColor.setFill()
        path.fill()
        path.lineWidth = 0.75
        borderColor.setStroke()
        path.stroke()

        let text = badgeText as NSString
        let attributes = textAttributes(with: textColor)
        let textSize = text.size(withAttributes: attributes)
        let origin = NSPoint(
            x: pill.midX - textSize.width / 2.0,
            y: pill.midY - textSize.height / 2.0
        )
        text.draw(at: origin, withAttributes: attributes)
    }
}

@MainActor
@objc(BPSidebarTableCellView)
public final class BPSidebarTableCellView: NSTableCellView {
    @objc public weak var badgeView: BPSidebarBadgeView?

    override public var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            badgeView?.isEmphasized = (backgroundStyle == .emphasized)
        }
    }
}

@MainActor
@objc(BPSideBarController)
public final class BPSideBarController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    @objc public weak var sidebar: NSOutlineView?
    @objc public private(set) var sidebarHost: BPSidebarHost
    @objc public weak var delegate: (any BPSideBarControllerDelegate)?

    @objc public var rootSidebarCategory: BPSidebarItem
    @objc public var installedFormulaeSidebarItem: BPSidebarItem
    @objc public var outdatedFormulaeSidebarItem: BPSidebarItem
    @objc public var allFormulaeSidebarItem: BPSidebarItem
    @objc public var leavesFormulaeSidebarItem: BPSidebarItem
    @objc public var pinnedFormulaeSidebarItem: BPSidebarItem
    @objc public var repositoriesFormulaeSidebarItem: BPSidebarItem
    @objc public var installedCasksSidebarItem: BPSidebarItem
    @objc public var outdatedCasksSidebarItem: BPSidebarItem
    @objc public var allCasksSidebarItem: BPSidebarItem
    @objc public var unifiedUpdatesSidebarItem: BPSidebarItem

    override public init() {
        let host = BPSidebarHost()
        self.sidebarHost = host
        self.rootSidebarCategory = BPSidebarItem.item(withTitle: "", identifier: "root")
        self.installedFormulaeSidebarItem = BPSidebarItem()
        self.outdatedFormulaeSidebarItem = BPSidebarItem()
        self.allFormulaeSidebarItem = BPSidebarItem()
        self.leavesFormulaeSidebarItem = BPSidebarItem()
        self.pinnedFormulaeSidebarItem = BPSidebarItem()
        self.repositoriesFormulaeSidebarItem = BPSidebarItem()
        self.installedCasksSidebarItem = BPSidebarItem()
        self.outdatedCasksSidebarItem = BPSidebarItem()
        self.allCasksSidebarItem = BPSidebarItem()
        self.unifiedUpdatesSidebarItem = BPSidebarItem()
        super.init()

        host.onSelectRow = { [weak self] rowIndex in
            guard let self else { return }
            if let sidebar = self.sidebar, sidebar.selectedRow != rowIndex {
                sidebar.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
            } else {
                self.delegate?.sourceListSelectionDidChange()
            }
        }
        buildSidebarTree()
        syncSidebarHost()
    }

    private func buildSidebarTree() {
        rootSidebarCategory = BPSidebarItem.item(withTitle: "", identifier: "root")

        let formulaeGroup = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Group_Formulae", comment: ""),
            identifier: "group"
        )
        rootSidebarCategory.addChildItem(formulaeGroup)

        installedFormulaeSidebarItem = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Item_Installed", comment: ""),
            identifier: "item"
        )
        installedFormulaeSidebarItem.symbolName = "checkmark.square"
        installedFormulaeSidebarItem.icon = NSImage(
            systemSymbolName: "checkmark.square",
            accessibilityDescription: NSLocalizedString("Sidebar_Item_Installed", comment: "")
        )
        installedFormulaeSidebarItem.accessibilityIdentifier = "sidebar.formulae.installed"
        formulaeGroup.addChildItem(installedFormulaeSidebarItem)

        outdatedFormulaeSidebarItem = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Item_Outdated", comment: ""),
            identifier: "item"
        )
        outdatedFormulaeSidebarItem.symbolName = "clock.arrow.circlepath"
        outdatedFormulaeSidebarItem.icon = NSImage(
            systemSymbolName: "clock.arrow.circlepath",
            accessibilityDescription: NSLocalizedString("Sidebar_Item_Outdated", comment: "")
        )
        outdatedFormulaeSidebarItem.accessibilityIdentifier = "sidebar.formulae.outdated"
        formulaeGroup.addChildItem(outdatedFormulaeSidebarItem)

        allFormulaeSidebarItem = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Item_All", comment: ""),
            identifier: "item"
        )
        allFormulaeSidebarItem.symbolName = "books.vertical"
        allFormulaeSidebarItem.icon = NSImage(
            systemSymbolName: "books.vertical",
            accessibilityDescription: NSLocalizedString("Sidebar_Item_All", comment: "")
        )
        allFormulaeSidebarItem.accessibilityIdentifier = "sidebar.formulae.all"
        formulaeGroup.addChildItem(allFormulaeSidebarItem)

        leavesFormulaeSidebarItem = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Item_Leaves", comment: ""),
            identifier: "item"
        )
        leavesFormulaeSidebarItem.symbolName = "leaf"
        leavesFormulaeSidebarItem.icon = NSImage(
            systemSymbolName: "leaf",
            accessibilityDescription: NSLocalizedString("Sidebar_Item_Leaves", comment: "")
        )
        leavesFormulaeSidebarItem.accessibilityIdentifier = "sidebar.formulae.leaves"
        formulaeGroup.addChildItem(leavesFormulaeSidebarItem)

        pinnedFormulaeSidebarItem = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Item_Pinned", comment: ""),
            identifier: "item"
        )
        pinnedFormulaeSidebarItem.symbolName = "pin"
        pinnedFormulaeSidebarItem.icon = NSImage(
            systemSymbolName: "pin",
            accessibilityDescription: NSLocalizedString("Sidebar_Item_Pinned", comment: "")
        )
        pinnedFormulaeSidebarItem.accessibilityIdentifier = "sidebar.formulae.pinned"
        formulaeGroup.addChildItem(pinnedFormulaeSidebarItem)

        repositoriesFormulaeSidebarItem = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Item_Repos", comment: ""),
            identifier: "item"
        )
        repositoriesFormulaeSidebarItem.symbolName = "building.columns"
        repositoriesFormulaeSidebarItem.icon = NSImage(
            systemSymbolName: "building.columns",
            accessibilityDescription: NSLocalizedString("Sidebar_Item_Repos", comment: "")
        )
        repositoriesFormulaeSidebarItem.accessibilityIdentifier = "sidebar.formulae.repositories"
        formulaeGroup.addChildItem(repositoriesFormulaeSidebarItem)

        let casksGroup = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Group_Casks", comment: ""),
            identifier: "group"
        )
        rootSidebarCategory.addChildItem(casksGroup)

        installedCasksSidebarItem = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Item_Installed", comment: ""),
            identifier: "item"
        )
        installedCasksSidebarItem.symbolName = "macwindow"
        installedCasksSidebarItem.icon = NSImage(
            systemSymbolName: "macwindow",
            accessibilityDescription: NSLocalizedString("Sidebar_Group_Casks", comment: "")
        )
        installedCasksSidebarItem.accessibilityIdentifier = "sidebar.casks.installed"
        casksGroup.addChildItem(installedCasksSidebarItem)

        outdatedCasksSidebarItem = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Item_Outdated", comment: ""),
            identifier: "item"
        )
        outdatedCasksSidebarItem.symbolName = "clock.arrow.circlepath"
        outdatedCasksSidebarItem.icon = NSImage(
            systemSymbolName: "clock.arrow.circlepath",
            accessibilityDescription: NSLocalizedString("Sidebar_Item_Outdated", comment: "")
        )
        outdatedCasksSidebarItem.accessibilityIdentifier = "sidebar.casks.outdated"
        casksGroup.addChildItem(outdatedCasksSidebarItem)

        allCasksSidebarItem = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Item_AllCasks", comment: ""),
            identifier: "item"
        )
        allCasksSidebarItem.symbolName = "square.stack.3d.up"
        allCasksSidebarItem.icon = NSImage(
            systemSymbolName: "square.stack.3d.up",
            accessibilityDescription: NSLocalizedString("Sidebar_Item_AllCasks", comment: "")
        )
        allCasksSidebarItem.accessibilityIdentifier = "sidebar.casks.all"
        casksGroup.addChildItem(allCasksSidebarItem)

        let toolsGroup = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Group_Tools", comment: ""),
            identifier: "group"
        )
        rootSidebarCategory.addChildItem(toolsGroup)

        let doctorItem = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Item_Doctor", comment: ""),
            identifier: "item"
        )
        doctorItem.badgeValue = NSNumber(value: -1)
        doctorItem.symbolName = "stethoscope"
        doctorItem.accessibilityIdentifier = "sidebar.tools.doctor"
        doctorItem.icon = NSImage(
            systemSymbolName: "stethoscope",
            accessibilityDescription: NSLocalizedString("Sidebar_Item_Doctor", comment: "")
        )
        toolsGroup.addChildItem(doctorItem)

        let updateItem = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Item_Update", comment: ""),
            identifier: "item"
        )
        updateItem.badgeValue = NSNumber(value: -1)
        updateItem.symbolName = "arrow.triangle.2.circlepath.circle"
        updateItem.accessibilityIdentifier = "sidebar.tools.update"
        updateItem.icon = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath.circle",
            accessibilityDescription: NSLocalizedString("Sidebar_Item_Update", comment: "")
        )
        toolsGroup.addChildItem(updateItem)

        let servicesItem = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Item_Services", comment: ""),
            identifier: "item"
        )
        servicesItem.badgeValue = NSNumber(value: -1)
        servicesItem.symbolName = "gearshape.2"
        servicesItem.accessibilityIdentifier = "sidebar.tools.services"
        servicesItem.icon = NSImage(
            systemSymbolName: "gearshape.2",
            accessibilityDescription: NSLocalizedString("Sidebar_Item_Services", comment: "")
        )
        toolsGroup.addChildItem(servicesItem)

        unifiedUpdatesSidebarItem = BPSidebarItem.item(
            withTitle: NSLocalizedString("Sidebar_Item_Unified_Updates", comment: ""),
            identifier: "item"
        )
        unifiedUpdatesSidebarItem.symbolName = "arrow.down.circle"
        unifiedUpdatesSidebarItem.accessibilityIdentifier = "sidebar.tools.updates"
        unifiedUpdatesSidebarItem.icon = NSImage(
            systemSymbolName: "arrow.down.circle",
            accessibilityDescription: NSLocalizedString("Sidebar_Item_Unified_Updates", comment: "")
        )
        toolsGroup.addChildItem(unifiedUpdatesSidebarItem)
    }

    @objc public func syncSidebarHost() {
        sidebarHost.removeAllSections()
        var currentRowIndex = 0
        for group in rootSidebarCategory.children {
            let groupRowIndex = currentRowIndex
            currentRowIndex += 1
            sidebarHost.addSection(rowIndex: groupRowIndex, title: group.title ?? "")
            for row in group.children {
                let itemRowIndex = currentRowIndex
                currentRowIndex += 1
                let axLabel = Self.accessibilityLabel(
                    forGroup: group.title,
                    title: row.title,
                    badge: row.badgeValue
                )
                sidebarHost.addRow(
                    toSectionAtRowIndex: groupRowIndex,
                    rowIndex: itemRowIndex,
                    title: row.title ?? "",
                    groupTitle: group.title ?? "",
                    symbolName: row.symbolName ?? "",
                    badgeCount: row.badgeValue?.intValue ?? -1,
                    accessibilityIdentifier: row.accessibilityIdentifier ?? "",
                    accessibilityLabel: axLabel
                )
            }
        }
    }

    @objc(restorableRowFrom:rowCount:)
    public static func restorableRow(from storedRow: Int, rowCount: Int) -> FormulaeSideBarItem {
        guard storedRow >= 0 && storedRow < rowCount,
              let item = FormulaeSideBarItem(rawValue: UInt(storedRow)) else {
            return .installed
        }
        switch item {
        case .formulaeCategory, .casksCategory, .toolsCategory:
            return .installed
        default:
            return item
        }
    }

    @objc(infoKeyForRow:)
    public static func infoKey(forRow row: Int) -> String? {
        BPFormulaeTableActions.sidebarInfoKey(forRow: row)
    }

    @objc public func configureSidebarSettings() {
        sidebar?.floatsGroupRows = false
        sidebar?.reloadData()
        sidebar?.expandItem(nil, expandChildren: true)
        let rowCount = sidebar?.numberOfRows ?? 16
        let row = Self.restorableRow(from: BPPreferences.lastSelectedSidebarRow, rowCount: rowCount)
        sidebar?.selectRowIndexes(IndexSet(integer: Int(row.rawValue)), byExtendingSelection: false)
        sidebar?.setAccessibilityLabel(NSLocalizedString("Sidebar_VoiceOver_Sidebar", comment: ""))
        sidebarHost.selectedRowIndex = Int(row.rawValue)
        syncSidebarHost()
    }

    @objc(accessibilityLabelForGroup:title:badge:)
    public static func accessibilityLabel(forGroup group: String?, title: String?, badge: NSNumber?) -> String {
        var parts: [String] = []
        if let group, !group.isEmpty {
            parts.append(group)
        }
        if let title, !title.isEmpty {
            parts.append(title)
        }
        if let badge, badge.intValue >= 0 {
            parts.append(bpSpokenBadgeCount(badge))
        }
        return parts.joined(separator: bpSpokenSeparator())
    }

    @objc public func selectableRowAccessibilityIdentifiers() -> [String] {
        var identifiers: [String] = []
        for group in rootSidebarCategory.children {
            for row in group.children {
                if let id = row.accessibilityIdentifier, !id.isEmpty {
                    identifiers.append(id)
                }
            }
        }
        return identifiers
    }

    @objc(itemForListMode:)
    public func item(forListMode mode: Int) -> BPSidebarItem? {
        switch mode {
        case 1: return installedFormulaeSidebarItem
        case 3: return outdatedFormulaeSidebarItem
        case 0: return allFormulaeSidebarItem
        case 2: return leavesFormulaeSidebarItem
        case 6: return pinnedFormulaeSidebarItem
        case 5: return repositoriesFormulaeSidebarItem
        case 7: return installedCasksSidebarItem
        case 8: return outdatedCasksSidebarItem
        case 9: return allCasksSidebarItem
        default: return nil
        }
    }

    @objc(refreshBadgeForListMode:)
    public func refreshBadge(forListMode mode: Int) {
        guard let item = item(forListMode: mode) else { return }
        refreshSidebarBadges()
        sidebar?.reloadItem(item)
        if mode == 3 || mode == 8 {
            sidebar?.reloadItem(unifiedUpdatesSidebarItem)
        }
    }

    @objc public func refreshSidebarBadges() {
        let manager = bpSharedHomebrewManager()
        let installedCount = manager?.installedFormulae?.count ?? 0
        let outdatedCount = manager?.outdatedFormulae?.count ?? 0
        let allCount = manager?.allFormulae?.count ?? 0
        let leavesCount = manager?.leavesFormulae?.count ?? 0
        let pinnedCount = manager?.pinnedFormulae?.count ?? 0
        let reposCount = manager?.repositoriesFormulae?.count ?? 0
        let installedCasksCount = manager?.installedCasks?.count ?? 0
        let outdatedCasksCount = manager?.outdatedCasks?.count ?? 0
        let allCasksCount = manager?.allCasks?.count ?? 0

        installedFormulaeSidebarItem.badgeValue = NSNumber(value: installedCount)
        outdatedFormulaeSidebarItem.badgeValue = NSNumber(value: outdatedCount)
        allFormulaeSidebarItem.badgeValue = NSNumber(value: allCount)
        leavesFormulaeSidebarItem.badgeValue = NSNumber(value: leavesCount)
        pinnedFormulaeSidebarItem.badgeValue = NSNumber(value: pinnedCount)
        repositoriesFormulaeSidebarItem.badgeValue = NSNumber(value: reposCount)
        installedCasksSidebarItem.badgeValue = NSNumber(value: installedCasksCount)
        outdatedCasksSidebarItem.badgeValue = NSNumber(value: outdatedCasksCount)
        allCasksSidebarItem.badgeValue = NSNumber(value: allCasksCount)
        unifiedUpdatesSidebarItem.badgeValue = NSNumber(value: outdatedCount + outdatedCasksCount)
        syncSidebarHost()
    }

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let sidebarItem = item as? BPSidebarItem {
            return sidebarItem.children.count
        }
        return rootSidebarCategory.children.count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let sidebarItem = item as? BPSidebarItem {
            return sidebarItem.children[index]
        }
        return rootSidebarCategory.children[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? BPSidebarItem)?.hasChildren() ?? false
    }

    public func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? BPSidebarItem)?.identifier == "group"
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        !self.outlineView(outlineView, isGroupItem: item)
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
        false
    }

    private func makeProgrammaticHeaderCellView() -> BPSidebarTableCellView {
        let headerView = BPSidebarTableCellView(frame: NSRect(x: 0, y: 0, width: 180, height: 20))
        headerView.identifier = NSUserInterfaceItemIdentifier("HeaderCell")
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11.0, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(label)
        headerView.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 4.0),
            label.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -4.0),
            label.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
        return headerView
    }

    private func makeProgrammaticMainCellView() -> BPSidebarTableCellView {
        let cellView = BPSidebarTableCellView(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        cellView.identifier = NSUserInterfaceItemIdentifier("MainCell")

        let iconView = NSImageView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(iconView)
        cellView.imageView = iconView

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(label)
        cellView.textField = label

        let badgeView = BPSidebarBadgeView(frame: NSRect(x: 0, y: 0, width: 28, height: 16))
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(badgeView)
        cellView.badgeView = badgeView

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4.0),
            iconView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16.0),
            iconView.heightAnchor.constraint(equalToConstant: 16.0),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6.0),
            label.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            badgeView.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 4.0),
            badgeView.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -6.0),
            badgeView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
        ])
        return cellView
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let sidebarItem = item as? BPSidebarItem else { return nil }
        if sidebarItem.identifier == "group" {
            let headerView = (outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("HeaderCell"), owner: self) as? BPSidebarTableCellView)
                ?? makeProgrammaticHeaderCellView()
            headerView.textField?.stringValue = sidebarItem.title ?? ""
            headerView.textField?.textColor = .secondaryLabelColor
            return headerView
        }

        let cellView = (outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("MainCell"), owner: self) as? BPSidebarTableCellView)
            ?? makeProgrammaticMainCellView()
        cellView.textField?.stringValue = sidebarItem.title ?? ""
        cellView.textField?.setAccessibilityIdentifier(sidebarItem.accessibilityIdentifier)
        cellView.textField?.setAccessibilityLabel(
            Self.accessibilityLabel(
                forGroup: sidebarItem.parentItem?.title,
                title: sidebarItem.title,
                badge: sidebarItem.badgeValue
            )
        )

        if let badge = sidebarItem.badgeValue, badge.intValue >= 0 {
            cellView.badgeView?.badgeValue = UInt(badge.intValue)
            cellView.badgeView?.isHidden = false
        } else {
            cellView.badgeView?.isHidden = true
        }

        if let icon = sidebarItem.icon {
            cellView.imageView?.image = icon
        }
        return cellView
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        if let sidebar, sidebar.selectedRow >= 0 {
            sidebarHost.selectedRowIndex = sidebar.selectedRow
        }
        delegate?.sourceListSelectionDidChange()
    }

    @objc(selectSideBarRowWithSenderTag:)
    public func selectSideBarRow(withSenderTag sender: Any?) {
        let tag = (sender as AnyObject?)?.tag ?? 0
        sidebarHost.selectedRowIndex = tag
        sidebar?.selectRowIndexes(IndexSet(integer: tag), byExtendingSelection: false)
    }
}

@MainActor
@objc(BPWindow)
public final class BPWindow: NSWindow {
    override public init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        sharedInit()
    }

    private func sharedInit() {
        styleMask.insert(.fullSizeContentView)
        titlebarAppearsTransparent = true
        toolbarStyle = .unified
        registerForDraggedTypes([.fileURL])
    }

    @objc public func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        brewfile(fromDrag: sender) != nil ? .copy : []
    }

    @objc public func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    @objc public func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let brewfile = brewfile(fromDrag: sender) else { return false }
        if let target = bpSharedAppDelegate()?.brewfileImportTarget {
            let importer = unsafeBitCast(target, to: BPBrewfileImportingObjCBridge.self)
            importer.importBrewfile(at: brewfile)
        }
        return true
    }

    @objc(brewfileFromDrag:)
    public func brewfile(fromDrag sender: any NSDraggingInfo) -> URL? {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return BPBrewfile.brewfileURLs(from: urls).first
    }
}

@MainActor
@objc(BPDoctorViewController)
public final class BPDoctorViewController: NSViewController {
    @objc public var doctorTextView: BPAutoScrollTextView?
    @objc public weak var progressIndicator: NSProgressIndicator?
    @objc public var isPerformingDoctor: Bool = false
    @objc public var consoleHost: BPConsoleToolHost?

    override public func loadView() {
        let textView = BPAutoScrollTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 232))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = BPStyle.defaultFixedWidthFont()
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        self.doctorTextView = textView
        self.isPerformingDoctor = false

        let title = Bundle.main.localizedString(
            forKey: "UHp-GH-2qP.title",
            value: NSLocalizedString("Homebrew Doctor", comment: ""),
            table: "BPDoctorView"
        )
        let runTitle = Bundle.main.localizedString(
            forKey: "YyI-zq-THZ.title",
            value: NSLocalizedString("Run Doctor", comment: ""),
            table: "BPDoctorView"
        )
        let clearTitle = Bundle.main.localizedString(
            forKey: "AlR-6d-ju7.title",
            value: NSLocalizedString("Clear Log", comment: ""),
            table: "BPDoctorView"
        )

        let host = BPConsoleToolHost(
            textView: textView,
            title: title,
            subtitle: nil,
            runButtonTitle: runTitle,
            clearButtonTitle: clearTitle
        )
        host.onRun = { [weak self] in
            self?.runStopDoctor(nil)
        }
        host.onClear = { [weak self] in
            self?.clearLogDoctor(nil)
        }
        self.consoleHost = host
        self.view = host.viewController.view
    }

    override public func awakeFromNib() {
        MainActor.assumeIsolated {
            progressIndicator?.setAccessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
            doctorTextView?.font = BPStyle.defaultFixedWidthFont()
            isPerformingDoctor = false
        }
    }

    override public var nibName: NSNib.Name? {
        "BPDoctorView"
    }

    @objc(runStopDoctor:)
    public func runStopDoctor(_ sender: Any?) {
        let appDelegate = bpSharedAppDelegate()
        if appDelegate?.isRunningBackgroundTask == true {
            appDelegate?.displayBackgroundWarning()
            return
        }
        appDelegate?.isRunningBackgroundTask = true

        doctorTextView?.clearOutput()
        isPerformingDoctor = true
        consoleHost?.isRunning = true
        consoleHost?.syncLogFromTextView()
        progressIndicator?.startAnimation(sender)

        let textView = self.doctorTextView
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = bpSharedHomebrewInterface()?.runDoctor { output in
                textView?.appendOutput(output)
                DispatchQueue.main.async {
                    self?.consoleHost?.syncLogFromTextView()
                }
            }
            DispatchQueue.main.async {
                textView?.flushPendingOutput()
                self?.progressIndicator?.stopAnimation(nil)
                self?.isPerformingDoctor = false
                self?.consoleHost?.isRunning = false
                self?.consoleHost?.syncLogFromTextView()
                bpSharedAppDelegate()?.isRunningBackgroundTask = false

                let title = NSLocalizedString("Homebrew_Task_Finished", comment: "")
                let desc = NSLocalizedString("Notification_Doctor", comment: "")
                bpSharedAppDelegate()?.requestUserAttention(withMessageTitle: title, andDescription: desc)
            }
        }
    }

    @objc(clearLogDoctor:)
    public func clearLogDoctor(_ sender: Any?) {
        doctorTextView?.clearOutput()
        doctorTextView?.string = ""
        consoleHost?.syncLogFromTextView()
    }
}

@MainActor
@objc(BPUpdateViewController)
public final class BPUpdateViewController: NSViewController {
    @objc public var updateTextView: BPAutoScrollTextView?
    @objc public weak var progressIndicator: NSProgressIndicator?
    @objc public var isPerformingUpdate: Bool = false
    @objc public var consoleHost: BPConsoleToolHost?

    override public func loadView() {
        let textView = BPAutoScrollTextView(frame: NSRect(x: 0, y: 0, width: 404, height: 232))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = BPStyle.defaultFixedWidthFont()
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        self.updateTextView = textView
        self.isPerformingUpdate = false

        let title = Bundle.main.localizedString(
            forKey: "a3Y-VX-bpV.title",
            value: NSLocalizedString("Homebrew Updater", comment: ""),
            table: "BPUpdateView"
        )
        let runTitle = Bundle.main.localizedString(
            forKey: "MVF-cn-lfW.title",
            value: NSLocalizedString("Update Homebrew", comment: ""),
            table: "BPUpdateView"
        )
        let clearTitle = Bundle.main.localizedString(
            forKey: "EE6-5g-Jos.title",
            value: NSLocalizedString("Clear Log", comment: ""),
            table: "BPUpdateView"
        )

        let host = BPConsoleToolHost(
            textView: textView,
            title: title,
            subtitle: nil,
            runButtonTitle: runTitle,
            clearButtonTitle: clearTitle
        )
        host.onRun = { [weak self] in
            self?.runStopUpdate(nil)
        }
        host.onClear = { [weak self] in
            self?.clearLogUpdate(nil)
        }
        self.consoleHost = host
        self.view = host.viewController.view
    }

    override public func awakeFromNib() {
        MainActor.assumeIsolated {
            progressIndicator?.setAccessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
            updateTextView?.font = BPStyle.defaultFixedWidthFont()
            isPerformingUpdate = false
        }
    }

    override public var nibName: NSNib.Name? {
        "BPUpdateView"
    }

    @objc(runStopUpdate:)
    public func runStopUpdate(_ sender: Any?) {
        let appDelegate = bpSharedAppDelegate()
        if appDelegate?.isRunningBackgroundTask == true {
            appDelegate?.displayBackgroundWarning()
            return
        }
        appDelegate?.isRunningBackgroundTask = true

        updateTextView?.clearOutput()
        isPerformingUpdate = true
        consoleHost?.isRunning = true
        consoleHost?.syncLogFromTextView()
        progressIndicator?.startAnimation(sender)

        let textView = self.updateTextView
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = bpSharedHomebrewInterface()?.update { output in
                textView?.appendOutput(output)
                DispatchQueue.main.async {
                    self?.consoleHost?.syncLogFromTextView()
                }
            }
            DispatchQueue.main.async {
                textView?.flushPendingOutput()
                self?.progressIndicator?.stopAnimation(nil)
                self?.isPerformingUpdate = false
                self?.consoleHost?.isRunning = false
                self?.consoleHost?.syncLogFromTextView()
                bpSharedAppDelegate()?.isRunningBackgroundTask = false

                let title = NSLocalizedString("Homebrew_Task_Finished", comment: "")
                let desc = NSLocalizedString("Notification_Update", comment: "")
                bpSharedAppDelegate()?.requestUserAttention(withMessageTitle: title, andDescription: desc)
            }
        }
    }

    @objc(clearLogUpdate:)
    public func clearLogUpdate(_ sender: Any?) {
        updateTextView?.clearOutput()
        updateTextView?.string = ""
        consoleHost?.syncLogFromTextView()
    }
}

@objc private protocol BPInformationHostMessaging: NSObjectProtocol {
    var viewController: NSViewController { get }
    @objc(beginWithName:cask:infoType:)
    func begin(withName name: String?, cask: Bool, infoType: Int) -> UInt64
    @objc(receiveInformation:website:name:cask:infoType:generation:)
    func receiveInformation(
        _ information: String?,
        website: URL?,
        name: String?,
        cask: Bool,
        infoType: Int,
        generation: UInt64
    )
    @objc(close)
    func close()
}

@objc private protocol BPPopoverMessaging: NSObjectProtocol {
    var contentViewController: NSViewController? { get set }
    var behavior: NSPopover.Behavior { get set }
}

@MainActor
@objc(BPFormulaPopoverViewController)
public final class BPFormulaPopoverViewController: NSViewController {
    @objc public var formulaTextView: NSTextView?
    @objc public weak var formulaTitleLabel: NSTextField?
    @objc public weak var formulaPopover: NSPopover?
    @objc public weak var progressIndicator: NSProgressIndicator?
    @objc public var timedDispatch: BPTimedDispatch?
    @objc public var informationHost: AnyObject?
    @objc public var retainedPopover: NSPopover?
    @objc public var dependentsProvider: (@Sendable (String, Bool) -> String?)?

    @objc public var infoType: BPFormulaInfoType = .general {
        didSet {
            activeInformationHost?.close()
            popoverBridge?.behavior = (infoType == .general) ? .transient : .semitransient
        }
    }

    @objc(formulaObject) public weak var formula: AnyObject? {
        didSet {
            handleFormulaChanged()
        }
    }

    private var activeInformationHost: BPInformationHostMessaging? {
        guard let host = informationHost else { return nil }
        return unsafeBitCast(host, to: BPInformationHostMessaging.self)
    }

    private var popoverBridge: BPPopoverMessaging? {
        guard let pop = formulaPopover as AnyObject? else { return nil }
        return unsafeBitCast(pop, to: BPPopoverMessaging.self)
    }

    override public func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 320))
        if formulaPopover == nil {
            let pop = NSPopover()
            retainedPopover = pop
            formulaPopover = pop
        }
        awakeFromNib()
    }

    override public func awakeFromNib() {
        MainActor.assumeIsolated {
            formulaTextView?.font = BPStyle.defaultFixedWidthFont()
            formulaTextView?.textColor = BPStyle.popoverTextViewColor()
            popoverBridge?.contentViewController = self
            timedDispatch = BPTimedDispatch()
            formulaTitleLabel?.textColor = BPStyle.popoverTitleColor()
            infoType = .general
            NotificationCenter.default.removeObserver(self, name: NSPopover.willCloseNotification, object: nil)
            if let pop = formulaPopover {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(informationPopoverWillClose(_:)),
                    name: NSPopover.willCloseNotification,
                    object: pop
                )
            }
        }
    }

    @objc(informationPopoverWillClose:)
    public func informationPopoverWillClose(_ notification: Notification) {
        activeInformationHost?.close()
    }

    private func handleFormulaChanged() {
        activeInformationHost?.close()
        formulaTextView?.string = ""
        progressIndicator?.stopAnimation(nil)
        guard let formulaObj = formula, let f = bpAsFormula(formulaObj) else { return }

        if informationHost == nil {
            informationHost = BPFormulaInformationHost()
        }
        guard let host = activeInformationHost else { return }
        let name = f.name ?? ""
        let cask = f.cask
        let currentInfoType = self.infoType
        let generation = host.begin(withName: name, cask: cask, infoType: currentInfoType.rawValue)
        popoverBridge?.contentViewController = host.viewController

        if currentInfoType != .general {
            if cask {
                host.receiveInformation(
                    nil,
                    website: nil,
                    name: name,
                    cask: cask,
                    infoType: currentInfoType.rawValue,
                    generation: generation
                )
                return
            }
            let onlyInstalled = (currentInfoType == .installedDependents)
            let provider = self.dependentsProvider
            timedDispatch?.scheduleDispatch(
                afterTimeInterval: 0.0,
                in: DispatchQueue.global(qos: .background)
            ) { [weak self] in
                let dependents = provider != nil
                    ? provider?(name, onlyInstalled)
                    : bpSharedHomebrewInterface()?.dependants(forFormulaName: name, onlyInstalled: onlyInstalled)
                DispatchQueue.main.async {
                    self?.activeInformationHost?.receiveInformation(
                        dependents,
                        website: nil,
                        name: name,
                        cask: cask,
                        infoType: currentInfoType.rawValue,
                        generation: generation
                    )
                }
            }
            return
        }

        if let info = f.information {
            host.receiveInformation(
                info,
                website: f.website,
                name: name,
                cask: cask,
                infoType: currentInfoType.rawValue,
                generation: generation
            )
            return
        }

        nonisolated(unsafe) let unsafeFormula = f
        timedDispatch?.scheduleDispatch(
            afterTimeInterval: 0.3,
            in: DispatchQueue.global(qos: .background)
        ) { [weak self] in
            unsafeFormula.needsInformation = true
            let information = unsafeFormula.information
            let website = unsafeFormula.website
            DispatchQueue.main.async {
                self?.activeInformationHost?.receiveInformation(
                    information,
                    website: website,
                    name: name,
                    cask: cask,
                    infoType: currentInfoType.rawValue,
                    generation: generation
                )
            }
        }
    }

    override public var nibName: NSNib.Name? {
        "BPFormulaPopoverView"
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

@objc(BPSelectedFormulaViewControllerDelegate)
public protocol BPSelectedFormulaViewControllerDelegate: NSObjectProtocol {
    @objc(selectedFormulaViewDidUpdateFormulaInfoForFormula:)
    func selectedFormulaViewDidUpdateFormulaInfo(forFormula formula: Any?)
    @objc optional func selectedFormulaViewDidRequestSelectRelatedFormulaNamed(_ formulaName: String)
    @objc optional func selectedFormulaViewDidRequestShowMoreInformation()
    @objc optional func selectedFormulaViewDidRequestOpenWebsite()
}

@objc private protocol BPSelectedFormulaHostMessaging: NSObjectProtocol {
    var viewController: NSViewController { get }
    @objc func clearSelection()
    @objc func showMultipleSelection()
    @objc(beginSelectionWithName:cask:installed:pinned:installPath:latestVersion:dependencies:conflicts:shortDescription:)
    func beginSelection(
        withName name: String,
        cask: Bool,
        installed: Bool,
        pinned: Bool,
        installPath: String?,
        latestVersion: String?,
        dependencies: String?,
        conflicts: String?,
        shortDescription: String?
    ) -> UInt64
    @objc(updateSelectionWithName:cask:installed:pinned:installPath:latestVersion:dependencies:conflicts:shortDescription:)
    func updateSelection(
        withName name: String,
        cask: Bool,
        installed: Bool,
        pinned: Bool,
        installPath: String?,
        latestVersion: String?,
        dependencies: String?,
        conflicts: String?,
        shortDescription: String?
    )
    @objc(receiveDependents:name:cask:generation:)
    func receiveDependents(_ dependents: [String], name: String, cask: Bool, generation: UInt64)
}

@MainActor
@objc(BPSelectedFormulaViewController)
public final class BPSelectedFormulaViewController: NSViewController {
    private static let formulaDidUpdateNotification = Notification.Name("BPFormulaDidUpdateNotification")

    @objc public private(set) var inspectorHost: BPSelectedFormulaHost?
    private var customInspectorHost: AnyObject?
    @objc public var timedDispatch: BPTimedDispatch?

    @objc public weak var delegate: (any BPSelectedFormulaViewControllerDelegate)?
    @objc public var dependentsProvider: (@Sendable (String, Bool) -> String?)?

    @objc public weak var formulaDescriptionLabel: NSTextField?
    @objc public weak var formulaPathLabel: NSTextField?
    @objc public weak var formulaVersionLabel: NSTextField?
    @objc public weak var formulaDependenciesLabel: NSTextField?
    @objc public weak var formulaConflictsLabel: NSTextField?
    @objc public weak var formulaDependentsLabel: NSTextField?
    @objc public weak var pinnedInfoRow: NSView?

    private var activeInspectorHost: BPSelectedFormulaHostMessaging? {
        guard let target = (customInspectorHost ?? inspectorHost) else { return nil }
        return unsafeBitCast(target, to: BPSelectedFormulaHostMessaging.self)
    }

    override public func setValue(_ value: Any?, forKey key: String) {
        if key == "inspectorHost" {
            nonisolated(unsafe) let unsafeValue = value
            MainActor.assumeIsolated {
                if let host = unsafeValue as? BPSelectedFormulaHost {
                    inspectorHost = host
                    customInspectorHost = nil
                } else {
                    customInspectorHost = unsafeValue as AnyObject?
                }
                configureInspectorHostCallbacks()
            }
            return
        }
        super.setValue(value, forKey: key)
    }

    override public init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        self.timedDispatch = BPTimedDispatch()
        self.inspectorHost = BPSelectedFormulaHost()
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        configureInspectorHostCallbacks()
    }

    required public init?(coder: NSCoder) {
        self.timedDispatch = BPTimedDispatch()
        self.inspectorHost = BPSelectedFormulaHost()
        super.init(coder: coder)
        configureInspectorHostCallbacks()
    }

    private func configureInspectorHostCallbacks() {
        guard let host = inspectorHost, customInspectorHost == nil else { return }
        host.onSelectRelatedPackage = { [weak self] packageName in
            guard let self, !packageName.isEmpty else { return }
            self.delegate?.selectedFormulaViewDidRequestSelectRelatedFormulaNamed?(packageName)
        }
        host.onShowMoreInfo = { [weak self] in
            guard let self else { return }
            self.delegate?.selectedFormulaViewDidRequestShowMoreInformation?()
        }
        host.onOpenWebsite = { [weak self] in
            guard let self else { return }
            self.delegate?.selectedFormulaViewDidRequestOpenWebsite?()
        }
    }

    override public func loadView() {
        if timedDispatch == nil {
            timedDispatch = BPTimedDispatch()
        }
        if inspectorHost == nil && customInspectorHost == nil {
            inspectorHost = BPSelectedFormulaHost()
        }
        configureInspectorHostCallbacks()
        if let view = activeInspectorHost?.viewController.view {
            self.view = view
        } else {
            self.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        }
    }

    @objc public var formulae: [Any]? {
        willSet {
            if let old = formulae {
                for item in old {
                    NotificationCenter.default.removeObserver(
                        self,
                        name: Self.formulaDidUpdateNotification,
                        object: item as AnyObject
                    )
                }
            }
        }
        didSet {
            if let current = formulae {
                for item in current {
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(updateFormulaInformation(_:)),
                        name: Self.formulaDidUpdateNotification,
                        object: item as AnyObject
                    )
                }
            }
            handleFormulaeUpdated()
        }
    }

    private func handleFormulaeUpdated() {
        if inspectorHost == nil && customInspectorHost == nil {
            inspectorHost = BPSelectedFormulaHost()
            configureInspectorHostCallbacks()
        }
        if timedDispatch == nil {
            timedDispatch = BPTimedDispatch()
        }
        guard let formulae, !formulae.isEmpty else {
            activeInspectorHost?.clearSelection()
            return
        }
        if formulae.count > 1 {
            activeInspectorHost?.showMultipleSelection()
            return
        }
        guard let firstObj = formulae.first, let formula = bpAsFormula(firstObj) else {
            activeInspectorHost?.clearSelection()
            return
        }

        let name = formula.name ?? ""
        let cask = formula.cask
        let pinned = !cask && (bpSharedHomebrewManager()?.isFormulaPinned(firstObj as AnyObject) ?? false)
        let generation = activeInspectorHost?.beginSelection(
            withName: name,
            cask: cask,
            installed: formula.isInstalled(),
            pinned: pinned,
            installPath: formula.installPath,
            latestVersion: formula.latestVersion,
            dependencies: formula.dependencies,
            conflicts: formula.conflicts,
            shortDescription: formula.shortDescription
        ) ?? 0

        delegate?.selectedFormulaViewDidUpdateFormulaInfo(forFormula: firstObj)

        let provider = self.dependentsProvider
        nonisolated(unsafe) let unsafeFormula = formula
        timedDispatch?.scheduleDispatch(
            afterTimeInterval: 0.3,
            in: DispatchQueue.global(qos: .background)
        ) { [weak self] in
            unsafeFormula.needsInformation = true
            if cask { return }
            let raw = provider != nil
                ? provider?(name, true)
                : bpSharedHomebrewInterface()?.dependants(forFormulaName: name, onlyInstalled: true)
            let dependents = bpFormulaClass()?.names(fromListOutput: raw) ?? []
            DispatchQueue.main.async {
                self?.activeInspectorHost?.receiveDependents(
                    dependents,
                    name: name,
                    cask: cask,
                    generation: generation
                )
            }
        }
    }

    @objc(updateFormulaInformation:)
    public nonisolated func updateFormulaInformation(_ notification: Notification) {
        let updatedObj = notification.object
        nonisolated(unsafe) let unsafeUpdated = updatedObj
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let formulae = self.formulae, formulae.count == 1,
                      let firstObj = formulae.first, let formula = bpAsFormula(firstObj) else {
                    return
                }
                if let updated = bpAsFormula(unsafeUpdated),
                   (updated.cask != formula.cask || updated.name != formula.name) {
                    return
                }
                let pinned = !formula.cask && (bpSharedHomebrewManager()?.isFormulaPinned(firstObj as AnyObject) ?? false)
                self.activeInspectorHost?.updateSelection(
                    withName: formula.name ?? "",
                    cask: formula.cask,
                    installed: formula.isInstalled(),
                    pinned: pinned,
                    installPath: formula.installPath,
                    latestVersion: formula.latestVersion,
                    dependencies: formula.dependencies,
                    conflicts: formula.conflicts,
                    shortDescription: formula.shortDescription
                )
                self.delegate?.selectedFormulaViewDidUpdateFormulaInfo(forFormula: firstObj)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

@MainActor
@objc(BPFormulaOptionsWindowController)
public final class BPFormulaOptionsWindowController: NSWindowController, NSTableViewDelegate {
    private static let optionCommandKey = "formulaOptionCommand"
    private static let optionAppliedKey = "isFormulaOptionCommandApplied"
    private static let optionDescriptionKey = "formulaOptionDescription"

    @objc public weak var userHelpLabel: NSTextField?
    @objc public weak var formulaNameLabel: NSTextField?
    @objc public weak var optionDetailsTextField: NSTextField?
    @objc public weak var formulaOptionsTableView: NSTableView?
    @objc public var formulasArrayController: NSArrayController?

    @objc public var availableOptions: NSMutableArray = NSMutableArray()
    @objc public var formula: AnyObject?
    @objc public var optionsHost: BPFormulaOptionsHost?
    @objc public var installWithOptionsBlock: (([Any]) -> Void)?

    override public func loadWindow() {
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        awakeFromNib()
    }

    override public func awakeFromNib() {
        MainActor.assumeIsolated {
            var names: [String] = []
            var explanations: [String] = []
            for case let dict as NSDictionary in availableOptions {
                names.append((dict[Self.optionCommandKey] as? String) ?? "")
                explanations.append((dict[Self.optionDescriptionKey] as? String) ?? "")
            }

            let host = BPFormulaOptionsHost()
            let formulaName = bpAsFormula(formula)?.name ?? ""
            host.configure(formulaName: formulaName, optionNames: names, optionExplanations: explanations)
            host.onOptionToggled = { [weak self] optionName, applied in
                guard let self else { return }
                for case let entry as NSMutableDictionary in self.availableOptions {
                    if (entry[Self.optionCommandKey] as? String) == optionName {
                        entry[Self.optionAppliedKey] = NSNumber(value: applied)
                    }
                }
            }
            host.onCancel = { [weak self] in
                self?.cancel(nil)
            }
            host.onInstall = { [weak self] in
                self?.install(nil)
            }
            self.optionsHost = host

            if let contentView = window?.contentView {
                for subview in contentView.subviews {
                    subview.removeFromSuperview()
                }
                let hostView = host.viewController.view
                hostView.translatesAutoresizingMaskIntoConstraints = false
                contentView.addSubview(hostView)
                NSLayoutConstraint.activate([
                    hostView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    hostView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                    hostView.topAnchor.constraint(equalTo: contentView.topAnchor),
                    hostView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
                ])
            }
        }
    }

    @objc(runFormula:withCompletionBlock:)
    public static func runFormula(
        _ formula: Any?,
        withCompletionBlock completionBlock: (([Any]) -> Void)?
    ) -> BPFormulaOptionsWindowController {
        let controller = BPFormulaOptionsWindowController(windowNibName: "BPFormulaOptionsWindow")
        controller.formula = formula as AnyObject?
        controller.installWithOptionsBlock = completionBlock
        let available = NSMutableArray()
        if let options = bpAsFormula(formula)?.options {
            for case let option as BPFormulaOption in options {
                if let optionCommand = option.name {
                    let optionDescription = option.explanation ?? ""
                    let dict = NSMutableDictionary(dictionary: [
                        optionCommandKey: optionCommand,
                        optionAppliedKey: NSNumber(value: false),
                        optionDescriptionKey: optionDescription
                    ])
                    available.add(dict)
                }
            }
        }
        controller.availableOptions = available

        if let formulaWindow = controller.window {
            bpSharedAppDelegate()?.isRunningBackgroundTask = true
            NSApplication.shared.mainWindow?.beginSheet(formulaWindow) { returnCode in
                if returnCode == .stop {
                    let selected = controller.allSelectedOptions()
                    controller.installWithOptionsBlock?(selected)
                } else {
                    bpSharedAppDelegate()?.isRunningBackgroundTask = false
                }
            }
        }
        return controller
    }

    @objc public func allSelectedOptions() -> [Any] {
        if let host = optionsHost {
            return host.selectedOptionNames
        }
        var selected: [String] = []
        for case let entry as NSDictionary in availableOptions {
            if (entry[Self.optionAppliedKey] as? NSNumber)?.boolValue == true,
               let cmd = entry[Self.optionCommandKey] as? String {
                selected.append(cmd)
            }
        }
        return selected
    }

    @objc(cancel:)
    public func cancel(_ sender: Any?) {
        guard let window = self.window else { return }
        if let mainWindow = NSApplication.shared.mainWindow {
            mainWindow.endSheet(window, returnCode: .abort)
        } else {
            window.sheetParent?.endSheet(window, returnCode: .abort)
        }
    }

    @objc(install:)
    public func install(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Generic_Attention", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Generic_Yes", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Generic_Cancel", comment: ""))
        let formulaName = bpAsFormula(formula)?.name ?? ""
        alert.informativeText = String(
            format: NSLocalizedString("Formula_Options_Confirmation", comment: ""),
            formulaName
        )
        alert.window.title = NSLocalizedString("Cakebrew", comment: "")

        let returnValue = alert.runModal()
        let modalResponse: NSApplication.ModalResponse = (returnValue == .alertFirstButtonReturn) ? .stop : .abort
        guard let window = self.window else { return }
        if let mainWindow = NSApplication.shared.mainWindow {
            mainWindow.endSheet(window, returnCode: modalResponse)
        } else {
            window.sheetParent?.endSheet(window, returnCode: modalResponse)
        }
    }
}

@MainActor
@objc(BPPreferencesWindowController)
public final class BPPreferencesWindowController: NSWindowController {
    @objc public var backgroundCheckCheckbox: NSButton?
    @objc public var intervalPopUp: NSPopUpButton?
    @objc public var greedyCheckbox: NSButton?
    @objc public var helperStatusLabel: NSTextField?
    @objc public var helperActionButton: NSButton?
    @objc public var preferencesHost: BPPreferencesHost?

    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = NSLocalizedString("Preferences_Title", comment: "")
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildContentView()
    }

    private func buildContentView() {
        guard let content = window?.contentView else { return }

        let bgCheckbox = NSButton(
            checkboxWithTitle: NSLocalizedString("Preferences_Background_Check", comment: ""),
            target: self,
            action: #selector(toggleBackgroundCheck(_:))
        )
        bgCheckbox.state = BPPreferences.backgroundCheckEnabled ? .on : .off
        self.backgroundCheckCheckbox = bgCheckbox

        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        let intervals: [(String, Double)] = [
            (NSLocalizedString("Preferences_Interval_Hourly", comment: ""), 3600.0),
            (NSLocalizedString("Preferences_Interval_Six_Hours", comment: ""), 21600.0),
            (NSLocalizedString("Preferences_Interval_Daily", comment: ""), 86400.0)
        ]
        for (title, seconds) in intervals {
            popUp.addItem(withTitle: title)
            popUp.lastItem?.representedObject = NSNumber(value: seconds)
        }
        self.intervalPopUp = popUp
        selectIntervalItemMatchingPreference()
        popUp.target = self
        popUp.action = #selector(intervalChanged(_:))

        let greedy = NSButton(
            checkboxWithTitle: NSLocalizedString("Preferences_Greedy_Casks", comment: ""),
            target: self,
            action: #selector(toggleGreedy(_:))
        )
        greedy.state = BPPreferences.greedyCaskUpgrades ? .on : .off
        self.greedyCheckbox = greedy

        self.helperStatusLabel = NSTextField(wrappingLabelWithString: "")
        let actionBtn = NSButton(title: "", target: self, action: #selector(helperAction(_:)))
        actionBtn.bezelStyle = .rounded
        self.helperActionButton = actionBtn

        let host = BPPreferencesHost()
        host.onBackgroundCheckChanged = { [weak self] enabled in
            guard let self else { return }
            self.backgroundCheckCheckbox?.state = enabled ? .on : .off
            BPPreferences.backgroundCheckEnabled = enabled
            self.updateIntervalEnabled()
            self.syncSwiftUIHost()
        }
        host.onIntervalChanged = { [weak self] interval in
            guard let self else { return }
            BPPreferences.backgroundCheckInterval = interval
            self.selectIntervalItemMatchingPreference()
            self.syncSwiftUIHost()
        }
        host.onGreedyChanged = { [weak self] greedy in
            guard let self else { return }
            self.greedyCheckbox?.state = greedy ? .on : .off
            BPPreferences.greedyCaskUpgrades = greedy
            self.syncSwiftUIHost()
        }
        host.onAutomaticAppUpdateCheckChanged = { [weak self] enabled in
            guard let self else { return }
            BPPreferences.automaticAppUpdateCheckEnabled = enabled
            self.syncSwiftUIHost()
        }
        host.onShowMenuBarExtraChanged = { [weak self] enabled in
            guard let self else { return }
            BPPreferences.showMenuBarExtra = enabled
            bpSharedAppDelegate()?.updateMenuBarExtra()
            self.syncSwiftUIHost()
        }
        host.onCheckForAppUpdates = {
            bpSharedAppDelegate()?.checkForAppUpdates(nil)
        }
        host.onHelperAction = { [weak self] in
            self?.helperAction(nil)
        }
        self.preferencesHost = host

        let hostView = host.viewController.view
        hostView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hostView)
        NSLayoutConstraint.activate([
            hostView.topAnchor.constraint(equalTo: content.topAnchor),
            hostView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            hostView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        updateIntervalEnabled()
        refreshHelperStatus()
    }

    @objc public func syncSwiftUIHost() {
        guard let host = preferencesHost else { return }
        let actionTitle = (helperActionButton?.isHidden == true) ? nil : helperActionButton?.title
        host.showMenuBarExtra = BPPreferences.showMenuBarExtra
        host.sync(
            backgroundCheckEnabled: BPPreferences.backgroundCheckEnabled,
            interval: BPPreferences.backgroundCheckInterval,
            greedy: BPPreferences.greedyCaskUpgrades,
            automaticAppUpdates: BPPreferences.automaticAppUpdateCheckEnabled,
            helperStatus: helperStatusLabel?.stringValue ?? "",
            helperActionTitle: actionTitle
        )
    }

    private func selectIntervalItemMatchingPreference() {
        guard let popUp = intervalPopUp else { return }
        let current = BPPreferences.backgroundCheckInterval
        for item in popUp.itemArray {
            if (item.representedObject as? NSNumber)?.doubleValue == current {
                popUp.select(item)
                return
            }
        }
        if popUp.numberOfItems > 1 {
            popUp.selectItem(at: 1)
        }
    }

    private func updateIntervalEnabled() {
        intervalPopUp?.isEnabled = (backgroundCheckCheckbox?.state == .on)
    }

    @objc public func refreshHelperStatus() {
        let state = bpSharedHelperRegistration()?.currentState() ?? 0
        helperStatusLabel?.stringValue = bpHelperRegistrationClass()?.localizedDescription(forState: state) ?? ""
        let offersLoginItems = bpHelperRegistrationClass()?.stateOffersLoginItemsShortcut(state) ?? false
        let offersInstall = (state == 0) // kBPHelperStateNotRegistered
        helperActionButton?.isHidden = !(offersLoginItems || offersInstall)
        helperActionButton?.title = offersLoginItems
            ? NSLocalizedString("Helper_Action_Open_Login_Items", comment: "")
            : NSLocalizedString("Helper_Action_Install", comment: "")
        syncSwiftUIHost()
    }

    @objc(helperAction:)
    public func helperAction(_ sender: Any?) {
        let state = bpSharedHelperRegistration()?.currentState() ?? 0
        if bpHelperRegistrationClass()?.stateOffersLoginItemsShortcut(state) == true {
            bpHelperRegistrationClass()?.openLoginItemsSettings()
        } else {
            var error: NSError?
            _ = bpSharedHelperRegistration()?.registerReturningError(&error)
        }
        refreshHelperStatus()
    }

    @objc(toggleBackgroundCheck:)
    public func toggleBackgroundCheck(_ sender: Any?) {
        BPPreferences.backgroundCheckEnabled = (backgroundCheckCheckbox?.state == .on)
        updateIntervalEnabled()
        syncSwiftUIHost()
    }

    @objc(intervalChanged:)
    public func intervalChanged(_ sender: Any?) {
        if let interval = intervalPopUp?.selectedItem?.representedObject as? NSNumber {
            BPPreferences.backgroundCheckInterval = interval.doubleValue
        }
        syncSwiftUIHost()
    }

    override public func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refreshHelperStatus()
    }

    @objc(toggleGreedy:)
    public func toggleGreedy(_ sender: Any?) {
        BPPreferences.greedyCaskUpgrades = (greedyCheckbox?.state == .on)
        syncSwiftUIHost()
    }
}

@MainActor
@objc(BPAutoremoveWindowController)
public final class BPAutoremoveWindowController: NSWindowController {
    @objc public var interface: AnyObject?
    @objc public var manager: AnyObject?
    @objc public var preview: BPAutoremovePreview?
    @objc public var operation: BPAutoremoveOperation?
    @objc public var previewProgress: Progress?
    @objc public var statusLabel: NSTextField?
    @objc public var outputView: BPAutoScrollTextView?
    @objc public var removeButton: NSButton?
    @objc public var cancelButton: NSButton?
    @objc public var autoremoveHost: BPAutoremoveHost?
    @objc public var busy: Bool = false

    @objc(presentForWindow:interface:manager:)
    public static func present(
        for parent: NSWindow?,
        interface: Any?,
        manager: Any?
    ) -> BPAutoremoveWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let controller = BPAutoremoveWindowController(window: window)
        controller.interface = interface as AnyObject?
        controller.manager = manager as AnyObject?
        controller.buildContent()
        bpSharedAppDelegate()?.isRunningBackgroundTask = true
        parent?.beginSheet(window) { _ in
            bpSharedAppDelegate()?.isRunningBackgroundTask = false
        }
        controller.loadPreview()
        return controller
    }

    private func buildContent() {
        window?.title = NSLocalizedString("Remove Unused Dependencies", comment: "")
        statusLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("Checking unused dependencies…", comment: ""))
        let outView = BPAutoScrollTextView(frame: NSRect(x: 0, y: 0, width: 620, height: 280))
        outView.isEditable = false
        outView.isSelectable = true
        outView.isRichText = false
        outView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        outView.textColor = .textColor
        outView.backgroundColor = .textBackgroundColor
        outView.textContainerInset = NSSize(width: 8, height: 8)
        outView.autoresizingMask = [.width]
        outView.isVerticallyResizable = true
        outView.textContainer?.widthTracksTextView = true
        outView.setAccessibilityIdentifier("autoremove.output")
        outView.setAccessibilityLabel(NSLocalizedString("Unused dependency preview and command output", comment: ""))
        self.outputView = outView

        let remBtn = NSButton(
            title: NSLocalizedString("Remove Reviewed Dependencies", comment: ""),
            target: self,
            action: #selector(removeReviewed(_:))
        )
        remBtn.isEnabled = false
        self.removeButton = remBtn

        let canBtn = NSButton(
            title: NSLocalizedString("Cancel", comment: ""),
            target: self,
            action: #selector(cancelOrClose(_:))
        )
        canBtn.isEnabled = true
        self.cancelButton = canBtn

        let host = BPAutoremoveHost(outputTextView: outView)
        host.onRemove = { [weak self] in
            self?.removeReviewed(nil)
        }
        host.onCancelOrClose = { [weak self] in
            self?.cancelOrClose(nil)
        }
        self.autoremoveHost = host

        if let contentView = window?.contentView {
            let hostView = host.viewController.view
            hostView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(hostView)
            NSLayoutConstraint.activate([
                hostView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
        syncAutoremoveHostState()
    }

    @objc public func syncAutoremoveHostState() {
        autoremoveHost?.candidateCount = (preview?.valid == true) ? (preview?.names.count ?? 0) : 0
        autoremoveHost?.update(
            statusText: statusLabel?.stringValue ?? "",
            removeEnabled: removeButton?.isEnabled ?? false,
            cancelTitle: cancelButton?.title ?? "",
            cancelEnabled: cancelButton?.isEnabled ?? true,
            busy: busy
        )
        autoremoveHost?.syncLogFromTextView()
    }

    private func loadPreview() {
        busy = true
        syncAutoremoveHostState()
        let progress = Progress(totalUnitCount: 1)
        self.previewProgress = progress
        nonisolated(unsafe) let iface = self.interface
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let preview = bpAsHomebrewInterface(iface)?.previewAutoremove(withProgress: progress)
                ?? BPAutoremovePreview.preview(withOutput: nil, succeeded: false)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.preview = preview
                self.outputView?.string = preview.rawOutput
                self.cancelButton?.isEnabled = true
                if progress.isCancelled {
                    self.statusLabel?.stringValue = NSLocalizedString("Cancelled before removal. Nothing was removed.", comment: "")
                } else if !preview.valid {
                    self.statusLabel?.stringValue = NSLocalizedString("The unused dependency preview could not be verified. Nothing can be removed.", comment: "")
                } else if preview.names.isEmpty {
                    self.statusLabel?.stringValue = NSLocalizedString("No unused dependencies to remove.", comment: "")
                } else {
                    self.statusLabel?.stringValue = String.localizedStringWithFormat(
                        NSLocalizedString("Review %lu unused dependencies before removal.", comment: ""),
                        UInt(preview.names.count)
                    )
                    self.removeButton?.isEnabled = true
                }
                self.cancelButton?.title = NSLocalizedString("Close", comment: "")
                self.syncAutoremoveHostState()
            }
        }
    }

    @objc(removeReviewed:)
    public func removeReviewed(_ sender: Any?) {
        guard !busy,
              removeButton?.isEnabled == true,
              let preview,
              preview.valid,
              !preview.names.isEmpty else {
            return
        }
        busy = true
        removeButton?.isEnabled = false
        cancelButton?.title = NSLocalizedString("Cancel", comment: "")
        statusLabel?.stringValue = NSLocalizedString("Rechecking and removing reviewed dependencies…", comment: "")
        syncAutoremoveHostState()

        let op = BPAutoremoveOperation(preview: preview, interface: interface)
        self.operation = op
        let outView = self.outputView
        outView?.appendOutput("\n")
        op.start(withOutput: { [weak self] chunk in
            outView?.appendOutput(chunk)
            DispatchQueue.main.async {
                self?.autoremoveHost?.syncLogFromTextView()
            }
        }, completion: { [weak self] _, _, attempted, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.outputView?.flushPendingOutput()
                self.cancelButton?.isEnabled = false
                self.syncAutoremoveHostState()
                let finished: @Sendable (Bool) -> Void = { [weak self] refreshed in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if refreshed {
                            self.statusLabel?.stringValue = message
                        } else {
                            let suffix = NSLocalizedString(
                                "Some formula or service lists could not be refreshed. Previous values were retained; refresh again before another operation.",
                                comment: ""
                            )
                            self.statusLabel?.stringValue = "\(message)\n\(suffix)"
                        }
                        self.busy = false
                        self.cancelButton?.title = NSLocalizedString("Close", comment: "")
                        self.cancelButton?.isEnabled = true
                        self.syncAutoremoveHostState()
                    }
                }
                if attempted, let mgr = bpAsHomebrewManager(self.manager) {
                    mgr.refreshFormulaStateAfterRemoval(withCompletion: finished)
                } else {
                    finished(true)
                }
            }
        })
    }

    @objc(cancelOrClose:)
    public func cancelOrClose(_ sender: Any?) {
        if busy {
            cancelButton?.isEnabled = false
            statusLabel?.stringValue = NSLocalizedString("Cancelling; waiting for Homebrew to stop…", comment: "")
            syncAutoremoveHostState()
            if let operation {
                operation.cancel()
            } else {
                previewProgress?.cancel()
            }
        } else if let window = self.window {
            window.sheetParent?.endSheet(window)
        }
    }
}

@MainActor
@objc(BPBundleWindowController)
public final class BPBundleWindowController: NSWindowController {
    @objc public var viewOperationContainer: NSView?
    @objc public var viewExportProgress: NSView?
    @objc public var viewImportProgress: NSView?
    @objc public var textViewImport: BPAutoScrollTextView?
    @objc public var progressLabelImport: NSTextField?
    @objc public var statusViewExport: NSImageView?
    @objc public var statusLabelExport: NSTextField?
    @objc public var progressLabelExport: NSTextField?
    @objc public var progressIndicator: NSProgressIndicator?
    @objc public var buttonClose: NSButton?

    @objc public var importOperation: BPBrewfileImportOperation?
    @objc public var exportOperation: BPBrewfileExportOperation?
    @objc public var bundleHost: BPBundleOperationHost?

    @objc(reviewHostForPlan:fileName:error:)
    public static func reviewHost(
        for plan: BPBrewfilePlan?,
        fileName: String?,
        error: NSError?
    ) -> BPBrewfileReviewHost {
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 550, height: 210))
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.font = NSFont.systemFont(ofSize: 13)
        text.textColor = .textColor
        text.backgroundColor = .textBackgroundColor
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        text.setAccessibilityIdentifier("brewfile.review.entries")
        text.string = error?.localizedDescription ?? (plan?.reviewText ?? "")
        if bpSharedHomebrewInterface()?.brewTransport != 0 {
            text.string = NSLocalizedString(
                "Reviewed import requires the standard, non-sandboxed Cakebrew app. Helper transport is not supported.",
                comment: ""
            )
        }

        var installedCount = 0
        var missingCount = 0
        var notCheckedCount = 0
        var formulaCount = 0
        var caskCount = 0
        var tapCount = 0
        var otherCount = 0

        for entry in plan?.entries ?? [] {
            if entry.status == "Installed" {
                installedCount += 1
            } else if entry.status == "Missing" {
                missingCount += 1
            } else {
                notCheckedCount += 1
            }

            if entry.kind == "brew" {
                formulaCount += 1
            } else if entry.kind == "cask" {
                caskCount += 1
            } else if entry.kind == "tap" {
                tapCount += 1
            } else {
                otherCount += 1
            }
        }

        let canInstall = (plan?.canInstall == true) && (bpSharedHomebrewInterface()?.brewTransport == 0)
        let resolvedName = (fileName?.isEmpty == false) ? fileName! : "Brewfile"
        let host = BPBrewfileReviewHost(
            entriesTextView: text,
            fileName: resolvedName,
            installedCount: installedCount,
            missingCount: missingCount,
            notCheckedCount: notCheckedCount,
            formulaCount: formulaCount,
            caskCount: caskCount,
            tapCount: tapCount,
            otherCount: otherCount,
            canInstall: canInstall,
            summaryText: plan?.reviewText ?? ""
        )
        host.viewController.view.frame = NSRect(x: 0, y: 0, width: 570, height: 280)
        return host
    }

    @objc(reviewFile:inventories:parentWindow:completion:)
    public static func reviewFile(
        _ url: URL?,
        inventories: [String: [String]]?,
        parentWindow window: NSWindow?,
        completion: (@Sendable (BPBrewfilePlan?) -> Void)?
    ) {
        let inv = inventories ?? [:]
        DispatchQueue.global(qos: .userInitiated).async {
            var nsError: NSError?
            let plan: BPBrewfilePlan?
            do {
                plan = try BPBrewfilePlan.plan(with: url, inventories: inv)
            } catch let err as NSError {
                nsError = err
                plan = nil
            }
            let capturedError = nsError
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Review Brewfile", comment: "")
                let fileName = url?.lastPathComponent ?? ""
                let disclaimer = NSLocalizedString(
                    "Direct entries only, not a dependency or upgrade plan. Installed means present in the current inventory, not up to date. Homebrew may upgrade packages, install dependencies and required tools, and run package installation scripts. Only the reviewed literal entries will be submitted.",
                    comment: ""
                )
                alert.informativeText = "\(fileName)\n\n\(disclaimer)"
                let install = alert.addButton(withTitle: NSLocalizedString("Install Reviewed Entries", comment: ""))
                install.setAccessibilityIdentifier("brewfile.review.install")
                let canInstall = (plan?.canInstall == true) && (bpSharedHomebrewInterface()?.brewTransport == 0)
                install.isEnabled = canInstall
                let cancel = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
                cancel.setAccessibilityIdentifier("brewfile.review.cancel")
                let reviewHost = Self.reviewHost(for: plan, fileName: fileName, error: capturedError)
                objc_setAssociatedObject(alert, &bpBrewfileReviewHostAssocKey, reviewHost, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                alert.accessoryView = reviewHost.viewController.view
                if let window {
                    alert.beginSheetModal(for: window) { result in
                        completion?(result == .alertFirstButtonReturn && canInstall ? plan : nil)
                    }
                } else {
                    completion?(nil)
                }
            }
        }
    }

    @objc(runImportOperationWithPlan:)
    public static func runImportOperation(with plan: BPBrewfilePlan?) -> BPBundleWindowController {
        let controller = createWindow()
        bpSharedAppDelegate()?.isRunningBackgroundTask = true
        controller.startSheetOnMainWindow()
        controller.runImportOperation(with: plan)
        return controller
    }

    @objc(runExportOperationWithFile:)
    public static func runExportOperation(withFile fileURL: URL?) -> BPBundleWindowController {
        let controller = createWindow()
        bpSharedAppDelegate()?.isRunningBackgroundTask = true
        controller.startSheetOnMainWindow()
        controller.runExportOperation(withFile: fileURL)
        return controller
    }

    @objc public static func createWindow() -> BPBundleWindowController {
        BPBundleWindowController(windowNibName: "BPBundleWindow")
    }

    override public func loadWindow() {
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 413, height: 289),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    override public func windowDidLoad() {
        super.windowDidLoad()
        if textViewImport == nil {
            textViewImport = BPAutoScrollTextView(frame: NSRect(x: 0, y: 0, width: 373, height: 197))
        }
        if buttonClose == nil {
            buttonClose = NSButton(frame: NSRect(x: 0, y: 0, width: 80, height: 28))
        }
        if progressLabelImport == nil {
            progressLabelImport = NSTextField(labelWithString: "")
        }
        guard let textViewImport else { return }
        textViewImport.isEditable = false
        textViewImport.isSelectable = true
        textViewImport.isRichText = false
        textViewImport.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textViewImport.setAccessibilityIdentifier("brewfile.import.output")

        let host = BPBundleOperationHost(importTextView: textViewImport)
        host.onAction = { [weak self] in
            self?.didClickClose(nil)
        }
        self.bundleHost = host

        if let contentView = window?.contentView {
            for subview in contentView.subviews {
                subview.removeFromSuperview()
            }
            let hostView = host.viewController.view
            hostView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(hostView)
            NSLayoutConstraint.activate([
                hostView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
    }

    private func startSheetOnMainWindow() {
        guard let sheetWindow = self.window else { return }
        bpSharedAppDelegate()?.window?.beginSheet(sheetWindow) { _ in
            bpSharedAppDelegate()?.isRunningBackgroundTask = false
        }
    }

    @objc(runImportOperationWithPlan:)
    public func runImportOperation(with plan: BPBrewfilePlan?) {
        _ = self.window
        textViewImport?.clearOutput()
        window?.title = NSLocalizedString("Import Brewfile", comment: "")
        window?.setContentSize(NSSize(width: 650, height: 380))
        textViewImport?.setAccessibilityIdentifier("brewfile.import.output")
        buttonClose?.title = NSLocalizedString("Cancel", comment: "")
        buttonClose?.isEnabled = true
        bundleHost?.configureImport(
            statusText: nil,
            actionTitle: NSLocalizedString("Cancel", comment: ""),
            actionEnabled: true,
            running: true
        )
        let iface = (NSClassFromString("BPHomebrewInterface") as AnyObject?)
            .flatMap { unsafeBitCast($0, to: BPHomebrewInterfaceClassObjCBridge.self).sharedInterface() }
        let op = BPBrewfileImportOperation(plan: plan, interface: iface)
        self.importOperation = op
        let tv = self.textViewImport
        op.start(withOutput: { [weak self] output in
            tv?.appendOutput(output)
            DispatchQueue.main.async {
                self?.bundleHost?.syncLogFromTextView()
            }
        }, completion: { [weak self] success, cancelled, error in
            DispatchQueue.main.async {
                guard let self else { return }
                let status = cancelled
                    ? NSLocalizedString("Import cancelled. Some changes may already have been made.", comment: "")
                    : (success
                        ? NSLocalizedString("Import finished.", comment: "")
                        : NSLocalizedString("Import failed. Review the output for details.", comment: ""))
                self.progressLabelImport?.stringValue = status
                if let error {
                    self.textViewImport?.appendOutput(error.localizedDescription)
                }
                self.textViewImport?.flushPendingOutput()
                self.buttonClose?.title = NSLocalizedString("Close", comment: "")
                self.buttonClose?.isEnabled = true
                self.bundleHost?.configureImport(
                    statusText: status,
                    actionTitle: NSLocalizedString("Close", comment: ""),
                    actionEnabled: true,
                    running: false
                )
                self.bundleHost?.syncLogFromTextView()
            }
        })
    }

    @objc(runExportOperationWithFile:)
    public func runExportOperation(withFile fileURL: URL?) {
        _ = self.window
        buttonClose?.isEnabled = false
        bundleHost?.configureExport(
            statusText: nil,
            detailText: nil,
            actionTitle: nil,
            actionEnabled: false,
            running: true,
            finished: false,
            succeeded: false
        )
        let iface = (NSClassFromString("BPHomebrewInterface") as AnyObject?)
            .flatMap { unsafeBitCast($0, to: BPHomebrewInterfaceClassObjCBridge.self).sharedInterface() }
        let op = BPBrewfileExportOperation(url: fileURL, interface: iface)
        self.exportOperation = op
        op.start { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                let succeeded = (error == nil)
                let statusText = error != nil ? NSLocalizedString("Brewfile_Export_Failed", comment: "") : nil
                let detailText = error?.localizedDescription
                self.buttonClose?.isEnabled = true
                self.bundleHost?.configureExport(
                    statusText: statusText,
                    detailText: detailText,
                    actionTitle: nil,
                    actionEnabled: true,
                    running: false,
                    finished: true,
                    succeeded: succeeded
                )
            }
        }
    }

    @objc(didClickClose:)
    public func didClickClose(_ sender: Any?) {
        if exportOperation?.running == true { return }
        if importOperation?.running == true {
            importOperation?.cancel()
            buttonClose?.isEnabled = false
            let cancelling = NSLocalizedString("Cancelling… Waiting for Homebrew to exit.", comment: "")
            progressLabelImport?.stringValue = cancelling
            bundleHost?.configureImport(
                statusText: cancelling,
                actionTitle: NSLocalizedString("Cancel", comment: ""),
                actionEnabled: false,
                running: true
            )
            return
        }
        if let window = self.window {
            window.sheetParent?.endSheet(window)
        }
    }
}

// MARK: - Swift 6 Wave 8: Dock Menu Protocols, Table View, Background Updater, Services, Installation & AppDelegate

@objc(BPDockMenuActions)
public protocol BPDockMenuActions: NSObjectProtocol {
    @objc(updateHomebrew:)
    func updateHomebrew(_ sender: Any?)
    @objc(upgradeAllOutdatedFormulae:)
    func upgradeAllOutdatedFormulae(_ sender: Any?)
    @objc(showUnifiedUpdates:)
    func showUnifiedUpdates(_ sender: Any?)
}

@objc(BPDockMenuTarget)
public protocol BPDockMenuTarget: BPDockMenuActions {
    @objc(isHomebrewInstalled)
    func isHomebrewInstalled() -> Bool
}

@objc(BPWindowOperation)
public enum BPWindowOperation: UInt, Sendable {
    @objc(kBPWindowOperationInstall) case install = 0
    @objc(kBPWindowOperationUninstall) case uninstall = 1
    @objc(kBPWindowOperationUpgrade) case upgrade = 2
    @objc(kBPWindowOperationTap) case tap = 3
    @objc(kBPWindowOperationUntap) case untap = 4
    @objc(kBPWindowOperationCleanup) case cleanup = 5
}

@objc(BPFormulaeTableRequest)
public enum BPFormulaeTableRequest: Int {
    case primary = 0
    case uninstall = 1
}

@objc(BPFormulaeTableActionDelegate)
public protocol BPFormulaeTableActionDelegate: NSObjectProtocol {
    @objc(formulaeTableView:requestAction:)
    func formulaeTableView(_ table: BPFormulaeTableView, requestAction request: BPFormulaeTableRequest)
}

@objc private protocol BPFirstResponderProviding: NSObjectProtocol {
    @objc optional var firstResponder: AnyObject? { get }
}

@MainActor
@objc(BPFormulaeTableView)
open class BPFormulaeTableView: NSTableView {
    nonisolated(unsafe) private static var kvoContext: UInt8 = 0

    private static let columnIdentifierVersion = NSUserInterfaceItemIdentifier("Version")
    private static let columnIdentifierLatestVersion = NSUserInterfaceItemIdentifier("LatestVersion")
    private static let columnIdentifierStatus = NSUserInterfaceItemIdentifier("Status")
    private static let columnIdentifierName = NSUserInterfaceItemIdentifier("Name")
    private static let spaceCharacter: unichar = 0x0020

    @objc dynamic open var mode: BPListMode = .all
    @objc open weak var actionDelegate: (any BPFormulaeTableActionDelegate)?
    private var isObservingMode: Bool = false

    open override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            self.target = self
            self.doubleAction = #selector(performDoubleClickAction(_:))
            if !self.isObservingMode {
                self.addObserver(
                    self,
                    forKeyPath: "mode",
                    options: [.initial, .new],
                    context: &Self.kvoContext
                )
                self.isObservingMode = true
            }
        }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.mode = .all
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc open func configureTableForListing() {
        var totalWidth: CGFloat = 0
        var titleWidth: Int = 0

        if let superview = self.superview {
            totalWidth = superview.frame.size.width
            let marginsFrame = superview.layoutMarginsGuide.frame
            totalWidth -= marginsFrame.origin.x * 2
        }

        switch self.mode {
        case .all, .allCasks:
            titleWidth = Int(totalWidth - 125)
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierLatestVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.isHidden = false
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.width = CGFloat(Int((totalWidth - CGFloat(titleWidth)) * 0.90))
            allowsMultipleSelection = false

        case .installed, .pinned, .installedCasks:
            titleWidth = Int(totalWidth * 0.4)
            tableColumn(withIdentifier: Self.columnIdentifierLatestVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.isHidden = false
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.width = CGFloat(Int(totalWidth)) * 0.55
            allowsMultipleSelection = false

        case .leaves:
            titleWidth = Int(totalWidth - 1)
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierLatestVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.isHidden = true
            allowsMultipleSelection = false

        case .outdated, .outdatedCasks:
            titleWidth = Int(totalWidth * 0.4)
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.isHidden = false
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.width = (totalWidth - CGFloat(titleWidth)) * 0.48
            tableColumn(withIdentifier: Self.columnIdentifierLatestVersion)?.isHidden = false
            tableColumn(withIdentifier: Self.columnIdentifierLatestVersion)?.width = (totalWidth - CGFloat(titleWidth)) * 0.48
            allowsMultipleSelection = true

        case .search:
            titleWidth = Int(totalWidth - 90)
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierLatestVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.isHidden = false
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.width = (totalWidth - CGFloat(titleWidth)) * 0.90
            allowsMultipleSelection = false

        case .repositories:
            titleWidth = Int(totalWidth - 1)
            tableColumn(withIdentifier: Self.columnIdentifierVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierLatestVersion)?.isHidden = true
            tableColumn(withIdentifier: Self.columnIdentifierStatus)?.isHidden = true
            allowsMultipleSelection = false

        @unknown default:
            break
        }

        tableColumn(withIdentifier: Self.columnIdentifierName)?.width = CGFloat(titleWidth)
        needsLayout = true
    }

    open nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if context == &Self.kvoContext {
            if let obj = object as AnyObject?, obj === self, keyPath == "mode" {
                MainActor.assumeIsolated {
                    self.configureTableForListing()
                }
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    @objc open func currentFirstResponder() -> AnyObject? {
        return self.window?.firstResponder
    }

    open override func performKeyEquivalent(with theEvent: NSEvent) -> Bool {
        let responder = currentFirstResponder()
        if responder !== self {
            return super.performKeyEquivalent(with: theEvent)
        }

        if self.selectedRow == -1 {
            return false
        }

        let chars = (theEvent.charactersIgnoringModifiers ?? "") as NSString
        if theEvent.type == .keyDown && chars.length == 1 {
            let key = chars.character(at: 0)
            if key == Self.spaceCharacter {
                spaceBarPressed()
                return true
            }
            let shortcuts: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            if !theEvent.isARepeat && theEvent.modifierFlags.intersection(shortcuts).isEmpty {
                if key == unichar(NSCarriageReturnCharacter) || key == unichar(NSEnterCharacter) {
                    actionDelegate?.formulaeTableView(self, requestAction: .primary)
                    return true
                }
                if key == unichar(NSDeleteCharacter) || key == unichar(NSDeleteFunctionKey) {
                    actionDelegate?.formulaeTableView(self, requestAction: .uninstall)
                    return true
                }
            }
        }
        return false
    }

    @objc(performDoubleClickAction:)
    open func performDoubleClickAction(_ sender: Any?) {
        let row = self.clickedRow
        if row < 0 || row >= self.numberOfRows || !self.selectedRowIndexes.contains(row) {
            return
        }
        actionDelegate?.formulaeTableView(self, requestAction: .primary)
    }

    @objc open func spaceBarPressed() {
        NSApp.sendAction(NSSelectorFromString("showFormulaInfo:"), to: nil, from: self)
    }

    deinit {
        if isObservingMode {
            super.removeObserver(self, forKeyPath: "mode", context: &Self.kvoContext)
        }
    }
}

@MainActor
@objc(BPTableActionWindowStub)
public final class BPTableActionWindowStub: NSObject {
    @objc public weak var firstResponder: NSResponder?
}

@MainActor
@objc(BPActionTestTable)
public final class BPActionTestTable: BPFormulaeTableView {
    @objc public var testWindow: BPTableActionWindowStub?
    @objc public var testSelectedRow: Int = 0
    @objc public var spaceCount: Int = 0
    @objc public var testClickedRow: Int = 0

    public override func currentFirstResponder() -> AnyObject? {
        return testWindow?.firstResponder
    }

    public override var selectedRow: Int { testSelectedRow }
    public override var clickedRow: Int { testClickedRow }
    public override var numberOfRows: Int { 2 }
    public override var selectedRowIndexes: IndexSet {
        testSelectedRow < 0 ? IndexSet() : IndexSet(integer: testSelectedRow)
    }

    public override func spaceBarPressed() {
        spaceCount += 1
    }
}

@objc private protocol BPUserNotificationCenterMessaging: NSObjectProtocol {
    @objc(requestAuthorizationWithOptions:completionHandler:)
    func requestAuthorization(
        withOptions options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, NSError?) -> Void
    )
    @objc(addNotificationRequest:withCompletionHandler:)
    func addNotificationRequest(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (NSError?) -> Void)?
    )
}

@objc(BPBackgroundUpdater)
open class BPBackgroundUpdater: NSObject, @unchecked Sendable {
    nonisolated(unsafe) private static var kvoContext: UInt8 = 0

    private static let lastNotifiedOutdatedCountKey = "BPLastNotifiedOutdatedCount"
    public static let outdatedNotificationTargetKey = "outdated-target"
    public static let outdatedNotificationTargetFormulae = "formulae"
    public static let outdatedNotificationTargetCasks = "casks"
    public static let outdatedNotificationTargetMixed = "mixed"

    @objc open var timer: Timer?
    @objc open var lastKnownOutdatedCount: UInt = 0
    @objc open var scheduledInterval: TimeInterval = 0
    @objc open var observingHomebrewManager: Bool = false
    @objc open var notificationCenter: AnyObject?

    public override convenience init() {
        self.init(notificationCenter: UNUserNotificationCenter.current())
    }

    @objc(initWithNotificationCenter:)
    public init(notificationCenter: Any?) {
        self.notificationCenter = notificationCenter as AnyObject?
        super.init()
    }

    @objc(badgeLabelForOutdatedCount:)
    open class func badgeLabel(forOutdatedCount count: UInt) -> String? {
        count == 0 ? nil : "\(count)"
    }

    @objc(shouldNotifyForCount:previousCount:)
    open class func shouldNotify(forCount count: UInt, previousCount: UInt) -> Bool {
        count > previousCount
    }

    @objc(shouldNotifyForCount:previousCount:hasBaseline:)
    open class func shouldNotify(forCount count: UInt, previousCount: UInt, hasBaseline: Bool) -> Bool {
        guard hasBaseline else { return false }
        return shouldNotify(forCount: count, previousCount: previousCount)
    }

    @objc open class func persistedOutdatedCount() -> UInt {
        UInt(max(0, UserDefaults.standard.integer(forKey: lastNotifiedOutdatedCountKey)))
    }

    @objc(setPersistedOutdatedCount:)
    open class func setPersistedOutdatedCount(_ count: UInt) {
        UserDefaults.standard.set(Int(count), forKey: lastNotifiedOutdatedCountKey)
    }

    @objc open class func hasPersistedOutdatedCount() -> Bool {
        UserDefaults.standard.object(forKey: lastNotifiedOutdatedCountKey) != nil
    }

    @objc open class func clearPersistedOutdatedCount() {
        UserDefaults.standard.removeObject(forKey: lastNotifiedOutdatedCountKey)
    }

    @objc(notificationUserInfoForOutdatedFormulaeCount:caskCount:)
    open class func notificationUserInfo(forOutdatedFormulaeCount formulaeCount: UInt, caskCount: UInt) -> [String: String]? {
        if formulaeCount > 0 && caskCount > 0 {
            return [outdatedNotificationTargetKey: outdatedNotificationTargetMixed]
        }
        if formulaeCount > 0 {
            return [outdatedNotificationTargetKey: outdatedNotificationTargetFormulae]
        }
        if caskCount > 0 {
            return [outdatedNotificationTargetKey: outdatedNotificationTargetCasks]
        }
        return nil
    }

    @objc open func start() {
        if let manager = bpSharedHomebrewManager() as? NSObject {
            manager.addObserver(self, forKeyPath: "outdatedFormulae", options: [], context: &Self.kvoContext)
            manager.addObserver(self, forKeyPath: "outdatedCasks", options: [], context: &Self.kvoContext)
            self.observingHomebrewManager = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(outdatedSnapshotDidPublish(_:)),
                name: Notification.Name("BPHomebrewManagerDidPublishOutdatedSnapshotNotification"),
                object: manager
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleTimer),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        scheduleTimer()
    }

    deinit {
        if observingHomebrewManager, let manager = bpSharedHomebrewManager() as? NSObject {
            manager.removeObserver(self, forKeyPath: "outdatedFormulae", context: &Self.kvoContext)
            manager.removeObserver(self, forKeyPath: "outdatedCasks", context: &Self.kvoContext)
        }
        NotificationCenter.default.removeObserver(self)
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        timer?.invalidate()
    }

    @objc open func scheduleTimer() {
        let enabled = BPPreferences.backgroundCheckEnabled
        let interval = max(BPPreferences.backgroundCheckInterval, 3600.0)

        if !enabled {
            timer?.invalidate()
            timer = nil
            scheduledInterval = 0
            return
        }

        if timer != nil && scheduledInterval == interval {
            return
        }

        timer?.invalidate()
        let newTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(timerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        newTimer.tolerance = interval * 0.1
        self.timer = newTimer
        self.scheduledInterval = interval
    }

    @objc(timerFired:)
    open func timerFired(_ timer: Timer?) {
        let busy = MainActor.assumeIsolated { bpSharedAppDelegate()?.isRunningBackgroundTask == true }
        if busy {
            return
        }
        bpSharedHomebrewManager()?.reloadFromInterface(rebuildingCache: false)
    }

    open nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if context != &Self.kvoContext {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(updateDockBadge), object: nil)
        self.perform(#selector(updateDockBadge), with: nil, afterDelay: 0)
    }

    @objc open func updateDockBadge() {
        let manager = bpSharedHomebrewManager()
        let count = UInt((manager?.outdatedFormulae?.count ?? 0) + (manager?.outdatedCasks?.count ?? 0))
        applyDockBadgeLabel(Self.badgeLabel(forOutdatedCount: count))
    }

    @objc(applyDockBadgeLabel:)
    open func applyDockBadgeLabel(_ label: String?) {
        MainActor.assumeIsolated {
            NSApplication.shared.dockTile.badgeLabel = label
        }
    }

    @objc(outdatedSnapshotDidPublish:)
    open func outdatedSnapshotDidPublish(_ notification: Notification) {
        guard let manager = bpSharedHomebrewManager(),
              let obj = notification.object as AnyObject?,
              obj === (manager as AnyObject) else {
            return
        }
        let snapshot = notification.userInfo
        let gen = (snapshot?["generation"] as? NSNumber)?.uintValue ?? UInt.max
        if gen != manager.currentReloadGeneration {
            return
        }
        let formulaeCount = (snapshot?["formulae-count"] as? NSNumber)?.uintValue ?? 0
        let caskCount = (snapshot?["cask-count"] as? NSNumber)?.uintValue ?? 0
        let count = formulaeCount + caskCount

        let hasBaseline = Self.hasPersistedOutdatedCount()
        let previous = Self.persistedOutdatedCount()
        Self.setPersistedOutdatedCount(count)
        self.lastKnownOutdatedCount = count

        if Self.shouldNotify(forCount: count, previousCount: previous, hasBaseline: hasBaseline) {
            postOutdatedNotification(withFormulaeCount: formulaeCount, caskCount: caskCount)
        }
    }

    @objc(postOutdatedNotificationWithFormulaeCount:caskCount:)
    open func postOutdatedNotification(withFormulaeCount formulaeCount: UInt, caskCount: UInt) {
        guard let center = notificationCenter else { return }
        let centerProxy = unsafeBitCast(center, to: BPUserNotificationCenterMessaging.self)
        centerProxy.requestAuthorization(withOptions: [.alert, .sound]) { [weak self] granted, error in
            if let error {
                NSLog("Error requesting notification permissions: %@", error as NSError)
            }
            if granted {
                DispatchQueue.main.async {
                    self?.deliverOutdatedNotification(withFormulaeCount: formulaeCount, caskCount: caskCount)
                }
            }
        }
    }

    @objc(deliverOutdatedNotificationWithFormulaeCount:caskCount:)
    open func deliverOutdatedNotification(withFormulaeCount formulaeCount: UInt, caskCount: UInt) {
        let count = formulaeCount + caskCount
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Background_Update_Notification_Title", comment: "")
        content.body = String(format: NSLocalizedString("Background_Update_Notification_Body", comment: ""), count)
        if let userInfo = Self.notificationUserInfo(forOutdatedFormulaeCount: formulaeCount, caskCount: caskCount) {
            content.userInfo = userInfo
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        if let center = notificationCenter {
            let centerProxy = unsafeBitCast(center, to: BPUserNotificationCenterMessaging.self)
            centerProxy.addNotificationRequest(request, withCompletionHandler: nil)
        }
    }
}

@objc(BPObservingBackgroundUpdater)
public final class BPObservingBackgroundUpdater: BPBackgroundUpdater, @unchecked Sendable {
    @objc public var badgeLabel: String?

    public override func scheduleTimer() {}

    public override func applyDockBadgeLabel(_ label: String?) {
        self.badgeLabel = label
    }
}

@MainActor
@objc(BPServicesViewController)
open class BPServicesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private static let serviceColumnName = NSUserInterfaceItemIdentifier("Name")
    private static let serviceColumnStatus = NSUserInterfaceItemIdentifier("Status")
    private static let serviceColumnUser = NSUserInterfaceItemIdentifier("User")

    @objc open var services: [BPService]?
    @objc open var tableView: NSTableView?
    @objc open var startButton: NSButton?
    @objc open var stopButton: NSButton?
    @objc open var restartButton: NSButton?
    @objc open var operationInFlight: Bool = false
    @objc open var details: BPServiceDetails?
    @objc open var detailsGeneration: UInt = 0
    @objc open var listGeneration: UInt = 0
    @objc open var applyingServices: Bool = false
    @objc open var detailsText: NSTextView?
    @objc open var revealButton: NSButton?
    @objc open var logsButton: NSButton?
    @objc open var outputCopyButton: NSButton?
    @objc open var selectedServiceName: String?
    @objc open var servicesHost: BPServicesHost?

    open override func loadView() {
        let tv = NSTableView(frame: .zero)
        for identifier in [Self.serviceColumnName, Self.serviceColumnStatus, Self.serviceColumnUser] {
            let column = NSTableColumn(identifier: identifier)
            column.title = NSLocalizedString("Services_Column_\(identifier.rawValue)", comment: "")
            column.width = identifier == Self.serviceColumnName ? 260 : 140
            tv.addTableColumn(column)
        }
        tv.dataSource = self
        tv.delegate = self
        tv.allowsMultipleSelection = false
        tv.setAccessibilityLabel(NSLocalizedString("Services_Title", comment: ""))
        self.tableView = tv

        let scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = tv
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        self.startButton = makeButton(title: NSLocalizedString("Services_Start", comment: ""), action: #selector(startSelectedService(_:)))
        self.stopButton = makeButton(title: NSLocalizedString("Services_Stop", comment: ""), action: #selector(stopSelectedService(_:)))
        self.restartButton = makeButton(title: NSLocalizedString("Services_Restart", comment: ""), action: #selector(restartSelectedService(_:)))

        let detailsScroll = NSScrollView(frame: .zero)
        detailsScroll.hasVerticalScroller = true
        detailsScroll.borderType = .bezelBorder
        let dt = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        dt.isEditable = false
        dt.isSelectable = true
        dt.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        dt.textColor = .labelColor
        dt.backgroundColor = .textBackgroundColor
        dt.textContainerInset = NSSize(width: 8, height: 6)
        dt.autoresizingMask = [.width]
        dt.isVerticallyResizable = true
        dt.isHorizontallyResizable = false
        dt.textContainer?.widthTracksTextView = true
        dt.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        dt.setAccessibilityIdentifier("services.details")
        dt.setAccessibilityLabel(NSLocalizedString("Services_Details_Title", comment: ""))
        self.detailsText = dt
        detailsScroll.documentView = dt

        let revBtn = makeButton(title: NSLocalizedString("Services_Reveal_File", comment: ""), action: #selector(revealServiceFile(_:)))
        let logBtn = makeButton(title: NSLocalizedString("Services_Open_Logs", comment: ""), action: #selector(openServiceLogs(_:)))
        let copyBtn = makeButton(title: NSLocalizedString("Services_Copy_Output", comment: ""), action: #selector(copyServiceOutput(_:)))
        revBtn.setAccessibilityIdentifier("services.revealFile")
        logBtn.setAccessibilityIdentifier("services.openLogs")
        copyBtn.setAccessibilityIdentifier("services.copyOutput")
        self.revealButton = revBtn
        self.logsButton = logBtn
        self.outputCopyButton = copyBtn

        let host = BPServicesHost(tableScrollView: scrollView, detailsScrollView: detailsScroll)
        host.onStart = { [weak self] in self?.startSelectedService(nil) }
        host.onStop = { [weak self] in self?.stopSelectedService(nil) }
        host.onRestart = { [weak self] in self?.restartSelectedService(nil) }
        host.onRevealFile = { [weak self] in self?.revealServiceFile(nil) }
        host.onOpenLogs = { [weak self] in self?.openServiceLogs(nil) }
        host.onCopyOutput = { [weak self] in self?.copyServiceOutput(nil) }
        host.onFilterChanged = { [weak self] in self?.applyServiceFilters() }
        self.servicesHost = host

        self.view = host.viewController.view
        updateButtonStates()
        showDetailsMessage(NSLocalizedString("Services_Details_Select", comment: ""))
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.isEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc open func displayedServices() -> [BPService] {
        let statusFilter = servicesHost?.statusFilterRawValue ?? 0
        let query = (servicesHost?.filterQuery ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let all = services ?? []
        if statusFilter == 0 && query.isEmpty {
            return all
        }

        var filtered: [BPService] = []
        filtered.reserveCapacity(all.count)
        for service in all {
            if statusFilter == 1 && !(service.status == .started || service.status == .scheduled) {
                continue
            }
            if statusFilter == 2 && !(service.status == .none || service.status == .stopped) {
                continue
            }
            if statusFilter == 3 && service.status != .error {
                continue
            }
            if !query.isEmpty {
                let matchesName = service.name?.localizedCaseInsensitiveContains(query) ?? false
                let matchesUser = service.user?.localizedCaseInsensitiveContains(query) ?? false
                let localizedStatus = BPService.localizedName(for: service.status)
                let matchesStatus = localizedStatus.localizedCaseInsensitiveContains(query)
                if !matchesName && !matchesUser && !matchesStatus {
                    continue
                }
            }
            filtered.append(service)
        }
        return filtered
    }

    @objc open func applyServiceFilters() {
        let selectedName = selectedServiceName ?? selectedService()?.name
        applyingServices = true
        tableView?.reloadData()
        let displayed = displayedServices()
        if let selectedName, !selectedName.isEmpty,
           let idx = displayed.firstIndex(where: { $0.name == selectedName }) {
            tableView?.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        } else {
            tableView?.deselectAll(nil)
        }
        applyingServices = false
        selectedServiceName = selectedService()?.name
        updateButtonStates()
        refreshEmptyState()
        requestSelectedServiceDetails()
    }

    @objc open func refreshServices() {
        let selectedName = selectedService()?.name ?? selectedServiceName
        invalidateServiceDetails()
        let generation = self.listGeneration
        fetchServices { [weak self] fetched in
            MainActor.assumeIsolated {
                guard let self, generation == self.listGeneration else { return }
                self.applyingServices = true
                self.services = fetched
                self.tableView?.reloadData()
                let displayed = self.displayedServices()
                if let selectedName, !selectedName.isEmpty,
                   let idx = displayed.firstIndex(where: { $0.name == selectedName }) {
                    self.tableView?.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                } else {
                    self.tableView?.deselectAll(nil)
                }
                self.applyingServices = false
                self.selectedServiceName = self.selectedService()?.name
                self.updateButtonStates()
                self.refreshEmptyState()
                self.requestSelectedServiceDetails()
            }
        }
    }

    @objc(fetchServicesWithCompletion:)
    open func fetchServices(withCompletion completion: @escaping @Sendable ([BPService]?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let list = bpSharedHomebrewInterface()?.listServices()
            DispatchQueue.main.async {
                completion(list)
            }
        }
    }

    @objc open func selectedService() -> BPService? {
        let displayed = displayedServices()
        guard let row = tableView?.selectedRow, row >= 0 && row < displayed.count else {
            return nil
        }
        return displayed[row]
    }

    @objc open func invalidateServiceDetails() {
        detailsGeneration &+= 1
        listGeneration &+= 1
        details = nil
        showDetailsMessage(NSLocalizedString("Services_Details_Select", comment: ""))
    }

    @objc(fetchDetailsForName:completion:)
    open func fetchDetails(forName name: String?, completion: @escaping @Sendable (BPServiceDetails?) -> Void) {
        let serviceName = name
        DispatchQueue.global(qos: .utility).async {
            let result = bpSharedHomebrewInterface()?.serviceDetails(forName: serviceName)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    @objc open func requestSelectedServiceDetails() {
        detailsGeneration &+= 1
        let generation = detailsGeneration
        details = nil
        guard let name = selectedService()?.name, !name.isEmpty else {
            showDetailsMessage(NSLocalizedString("Services_Details_Select", comment: ""))
            return
        }
        showDetailsMessage(String(format: NSLocalizedString("Services_Details_Loading", comment: ""), name))
        fetchDetails(forName: name) { [weak self] fetched in
            MainActor.assumeIsolated {
                guard let self,
                      generation == self.detailsGeneration,
                      self.selectedService()?.name == name else {
                    return
                }
                self.details = fetched
                self.renderServiceDetails()
            }
        }
    }

    @objc(showDetailsMessage:)
    open func showDetailsMessage(_ message: String?) {
        detailsText?.string = message ?? ""
        revealButton?.isEnabled = validatedServiceFileURL() != nil
        logsButton?.isEnabled = !validatedLogURLs().isEmpty
        outputCopyButton?.isEnabled = !(details?.rawOutput.isEmpty ?? true)
        syncServicesHostState()
    }

    @objc open func renderServiceDetails() {
        let service = details?.service ?? selectedService()
        let unknown = NSLocalizedString("Services_Details_Not_Available", comment: "")
        var format = NSLocalizedString("Services_Details_Format", comment: "")
        if format == "Services_Details_Format" {
            format = "Service: %@\nStatus: %@\nPID: %@\nUser: %@\nFile: %@\nLoaded file: %@\nLog: %@\nError log: %@\nExit code: %@"
        }
        let statusName = service.map { BPService.localizedName(for: $0.status) } ?? unknown
        var text = String(
            format: format,
            service?.name ?? unknown,
            statusName,
            service?.pid?.stringValue ?? unknown,
            service?.user ?? unknown,
            details?.serviceFile ?? unknown,
            details?.loadedFile ?? unknown,
            details?.logPath ?? unknown,
            details?.errorLogPath ?? unknown,
            details?.exitCode?.stringValue ?? unknown
        )
        if let details, !details.available {
            text = "\(NSLocalizedString("Services_Details_Failed", comment: ""))\n\(details.rawOutput)\n\n\(text)"
        }
        showDetailsMessage(text)
        detailsText?.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    @objc open func validatedLogURLs() -> [URL] {
        var seen = Set<URL>()
        var urls: [URL] = []
        for path in [details?.logPath ?? "", details?.errorLogPath ?? ""] {
            if let url = BPServiceDetails.readableFileURL(forPath: path), seen.insert(url).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    @objc open func showUnavailableFileMessage() {
        let current = detailsText?.string ?? ""
        showDetailsMessage("\(current)\n\n\(NSLocalizedString("Services_File_Unavailable", comment: ""))")
    }

    @objc(revealServiceFile:)
    open func revealServiceFile(_ sender: Any?) {
        guard let url = validatedServiceFileURL() else {
            showUnavailableFileMessage()
            return
        }
        revealValidatedFileURL(url)
    }

    @objc open func validatedServiceFileURL() -> URL? {
        BPServiceDetails.readableFileURL(forPath: details?.loadedFile)
            ?? BPServiceDetails.readableFileURL(forPath: details?.serviceFile)
    }

    @objc(revealValidatedFileURL:)
    open func revealValidatedFileURL(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc(openServiceLogs:)
    open func openServiceLogs(_ sender: Any?) {
        let urls = validatedLogURLs()
        guard !urls.isEmpty else {
            showUnavailableFileMessage()
            return
        }
        openLogURLs(urls)
    }

    @objc(openLogURLs:)
    open func openLogURLs(_ urls: [URL]) {
        guard let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
            showUnavailableFileMessage()
            return
        }
        let generation = detailsGeneration
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: editor,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
            if error != nil {
                DispatchQueue.main.async {
                    guard let self, generation == self.detailsGeneration else { return }
                    self.showUnavailableFileMessage()
                }
            }
        }
    }

    @objc(copyServiceOutput:)
    open func copyServiceOutput(_ sender: Any?) {
        guard let raw = details?.rawOutput, !raw.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(raw, forType: .string)
    }

    @objc(startSelectedService:)
    open func startSelectedService(_ sender: Any?) {
        runOperation { iface, name, output in
            iface.startService(name, withReturnBlock: output)
        }
    }

    @objc(stopSelectedService:)
    open func stopSelectedService(_ sender: Any?) {
        runOperation { iface, name, output in
            iface.stopService(name, withReturnBlock: output)
        }
    }

    @objc(restartSelectedService:)
    open func restartSelectedService(_ sender: Any?) {
        runOperation { iface, name, output in
            iface.restartService(name, withReturnBlock: output)
        }
    }

    private func runOperation(_ operation: @escaping @Sendable (BPHomebrewInterfaceObjCBridge, String, @escaping @Sendable (String) -> Void) -> Bool) {
        let displayed = displayedServices()
        guard let row = tableView?.selectedRow,
              !operationInFlight,
              row >= 0 && row < displayed.count else {
            return
        }

        let appDelegate = bpSharedAppDelegate()
        if BPAppDelegate.shouldBlockOperation(whileRunningBackgroundTask: appDelegate?.isRunningBackgroundTask == true) {
            appDelegate?.displayBackgroundWarning()
            return
        }

        let name = displayed[row].name ?? ""
        operationInFlight = true
        invalidateServiceDetails()
        updateButtonStates()

        DispatchQueue.global(qos: .background).async { [weak self] in
            nonisolated(unsafe) let output = NSMutableString()
            let succeeded: Bool
            if let iface = bpSharedHomebrewInterface() {
                succeeded = operation(iface, name) { chunk in
                    bpSynchronized(output) {
                        output.append(chunk)
                    }
                }
            } else {
                succeeded = false
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.operationInFlight = false
                self.refreshServices()

                if !succeeded {
                    let transcript: String = bpSynchronized(output) { output.copy() as? String ?? "" }
                    self.presentServiceFailure(forName: name, output: transcript)
                }
            }
        }
    }

    @objc(presentServiceFailureForName:output:)
    open func presentServiceFailure(forName name: String, output: String) {
        let error = BPBrewError.error(forExitStatus: 1, output: output)
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Services_Operation_Failed_Title", comment: ""), name)
        alert.informativeText = error?.localizedDescription ?? ""
        alert.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
        if let window = bpSharedAppDelegate()?.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }

    @objc open func refreshEmptyState() {
        let displayed = displayedServices()
        let isFiltering = (servicesHost?.statusFilterRawValue ?? 0) != 0 || !(servicesHost?.filterQuery.isEmpty ?? true)
        var state: BPEmptyState?
        if BPEmptyState.shouldShow(forRowCount: displayed.count, loading: false) {
            state = BPEmptyState.state(
                forSidebarRow: Int(FormulaeSideBarItem.services.rawValue),
                searching: isFiltering && !(services?.isEmpty ?? true)
            )
        }
        BPEmptyStateView.presentState(state, over: tableView?.enclosingScrollView)
    }

    @objc open func updateButtonStates() {
        let service = selectedService()
        let enabled = service != nil && !operationInFlight
        let running = service?.status == .started || service?.status == .scheduled

        startButton?.isEnabled = enabled && !running
        stopButton?.isEnabled = enabled && running
        restartButton?.isEnabled = enabled
        syncServicesHostState()
    }

    @objc open func syncServicesHostState() {
        var runningCount = 0
        var stoppedCount = 0
        var errorCount = 0
        for service in services ?? [] {
            if service.status == .started || service.status == .scheduled {
                runningCount += 1
            } else if service.status == .error {
                errorCount += 1
            } else {
                stoppedCount += 1
            }
        }
        servicesHost?.syncCounts(running: runningCount, stopped: stoppedCount, error: errorCount)
        let serviceFilePath = !(details?.loadedFile?.isEmpty ?? true) ? details?.loadedFile : details?.serviceFile
        let logFilePath = !(details?.logPath?.isEmpty ?? true) ? details?.logPath : details?.errorLogPath
        servicesHost?.syncPaths(serviceFile: serviceFilePath, logFile: logFilePath)
        servicesHost?.update(
            startEnabled: startButton?.isEnabled ?? false,
            stopEnabled: stopButton?.isEnabled ?? false,
            restartEnabled: restartButton?.isEnabled ?? false,
            revealEnabled: revealButton?.isEnabled ?? false,
            logsEnabled: logsButton?.isEnabled ?? false,
            copyEnabled: outputCopyButton?.isEnabled ?? false
        )
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        displayedServices().count
    }

    public func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let displayed = displayedServices()
        guard row >= 0 && row < displayed.count else {
            return ""
        }
        let service = displayed[row]
        if tableColumn?.identifier == Self.serviceColumnName {
            return service.name
        }
        if tableColumn?.identifier == Self.serviceColumnStatus {
            return BPService.localizedName(for: service.status)
        }
        if tableColumn?.identifier == Self.serviceColumnUser {
            return service.user ?? "--"
        }
        return ""
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        selectedServiceName = selectedService()?.name
        updateButtonStates()
        if !applyingServices {
            requestSelectedServiceDetails()
        }
    }
}

@MainActor
@objc(BPDeferredServicesController)
public final class BPDeferredServicesController: BPServicesViewController {
    @objc public var completions: NSMutableArray?
    @objc public var listCompletion: (([BPService]?) -> Void)?
    @objc public var openedURLs: [URL]?
    @objc public var revealedURL: URL?

    public override func fetchDetails(forName name: String?, completion: @escaping @Sendable (BPServiceDetails?) -> Void) {
        let block: @convention(block) (BPServiceDetails?) -> Void = { details in
            completion(details)
        }
        completions?.add(unsafeBitCast(block, to: AnyObject.self))
    }

    public override func fetchServices(withCompletion completion: @escaping @Sendable ([BPService]?) -> Void) {
        self.listCompletion = completion
    }

    public override func openLogURLs(_ urls: [URL]) {
        self.openedURLs = urls
    }

    public override func revealValidatedFileURL(_ url: URL) {
        self.revealedURL = url
    }
}

@objc private protocol BPButtonEnabling: NSObjectProtocol {
    @objc var isEnabled: Bool {
        @objc(isEnabled) get
        @objc(setEnabled:) set
    }
}

@objc private protocol BPSheetWindowMessaging: NSObjectProtocol {
    @objc var sheetParent: AnyObject? { get }
    @objc(beginSheet:completionHandler:)
    func beginSheet(_ sheetWindow: AnyObject, completionHandler handler: ((NSApplication.ModalResponse) -> Void)?)
    @objc(endSheet:)
    func endSheet(_ sheetWindow: AnyObject)
}

@objc private protocol BPSheetDelegateRecorderMessaging: NSObjectProtocol {
    @objc optional var window: AnyObject? { get }
    @objc(isRunningBackgroundTask) optional func isRunningBackgroundTask() -> Bool
    @objc(runningBackgroundTask) optional func runningBackgroundTask() -> Bool
    @objc(setRunningBackgroundTask:) optional func setRunningBackgroundTask(_ running: Bool)
}

@objc private protocol BPSheetAppRecorderMessaging: NSObjectProtocol {
    @objc optional var delegate: AnyObject? { get }
    @objc optional var events: NSMutableArray? { get }
}

@MainActor
@objc(BPInstallationWindowController)
open class BPInstallationWindowController: NSWindowController {
    @objc open var windowTitleLabel: NSTextField?
    @objc open var formulaNameLabel: NSTextField?
    @objc open var recordTextView: BPAutoScrollTextView?
    @objc open var okButton: AnyObject?
    @objc open var cancelButton: NSButton?
    @objc open var wasCancelled: Bool = false
    @objc open var upgradeProgress: Progress?
    @objc open var progressIndicator: NSProgressIndicator?

    @objc open var windowOperation: BPWindowOperation = .install
    @objc open var formulae: [Any]?
    @objc open var options: [Any]?

    @objc open var operationStatus: Bool = false
    @objc open var upgradeResult: BPUpgradeResult?
    @objc open var upgradeWorkerFinished: Bool = false
    @objc open var zapCask: Bool = false
    @objc open var completionBlock: ((Bool) -> Void)?
    @objc open var installationHost: BPInstallationHost?
    @objc open var isRunningTask: Bool = false

    @objc open class func applicationDelegate() -> AnyObject? {
        guard let app = NSApp as AnyObject? else { return nil }
        return unsafeBitCast(app, to: BPSheetAppRecorderMessaging.self).delegate ?? nil
    }

    @objc open class func sharedTaskMessagesMap() -> [NSNumber: String] {
        return [
            NSNumber(value: BPWindowOperation.install.rawValue): NSLocalizedString("Installation_Window_Operation_Install", comment: ""),
            NSNumber(value: BPWindowOperation.uninstall.rawValue): NSLocalizedString("Installation_Window_Operation_Uninstall", comment: ""),
            NSNumber(value: BPWindowOperation.upgrade.rawValue): NSLocalizedString("Installation_Window_Operation_Update", comment: ""),
            NSNumber(value: BPWindowOperation.tap.rawValue): NSLocalizedString("Installation_Window_Operation_Tap", comment: ""),
            NSNumber(value: BPWindowOperation.untap.rawValue): NSLocalizedString("Installation_Window_Operation_Untap", comment: ""),
            NSNumber(value: BPWindowOperation.cleanup.rawValue): NSLocalizedString("Installation_Window_Operation_Cleanup", comment: "")
        ]
    }

    @objc open func sheetWindowObject() -> AnyObject? {
        return self.window
    }

    open override func loadWindow() {
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        if progressIndicator == nil {
            progressIndicator = NSProgressIndicator(frame: .zero)
        }
        setupUI()
    }

    open override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            self.setupUI()
        }
    }

    private func setOkButtonEnabled(_ enabled: Bool) {
        guard let okButton else { return }
        unsafeBitCast(okButton, to: BPButtonEnabling.self).isEnabled = enabled
    }

    private func isOkButtonEnabled() -> Bool {
        guard let okButton else { return false }
        if let button = okButton as? NSButton {
            return button.isEnabled
        }
        return unsafeBitCast(okButton, to: BPButtonEnabling.self).isEnabled
    }

    @objc open func setupUI() {
        let messagesMap = Self.sharedTaskMessagesMap()
        let font = BPStyle.defaultFixedWidthFont()
        if recordTextView == nil {
            recordTextView = BPAutoScrollTextView(frame: NSRect(x: 0, y: 0, width: 344, height: 162))
        }
        if windowTitleLabel == nil {
            windowTitleLabel = NSTextField(labelWithString: "")
        }
        if formulaNameLabel == nil {
            formulaNameLabel = NSTextField(labelWithString: "")
        }
        if okButton == nil {
            okButton = NSButton(title: NSLocalizedString("Generic_OK", comment: ""), target: self, action: #selector(okAction(_:)))
        }
        if cancelButton == nil {
            cancelButton = NSButton(title: NSLocalizedString("Generic_Cancel", comment: ""), target: self, action: #selector(cancelAction(_:)))
        }
        recordTextView?.font = font
        progressIndicator?.setAccessibilityLabel(NSLocalizedString("VoiceOver_Operation_Progress", comment: ""))
        windowTitleLabel?.stringValue = messagesMap[NSNumber(value: windowOperation.rawValue)] ?? ""

        let count = formulae?.count ?? 0
        if count >= 1 {
            let names = namesOfAllFormulae().joined(separator: ", ")
            formulaNameLabel?.stringValue = names
        } else {
            if windowOperation != .cleanup {
                formulaNameLabel?.stringValue = NSLocalizedString("Installation_Window_All_Formulae", comment: "")
            } else {
                formulaNameLabel?.stringValue = ""
            }
        }

        operationStatus = false
        isRunningTask = true

        if installationHost == nil,
           let rawWin = sheetWindowObject(),
           rawWin.isKind(of: NSWindow.self),
           let realWin = rawWin as? NSWindow,
           let contentView = realWin.contentView,
           let recordTextView {
            let host = BPInstallationHost(recordTextView: recordTextView)
            host.onCancel = { [weak self] in
                self?.cancelAction(nil)
            }
            host.onOK = { [weak self] in
                self?.okAction(nil)
            }
            self.installationHost = host

            for subview in contentView.subviews {
                subview.removeFromSuperview()
            }
            let hostView = host.viewController.view
            hostView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(hostView)
            NSLayoutConstraint.activate([
                hostView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
        syncInstallationHostState()
    }

    @objc open func syncInstallationHostState() {
        guard let installationHost else { return }
        installationHost.update(
            windowTitle: windowTitleLabel?.stringValue ?? "",
            formulaNames: formulaNameLabel?.stringValue ?? "",
            running: isRunningTask,
            okEnabled: isOkButtonEnabled(),
            cancelEnabled: cancelButton?.isEnabled ?? true
        )
    }

    @objc(runWithOperation:formulae:options:)
    open class func run(
        withOperation windowOperation: BPWindowOperation,
        formulae: [Any]?,
        options: [Any]?
    ) -> Self {
        return run(withOperation: windowOperation, formulae: formulae, options: options, completion: nil)
    }

    @objc(runWithOperation:formulae:options:zap:)
    open class func run(
        withOperation windowOperation: BPWindowOperation,
        formulae: [Any]?,
        options: [Any]?,
        zap: Bool
    ) -> Self {
        let controller = run(withOperation: windowOperation, formulae: formulae, options: options, completion: nil)
        controller.zapCask = zap
        return controller
    }

    @objc(runWithOperation:formulae:options:completion:)
    open class func run(
        withOperation windowOperation: BPWindowOperation,
        formulae: [Any]?,
        options: [Any]?,
        completion completionBlock: ((Bool) -> Void)?
    ) -> Self {
        let operationWindowController = self.init(windowNibName: "BPInstallationWindow")
        operationWindowController.windowOperation = windowOperation
        operationWindowController.formulae = formulae
        operationWindowController.options = options
        operationWindowController.completionBlock = completionBlock

        if let del = self.applicationDelegate() {
            let delProxy = unsafeBitCast(del, to: BPSheetDelegateRecorderMessaging.self)
            delProxy.setRunningBackgroundTask?(true)
            if let sheetWin = operationWindowController.sheetWindowObject() {
                if let parentWin = delProxy.window ?? nil {
                    unsafeBitCast(parentWin, to: BPSheetWindowMessaging.self).beginSheet(sheetWin) { _ in
                        MainActor.assumeIsolated {
                            operationWindowController.cleanupAfterTask()
                        }
                    }
                }
            }
        }
        operationWindowController.executeInstallation()
        return operationWindowController
    }

    @objc open func cleanupAfterTask() {
        if let del = type(of: self).applicationDelegate() {
            unsafeBitCast(del, to: BPSheetDelegateRecorderMessaging.self).setRunningBackgroundTask?(false)
        }
        completionBlock?(operationStatus)
    }

    @objc open func namesOfAllFormulae() -> [String] {
        guard let formulae else { return [] }
        return formulae.compactMap { bpAsFormula($0)?.name }
    }

    @objc open func executeInstallation() {
        isRunningTask = true
        setOkButtonEnabled(false)
        progressIndicator?.startAnimation(nil)
        syncInstallationHostState()
        if windowOperation == .upgrade && formulae != nil {
            upgradeProgress = Progress(totalUnitCount: 1)
        }

        let op = self.windowOperation
        nonisolated(unsafe) let capturedFormulae = self.formulae
        nonisolated(unsafe) let capturedOptions = self.options
        let capturedZap = self.zapCask
        let capturedProgress = self.upgradeProgress
        let tv = self.recordTextView

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let displayTerminalOutput: @Sendable (String) -> Void = { output in
                tv?.appendOutput(output)
                DispatchQueue.main.async {
                    self?.installationHost?.syncLogFromTextView()
                }
            }

            guard let homebrewInterface = bpSharedHomebrewInterface() else {
                self?.finishTask()
                return
            }

            var statusResult = false
            var upResult: BPUpgradeResult?

            if op == .install {
                if let formula = bpAsFormula(capturedFormulae?.first) {
                    if formula.cask {
                        statusResult = homebrewInterface.installCask(formula.name, withReturnBlock: displayTerminalOutput)
                    } else {
                        statusResult = homebrewInterface.installFormula(formula.name, withOptions: capturedOptions, andReturnBlock: displayTerminalOutput)
                    }
                }
            } else if op == .uninstall {
                if let formula = bpAsFormula(capturedFormulae?.first) {
                    if formula.cask {
                        statusResult = homebrewInterface.uninstallCask(formula.name, zap: capturedZap, withReturnBlock: displayTerminalOutput)
                    } else {
                        statusResult = homebrewInterface.uninstallFormula(formula.name, withReturnBlock: displayTerminalOutput)
                    }
                }
            } else if op == .upgrade {
                let res = homebrewInterface.upgradeSelectionReporting(capturedFormulae ?? [], progress: capturedProgress, withReturnBlock: displayTerminalOutput)
                upResult = res
                statusResult = res?.succeeded ?? false
                for batch in res?.batches ?? [] {
                    let statusKey: String
                    switch batch.status {
                    case .succeeded:   statusKey = "Updates_Command_Succeeded"
                    case .failed:      statusKey = "Updates_Command_Failed"
                    case .cancelled:   statusKey = "Updates_Command_Cancelled"
                    case .unattempted: statusKey = "Updates_Command_Unattempted"
                    @unknown default:  statusKey = "Updates_Command_Failed"
                    }
                    let line = String(format: NSLocalizedString(statusKey, comment: ""), batch.arguments.joined(separator: " "))
                    displayTerminalOutput("\n\(line)\n")
                }
            } else if op == .tap {
                if let formula = bpAsFormula(capturedFormulae?.first) {
                    statusResult = homebrewInterface.tapRepository(formula.name, withReturnsBlock: displayTerminalOutput)
                }
            } else if op == .untap {
                if let formula = bpAsFormula(capturedFormulae?.first) {
                    statusResult = homebrewInterface.untapRepository(formula.name, withReturnsBlock: displayTerminalOutput)
                }
            } else if op == .cleanup {
                statusResult = homebrewInterface.runCleanup(withReturnBlock: displayTerminalOutput)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.upgradeResult = upResult
                self.operationStatus = statusResult
                self.finishTask()
            }
        }
    }

    @objc nonisolated open func finishTask() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.upgradeWorkerFinished = true
            self.isRunningTask = false
            self.recordTextView?.flushPendingOutput()
            self.progressIndicator?.stopAnimation(nil)
            self.setOkButtonEnabled(true)
            self.cancelButton?.isEnabled = false

            let succeeded = self.operationStatus && !self.wasCancelled
            let cancelled = self.wasCancelled || (self.upgradeResult?.cancelled == true)
            let failureTitle = NSLocalizedString(cancelled ? "Updates_Task_Cancelled" : "Homebrew_Task_Failed", comment: "")
            let title = succeeded ? NSLocalizedString("Homebrew_Task_Finished", comment: "") : failureTitle
            let currentTitle = self.windowTitleLabel?.stringValue ?? ""
            let currentNames = self.formulaNameLabel?.stringValue ?? ""
            let desc = "\(currentTitle) \(currentNames)"

            self.windowTitleLabel?.stringValue = cancelled
                ? title
                : (succeeded ? currentTitle : "\(currentTitle) — \(failureTitle)")
            self.syncInstallationHostState()

            bpSharedAppDelegate()?.requestUserAttention(withMessageTitle: title, andDescription: desc)

            if let app = NSApp {
                NSAccessibility.post(
                    element: app,
                    notification: .announcementRequested,
                    userInfo: [
                        .announcement: title,
                        .priority: NSAccessibilityPriorityLevel.high.rawValue
                    ]
                )
            }
            if let okResponder = self.okButton as? NSResponder,
               let rawWin = self.sheetWindowObject(),
               rawWin.isKind(of: NSWindow.self),
               let realWin = rawWin as? NSWindow {
                realWin.makeFirstResponder(okResponder)
            }
        }
    }

    @objc(cancelAction:)
    open func cancelAction(_ sender: Any?) {
        wasCancelled = true
        cancelButton?.isEnabled = false
        setOkButtonEnabled(upgradeProgress == nil)
        if upgradeProgress != nil {
            windowTitleLabel?.stringValue = NSLocalizedString("Updates_Cancelling", comment: "")
        }
        syncInstallationHostState()

        let msgKey = upgradeProgress != nil ? "Updates_Cancelling" : "Installation_Window_Cancelled"
        recordTextView?.appendOutput("\n\(NSLocalizedString(msgKey, comment: ""))\n")
        recordTextView?.flushPendingOutput()
        installationHost?.syncLogFromTextView()

        upgradeProgress?.cancel()
        if let interface = bpSharedHomebrewInterface() {
            if upgradeProgress == nil || interface.brewTransport == BPBrewTransport.helper.rawValue {
                interface.cancelCurrentOperation()
            }
        }
    }

    @objc(okAction:)
    open func okAction(_ sender: Any?) {
        if upgradeProgress != nil && !upgradeWorkerFinished {
            return
        }
        recordTextView?.clearOutput()
        recordTextView?.string = ""
        installationHost?.syncLogFromTextView()

        if let sheetWin = sheetWindowObject() {
            if let mainWindow = unsafeBitCast(sheetWin, to: BPSheetWindowMessaging.self).sheetParent {
                unsafeBitCast(mainWindow, to: BPSheetWindowMessaging.self).endSheet(sheetWin)
            }
        }
    }
}

@MainActor
@objc(BPInertInstallationWindowController)
public final class BPInertInstallationWindowController: BPInstallationWindowController {
    @objc public var recordedWindow: AnyObject?
    @objc public var parentAtExecution: AnyObject?
    @objc public var busyAtExecution: Bool = false
    @objc public var executions: UInt = 0

    public override init(window: NSWindow?) {
        super.init(window: window)
        if let recorderClass = NSClassFromString("BPSheetWindowRecorder") as? NSObject.Type {
            self.recordedWindow = recorderClass.init()
        }
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func sheetWindowObject() -> AnyObject? {
        return recordedWindow
    }

    public override var window: NSWindow? {
        get {
            guard let recordedWindow else { return nil }
            let raw = Unmanaged.passUnretained(recordedWindow).toOpaque()
            return Unmanaged<NSWindow>.fromOpaque(raw).takeUnretainedValue()
        }
        set {
            recordedWindow = newValue
        }
    }

    public override func executeInstallation() {
        executions += 1
        if let win = sheetWindowObject() {
            parentAtExecution = unsafeBitCast(win, to: BPSheetWindowMessaging.self).sheetParent
        }
        if let app = NSApp as AnyObject? {
            let appProxy = unsafeBitCast(app, to: BPSheetAppRecorderMessaging.self)
            if let del = appProxy.delegate ?? nil {
                let delProxy = unsafeBitCast(del, to: BPSheetDelegateRecorderMessaging.self)
                busyAtExecution = delProxy.runningBackgroundTask?() ?? delProxy.isRunningBackgroundTask?() ?? false
            }
            appProxy.events??.add("execute")
        }
        self.operationStatus = true
    }
}

@objc(BPBrewfileImporting)
public protocol BPBrewfileImporting: NSObjectProtocol {
    @objc(importBrewfileAtURL:)
    func importBrewfile(at url: URL)
}

@objc(BPNotificationNavigationAction)
public enum BPNotificationNavigationAction: UInt, Sendable {
    case none = 0
    case outdatedFormulae = 1
    case outdatedCasks = 2
    case unifiedUpdates = 3
}

@objc(BPNotificationNavigation)
public protocol BPNotificationNavigation: NSObjectProtocol {
    @objc(showOutdatedFormulae:)
    func showOutdatedFormulae(_ sender: Any?)
    @objc(showOutdatedCasks:)
    func showOutdatedCasks(_ sender: Any?)
    @objc(showUnifiedUpdates:)
    func showUnifiedUpdates(_ sender: Any?)
}

@objc(BPNotificationPresenting)
public protocol BPNotificationPresenting: NSObjectProtocol {
    @objc func cleanupNotificationAlerts()
    @objc func activateCakebrewIgnoringOtherApps()
    @objc func showMainWindow()
}

@objc private protocol BPNotificationResponseMessaging: NSObjectProtocol {
    @objc optional func notification() -> AnyObject?
    @objc optional func request() -> AnyObject?
    @objc optional func content() -> AnyObject?
    @objc optional func userInfo() -> NSDictionary?
}

@objc private protocol BPTaggedSenderMessaging: NSObjectProtocol {
    @objc optional var tag: Int { get }
}

private func bpExtractNotificationUserInfo(from response: Any?) -> [AnyHashable: Any]? {
    guard let obj = response as AnyObject? else { return nil }
    let r1 = unsafeBitCast(obj, to: BPNotificationResponseMessaging.self)
    guard let notif = r1.notification?() else { return nil }
    let r2 = unsafeBitCast(notif, to: BPNotificationResponseMessaging.self)
    guard let req = r2.request?() else { return nil }
    let r3 = unsafeBitCast(req, to: BPNotificationResponseMessaging.self)
    guard let cont = r3.content?() else { return nil }
    let r4 = unsafeBitCast(cont, to: BPNotificationResponseMessaging.self)
    return r4.userInfo?() as? [AnyHashable: Any]
}

private let bpSIGTERMHandler: @convention(c) (Int32) -> Void = { sig in
    if sig == SIGTERM {
        bpSharedHomebrewManager()?.cleanUp()
    }
    Darwin.signal(sig, SIG_DFL)
}

@objc(BPAppDelegate)
public final class BPAppDelegate: NSObject, NSApplicationDelegate, BPNotificationPresenting, @unchecked Sendable {
    public static let homebrewWebsiteURLString = "https://www.cakebrew.com"
    public static let cakebrewDocumentationURLString = "https://github.com/scottdensmore/Cakebrew#readme"
    public static let cakebrewReleasesURLString = "https://github.com/scottdensmore/Cakebrew/releases"

    @IBOutlet @objc public var window: NSWindow?
    @objc public weak var dockActionTarget: (any BPDockMenuTarget)?

    private weak var _brewfileImportTarget: (any BPBrewfileImporting)?
    @objc public var brewfileImportTarget: (any BPBrewfileImporting)? {
        get { _brewfileImportTarget }
        set {
            _brewfileImportTarget = newValue
            if let target = newValue, let pending = pendingBrewfileURL {
                pendingBrewfileURL = nil
                target.importBrewfile(at: pending)
            }
        }
    }

    private weak var _notificationNavigationTarget: (any BPNotificationNavigation)?
    @objc public var notificationNavigationTarget: (any BPNotificationNavigation)? {
        get { _notificationNavigationTarget }
        set {
            #if DEBUG
            if newValue != nil && _notificationNavigationTarget == nil {
                queueMockNotificationBeforeTargetRegistration()
            }
            #endif
            _notificationNavigationTarget = newValue
            let pending = pendingNotificationNavigationAction
            if newValue != nil && pending != .none {
                pendingNotificationNavigationAction = .none
                navigate(forNotificationAction: pending)
            }
        }
    }

    private var _notificationPresenter: (any BPNotificationPresenting)?
    @objc public var notificationPresenter: any BPNotificationPresenting {
        get { _notificationPresenter ?? self }
        set { _notificationPresenter = newValue }
    }

    private var _runningBackgroundTask: Bool = false
    @objc public var runningBackgroundTask: Bool {
        @objc(isRunningBackgroundTask) get { _runningBackgroundTask }
        @objc(setRunningBackgroundTask:) set { _runningBackgroundTask = newValue }
    }

    @objc public private(set) var statusItem: NSStatusItem?

    private var preferencesWindowController: BPPreferencesWindowController?
    private var backgroundUpdater: BPBackgroundUpdater?
    private var appUpdateHost: BPAppUpdateHost?
    private var _aboutWindowController: DCOAboutWindowController?
    private var pendingBrewfileURL: URL?
    private var pendingNotificationNavigationAction: BPNotificationNavigationAction = .none
    #if DEBUG
    private var didQueueMockNotification: Bool = false
    #endif

    public override init() {
        super.init()
        if let proto = NSProtocolFromString("UNUserNotificationCenterDelegate") {
            class_addProtocol(BPAppDelegate.self, proto)
        }
    }

    @MainActor
    private var aboutWindowController: DCOAboutWindowController {
        if let existing = _aboutWindowController {
            return existing
        }
        let controller = DCOAboutWindowController()
        controller.appWebsiteURL = URL(string: Self.homebrewWebsiteURLString)
        _aboutWindowController = controller
        return controller
    }

    public func applicationDidFinishLaunching(_ aNotification: Notification) {
        BPPreferences.registerDefaults()
        setupSignalHandler()

        MainActor.assumeIsolated {
            if let appMenu = NSApp.mainMenu?.items.first?.submenu {
                _ = BPAppDelegate.installCheckForUpdatesMenuItem(inApplicationMenu: appMenu, target: self)
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(updatesSnapshotDidChangeForMenuBar(_:)),
                name: Notification.Name("BPHomebrewManagerUpdatesSnapshotDidChangeNotification"),
                object: nil
            )
            self.updateMenuBarExtra()
        }

        let updater = BPBackgroundUpdater()
        self.backgroundUpdater = updater
        updater.start()

        bpSharedHomebrewManager()?.reloadFromInterface(rebuildingCache: false)
        UNUserNotificationCenter.current().delegate = unsafeBitCast(self, to: UNUserNotificationCenterDelegate.self)
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainActor.assumeIsolated {
                self.window?.makeKeyAndOrderFront(self)
            }
        }
        cleanupTaskAlerts()
        return true
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        guard let brewfile = BPBrewfile.brewfileURLs(from: urls).first else {
            MainActor.assumeIsolated {
                self.displayBrewfileNotRecognized(forURLs: urls)
            }
            return
        }
        guard let target = brewfileImportTarget else {
            pendingBrewfileURL = brewfile
            return
        }
        target.importBrewfile(at: brewfile)
    }

    @objc(notificationNavigationActionForUserInfo:)
    public static func notificationNavigationAction(forUserInfo userInfo: [AnyHashable: Any]?) -> BPNotificationNavigationAction {
        guard let target = userInfo?[BPBackgroundUpdater.outdatedNotificationTargetKey] as? String else {
            return .none
        }
        if target == BPBackgroundUpdater.outdatedNotificationTargetFormulae {
            return .outdatedFormulae
        }
        if target == BPBackgroundUpdater.outdatedNotificationTargetCasks {
            return .outdatedCasks
        }
        if target == BPBackgroundUpdater.outdatedNotificationTargetMixed {
            return .unifiedUpdates
        }
        return .none
    }

    @objc(navigateForNotificationUserInfo:)
    public func navigate(forNotificationUserInfo userInfo: [AnyHashable: Any]?) {
        let action = Self.notificationNavigationAction(forUserInfo: userInfo)
        guard action != .none else { return }

        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.navigate(forNotificationAction: action)
            }
            return
        }
        navigate(forNotificationAction: action)
    }

    #if DEBUG
    private func queueMockNotificationBeforeTargetRegistration() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !didQueueMockNotification,
              arguments.contains("-BPMockBrew"),
              let targetIndex = arguments.firstIndex(of: "-BPMockNotificationTarget"),
              targetIndex + 1 < arguments.count else {
            return
        }
        didQueueMockNotification = true
        navigate(forNotificationUserInfo: [
            BPBackgroundUpdater.outdatedNotificationTargetKey: arguments[targetIndex + 1]
        ])
    }
    #endif

    private func navigate(forNotificationAction action: BPNotificationNavigationAction) {
        guard let target = notificationNavigationTarget else {
            pendingNotificationNavigationAction = action
            return
        }
        switch action {
        case .outdatedFormulae:
            target.showOutdatedFormulae(self)
        case .outdatedCasks:
            target.showOutdatedCasks(self)
        case .unifiedUpdates:
            target.showUnifiedUpdates(self)
        case .none:
            break
        @unknown default:
            break
        }
    }

    public func cleanupNotificationAlerts() {
        cleanupTaskAlerts()
    }

    public func activateCakebrewIgnoringOtherApps() {
        MainActor.assumeIsolated {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func showMainWindow() {
        MainActor.assumeIsolated {
            self.window?.makeKeyAndOrderFront(self)
        }
    }

    @MainActor
    private func displayBrewfileNotRecognized(forURLs urls: [URL]) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Brewfile_Not_Recognized_Title", comment: "")
        alert.informativeText = String.localizedStringWithFormat(
            NSLocalizedString("Brewfile_Not_Recognized_Body", comment: ""),
            urls.first?.lastPathComponent ?? ""
        )
        alert.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
        if let window = self.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }

    public func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let target = self.dockActionTarget
        let enabled = (target?.isHomebrewInstalled() == true)
            && !Self.shouldBlockOperation(whileRunningBackgroundTask: self.runningBackgroundTask)
        return BPDockMenu.dockMenu(withTarget: self, enabled: enabled)
    }

    @objc(performDockMenuAction:)
    public func performDockMenuAction(_ sender: Any?) {
        let tag = (sender as AnyObject?).flatMap { unsafeBitCast($0, to: BPTaggedSenderMessaging.self).tag } ?? 0
        guard let item = BPDockMenuItem(rawValue: tag),
              let action = BPDockMenu.controllerAction(for: item),
              let target = dockActionTarget as AnyObject?,
              target.responds(to: action) else {
            return
        }
        MainActor.assumeIsolated {
            NSApp.activate()
            self.window?.makeKeyAndOrderFront(self)
        }
        _ = target.perform(action, with: sender)
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        bpSharedHomebrewManager()?.cleanUp()
        return .terminateNow
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func cleanupTaskAlerts() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        MainActor.assumeIsolated {
            NSApplication.shared.dockTile.badgeLabel = nil
        }
    }

    @objc public static func urlForApplicationSupportFolder() -> URL? {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let path = base.appendingPathComponent("Cakebrew/")
            try FileManager.default.createDirectory(
                atPath: path.relativePath,
                withIntermediateDirectories: true,
                attributes: nil
            )
            return path
        } catch {
            return nil
        }
    }

    @objc public static func urlForApplicationCachesFolder() -> URL? {
        do {
            let base = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let path = base.appendingPathComponent("com.brunophilipe.Cakebrew/")
            try FileManager.default.createDirectory(
                atPath: path.relativePath,
                withIntermediateDirectories: true,
                attributes: nil
            )
            return path
        } catch {
            NSLog("Error creating Cakebrew cache directory: %@", "\(error)")
            return nil
        }
    }

    @objc public func displayBackgroundWarning() {
        MainActor.assumeIsolated {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Message_BGTask_Title", comment: "")
            alert.addButton(withTitle: NSLocalizedString("Generic_OK", comment: ""))
            alert.informativeText = NSLocalizedString("Message_BGTask_Body", comment: "")
            if let window = self.window {
                alert.beginSheetModal(for: window, completionHandler: nil)
            }
        }
    }

    @objc(requestUserAttentionWithMessageTitle:andDescription:)
    public func requestUserAttention(withMessageTitle title: String, andDescription desc: String) {
        MainActor.assumeIsolated {
            _ = NSApplication.shared.requestUserAttention(.informationalRequest)
            if !NSApplication.shared.isActive {
                NSApplication.shared.dockTile.badgeLabel = "●"
            }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = desc
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Error scheduling notification: %@", error as NSError)
            }
        }
    }

    @objc(showAboutWindow:)
    public func showAboutWindow(_ sender: Any?) {
        nonisolated(unsafe) let senderObj = sender
        MainActor.assumeIsolated {
            let about = self.aboutWindowController
            about.showWindow(senderObj)
            about.window?.becomeFirstResponder()
        }
    }

    @objc(openPreferences:)
    public func openPreferences(_ sender: Any?) {
        nonisolated(unsafe) let senderObj = sender
        MainActor.assumeIsolated {
            if self.preferencesWindowController == nil {
                let prefs = BPPreferencesWindowController()
                prefs.window?.center()
                self.preferencesWindowController = prefs
            }
            self.preferencesWindowController?.showWindow(senderObj)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @discardableResult
    @objc(installCheckForUpdatesMenuItemInApplicationMenu:target:)
    public static func installCheckForUpdatesMenuItem(inApplicationMenu appMenu: NSMenu?, target: AnyObject?) -> NSMenuItem? {
        guard let appMenu else { return nil }
        let action = #selector(BPAppDelegate.checkForAppUpdates(_:))
        let existingIndex = appMenu.indexOfItem(withTarget: target, andAction: action)
        if existingIndex >= 0 {
            return appMenu.item(at: existingIndex)
        }
        let title = Bundle.main.localizedString(
            forKey: "App_Update_Menu_Item",
            value: "Check for Updates…",
            table: nil
        )
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.setAccessibilityIdentifier("menu.app.checkForUpdates")
        let insertIndex = appMenu.numberOfItems > 1 ? 1 : appMenu.numberOfItems
        appMenu.insertItem(item, at: insertIndex)
        return item
    }

    @discardableResult
    @objc(installCommandPaletteMenuItemInToolsMenu:target:)
    public static func installCommandPaletteMenuItem(inToolsMenu toolsMenu: NSMenu?, target: AnyObject?) -> NSMenuItem? {
        guard let toolsMenu else { return nil }
        let action = NSSelectorFromString("showCommandPalette:")
        let existingIndex = toolsMenu.indexOfItem(withTarget: target, andAction: action)
        if existingIndex >= 0 {
            return toolsMenu.item(at: existingIndex)
        }
        let title = Bundle.main.localizedString(
            forKey: "Command_Palette_Menu_Item",
            value: "Command Palette…",
            table: nil
        )
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "k")
        item.keyEquivalentModifierMask = [.command]
        item.target = target
        item.setAccessibilityIdentifier("menu.tools.commandPalette")
        toolsMenu.insertItem(item, at: 0)
        if toolsMenu.numberOfItems > 1, toolsMenu.item(at: 1)?.isSeparatorItem == false {
            toolsMenu.insertItem(NSMenuItem.separator(), at: 1)
        }
        return item
    }

    @objc(updatesSnapshotDidChangeForMenuBar:)
    public func updatesSnapshotDidChangeForMenuBar(_ notification: Notification) {
        if statusItem != nil {
            updateMenuBarExtra()
        }
    }

    @objc public func updateMenuBarExtra() {
        MainActor.assumeIsolated {
            if !BPPreferences.showMenuBarExtra {
                if let item = self.statusItem {
                    NSStatusBar.system.removeStatusItem(item)
                    self.statusItem = nil
                }
                return
            }

            if self.statusItem == nil {
                self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            }

            let snapshot = bpSharedHomebrewManager()?.updatesSnapshot
            let outdatedCount = (snapshot?.formulae.count ?? 0) + (snapshot?.casks.count ?? 0)

            if let button = self.statusItem?.button {
                if let icon = NSImage(systemSymbolName: "mug.fill", accessibilityDescription: NSLocalizedString("Cakebrew", comment: "")) {
                    icon.isTemplate = true
                    button.image = icon
                }
                button.imagePosition = .imageLeading
                button.title = outdatedCount > 0 ? " \(outdatedCount)" : ""
                button.setAccessibilityIdentifier("menubar.statusItem")
            }

            let menu = NSMenu(title: NSLocalizedString("Cakebrew", comment: ""))
            let openTitle = Bundle.main.localizedString(forKey: "MenuBar_Open_Cakebrew", value: "Open Cakebrew", table: nil)
            let openItem = NSMenuItem(title: openTitle, action: #selector(openMainWindowFromMenuBar(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.setAccessibilityIdentifier("menubar.openCakebrew")
            menu.addItem(openItem)

            menu.addItem(NSMenuItem.separator())

            let updatesTitle = Bundle.main.localizedString(forKey: "Sidebar_Item_Unified_Updates", value: "Updates", table: nil)
            let updatesItem = NSMenuItem(title: updatesTitle, action: #selector(openUnifiedUpdatesFromMenuBar(_:)), keyEquivalent: "")
            updatesItem.target = self
            updatesItem.setAccessibilityIdentifier("menubar.unifiedUpdates")
            menu.addItem(updatesItem)

            let upgradeAllTitle = Bundle.main.localizedString(forKey: "Dock_Upgrade_All_Outdated", value: "Upgrade All Outdated", table: nil)
            let upgradeAllItem = NSMenuItem(title: upgradeAllTitle, action: #selector(upgradeAllFromMenuBar(_:)), keyEquivalent: "")
            upgradeAllItem.target = self
            upgradeAllItem.isEnabled = snapshot?.hasEligibleUpdates == true
            upgradeAllItem.setAccessibilityIdentifier("menubar.upgradeAll")
            menu.addItem(upgradeAllItem)

            let refreshTitle = Bundle.main.localizedString(forKey: "Dock_Check_For_Updates", value: "Check for Updates", table: nil)
            let refreshItem = NSMenuItem(title: refreshTitle, action: #selector(updateHomebrewFromMenuBar(_:)), keyEquivalent: "")
            refreshItem.target = self
            refreshItem.setAccessibilityIdentifier("menubar.checkUpdates")
            menu.addItem(refreshItem)

            self.statusItem?.menu = menu
        }
    }

    @objc(openMainWindowFromMenuBar:)
    public func openMainWindowFromMenuBar(_ sender: Any?) {
        activateCakebrewIgnoringOtherApps()
        showMainWindow()
    }

    @objc(openUnifiedUpdatesFromMenuBar:)
    public func openUnifiedUpdatesFromMenuBar(_ sender: Any?) {
        activateCakebrewIgnoringOtherApps()
        showMainWindow()
        notificationNavigationTarget?.showUnifiedUpdates(sender)
    }

    @objc(upgradeAllFromMenuBar:)
    public func upgradeAllFromMenuBar(_ sender: Any?) {
        activateCakebrewIgnoringOtherApps()
        showMainWindow()
        dockActionTarget?.upgradeAllOutdatedFormulae(sender)
    }

    @objc(updateHomebrewFromMenuBar:)
    public func updateHomebrewFromMenuBar(_ sender: Any?) {
        activateCakebrewIgnoringOtherApps()
        showMainWindow()
        dockActionTarget?.updateHomebrew(sender)
    }

    @MainActor
    private func ensureAppUpdateHost() -> BPAppUpdateHost {
        if let existing = appUpdateHost {
            existing.automaticCheckEnabled = BPPreferences.automaticAppUpdateCheckEnabled
            return existing
        }
        var version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        if version.isEmpty {
            version = "1.0.0"
        }
        let host = BPAppUpdateHost(
            currentVersion: version,
            automaticCheckEnabled: BPPreferences.automaticAppUpdateCheckEnabled
        )
        host.onToggleAutomaticCheck = { (enabled: Bool) in
            BPPreferences.automaticAppUpdateCheckEnabled = enabled
        }
        self.appUpdateHost = host
        return host
    }

    @objc(checkForAppUpdates:)
    public func checkForAppUpdates(_ sender: Any?) {
        MainActor.assumeIsolated {
            let host = self.ensureAppUpdateHost()
            host.performConfiguredCheck()
            host.showWindow()
        }
    }

    @objc(shouldBlockOperationWhileRunningBackgroundTask:)
    public static func shouldBlockOperation(whileRunningBackgroundTask isRunningBackgroundTask: Bool) -> Bool {
        return isRunningBackgroundTask
    }

    @objc(openWebsite:)
    public func openWebsite(_ sender: Any?) {
        if let url = URL(string: Self.homebrewWebsiteURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc(openDocumentation:)
    public func openDocumentation(_ sender: Any?) {
        if let url = URL(string: Self.cakebrewDocumentationURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc public func setupSignalHandler() {
        Darwin.signal(SIGTERM, bpSIGTERMHandler)
    }

    @objc(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:)
    public func handleNotificationCenter(
        _ center: Any?,
        didReceiveNotificationResponse response: Any?,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        nonisolated(unsafe) let userInfo = bpExtractNotificationUserInfo(from: response)
        let handleResponse: @Sendable () -> Void = { [weak self] in
            guard let self else {
                completionHandler()
                return
            }
            let presenter = self.notificationPresenter
            presenter.cleanupNotificationAlerts()
            presenter.activateCakebrewIgnoringOtherApps()
            presenter.showMainWindow()
            self.navigate(forNotificationUserInfo: userInfo)
            completionHandler()
        }

        if Thread.isMainThread {
            handleResponse()
        } else {
            DispatchQueue.main.async(execute: handleResponse)
        }
    }

    @objc(userNotificationCenter:willPresentNotification:withCompletionHandler:)
    public func handleNotificationCenter(
        _ center: Any?,
        willPresentNotification notification: Any?,
        withCompletionHandler completionHandler: @escaping @Sendable (UInt) -> Void
    ) {
        let options: UNNotificationPresentationOptions = [.banner, .sound]
        completionHandler(options.rawValue)
    }
}

// MARK: - Swift 6 Wave 8: BPHomebrewViewController

@objc(BPContentTab)
public enum BPContentTab: UInt, Sendable {
    @objc(kBPContentTabFormulae) case formulae = 0
    @objc(kBPContentTabDoctor) case doctor = 1
    @objc(kBPContentTabUpdate) case update = 2
    @objc(kBPContentTabServices) case services = 3
}

@MainActor
@objc(BPHomebrewViewController)
open class BPHomebrewViewController: NSViewController,
    BPDockMenuTarget,
    BPBrewfileImporting,
    BPNotificationNavigation,
    NSTableViewDelegate,
    BPFormulaeTableActionDelegate,
    BPSideBarControllerDelegate,
    BPSelectedFormulaViewControllerDelegate,
    BPHomebrewManagerDelegate,
    NSMenuDelegate,
    NSOpenSavePanelDelegate
{
    private static let kDefaultDetailPaneHeight: CGFloat = 120.0
    #if DEBUG
    private static let notificationSearchFixtureIdentifier = "mockvscode"
    #endif

    nonisolated(unsafe) private var _homebrewManager: BPHomebrewManager = BPHomebrewManager.sharedManager()
    private var didCommonInit: Bool = false

    @IBOutlet @objc open weak var sidebarController: BPSideBarController?
    @IBOutlet @objc open weak var formulaeTableView: BPFormulaeTableView?
    @IBOutlet @objc open weak var scrollView_formulae: NSScrollView?
    @IBOutlet @objc open weak var tabView: NSTabView?
    @IBOutlet @objc open weak var label_information: NSTextField?
    @IBOutlet @objc open weak var menu_formula: NSMenu?
    @IBOutlet @objc open weak var formulaeSplitView: NSSplitView?
    @IBOutlet @objc open weak var selectedFormulaView: NSView?
    @IBOutlet @objc open weak var backgroundActivityIndicator: NSProgressIndicator?
    @IBOutlet @objc open weak var mainWindowController: BPMainWindowController?

    @objc open private(set) var commandPaletteHost: BPCommandPaletteHost?
    @objc open private(set) var statusBarHost: BPStatusBarHost?

    // Cocoa bindings
    @objc dynamic open var enableUpgradeFormulasMenu: Bool = false
    @objc dynamic open var enableUpgradeAllMenu: Bool = false
    @objc dynamic open var currentFormula: BPFormula?

    @objc nonisolated public class func keyPathsForValuesAffectingCurrentFormulaPinned() -> Set<String> {
        ["currentFormula"]
    }

    @objc open var currentFormulaPinned: Bool {
        guard let currentFormula else { return false }
        return BPHomebrewManager.sharedManager().isFormulaPinned(currentFormula)
    }

    @objc open weak var appDelegate: BPAppDelegate?
    @objc open var lastSelectedSidebarIndex: Int = 0
    @objc open var hasAppliedDefaultDividerPosition: Bool = false

    private var _searchCoordinator: BPSearchCoordinator?
    @objc open var searchCoordinator: BPSearchCoordinator {
        get {
            if let existing = _searchCoordinator {
                return existing
            }
            let created = BPSearchCoordinator(
                performSearch: { query in
                    BPHomebrewManager.sharedManager().updateSearch(withName: query)
                },
                cancelSearch: {
                    BPHomebrewManager.sharedManager().cancelSearch()
                }
            )
            _searchCoordinator = created
            return created
        }
        set {
            _searchCoordinator = newValue
        }
    }

    @objc open var cleanupPreviewInFlight: Bool = false

    @objc open var searching: Bool {
        @objc(isSearching) get {
            searchCoordinator.searching
        }
    }

    @objc open var homebrewInstalled: Bool = true

    @objc(isHomebrewInstalled)
    nonisolated open func isHomebrewInstalled() -> Bool {
        MainActor.assumeIsolated {
            self.homebrewInstalled
        }
    }

    @objc open var formulaeDataSource: BPFormulaeDataSource?
    @objc open var installedPackageListHost: BPInstalledPackageListHost?
    @objc open var unifiedUpdatesHost: BPUnifiedUpdatesHost?
    @objc open var commandPaletteSheetWindow: NSWindow?
    @objc open var formulaOptionsWindowController: BPFormulaOptionsWindowController?
    @objc open var operationWindowController: NSWindowController?
    @objc open var updateViewController: BPUpdateViewController?
    @objc open var doctorViewController: BPDoctorViewController?
    @objc open var servicesViewController: BPServicesViewController?

    private var _formulaPopoverViewController: BPFormulaPopoverViewController?
    @objc open var formulaPopoverViewController: BPFormulaPopoverViewController {
        get {
            if let existing = _formulaPopoverViewController {
                return existing
            }
            let created = BPFormulaPopoverViewController()
            _ = created.view
            _formulaPopoverViewController = created
            return created
        }
        set {
            _formulaPopoverViewController = newValue
        }
    }

    @objc open var selectedFormulaeViewController: BPSelectedFormulaViewController?
    @objc open var toolbar: BPToolbar?
    @objc open var disabledView: BPDisabledView?
    @objc open var loadingView: BPLoadingView?

    public convenience init() {
        self.init(nibName: nil, bundle: nil)
    }

    public override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    @objc open func commonInit() {
        guard !didCommonInit else { return }
        didCommonInit = true

        _homebrewManager = BPHomebrewManager.sharedManager()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updatesSnapshotChanged(_:)),
            name: Notification.Name(BPHomebrewManagerUpdatesSnapshotDidChangeNotification),
            object: _homebrewManager
        )
        self.enableUpgradeAllMenu = (_homebrewManager.updatesSnapshot?.hasEligibleUpdates == true)
        _homebrewManager.delegate = self

        let selectedVC = BPSelectedFormulaViewController()
        selectedVC.delegate = self
        self.selectedFormulaeViewController = selectedVC

        self.homebrewInstalled = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveBackgroundActivityNotification(_:)),
            name: BPTask.didBeginBackgroundActivityNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveBackgroundActivityNotification(_:)),
            name: BPTask.didEndBackgroundActivityNotification,
            object: nil
        )
    }

    deinit {
        _homebrewManager.delegate = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc(updatesSnapshotChanged:)
    nonisolated open func updatesSnapshotChanged(_ notification: Notification) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.enableUpgradeAllMenu = (self._homebrewManager.updatesSnapshot?.hasEligibleUpdates == true)
                self.syncStatusBarHost()
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.enableUpgradeAllMenu = (self._homebrewManager.updatesSnapshot?.hasEligibleUpdates == true)
                self.syncStatusBarHost()
            }
        }
    }

    @objc(didReceiveBackgroundActivityNotification:)
    nonisolated open func didReceiveBackgroundActivityNotification(_ notification: Notification) {
        let name = notification.name
        if name == BPTask.didBeginBackgroundActivityNotification {
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.backgroundActivityIndicator?.startAnimation(self)
                    self.statusBarHost?.isBusy = true
                }
            } else {
                DispatchQueue.main.sync {
                    self.backgroundActivityIndicator?.startAnimation(self)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.statusBarHost?.isBusy = true
                }
            }
        } else if name == BPTask.didEndBackgroundActivityNotification {
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.backgroundActivityIndicator?.stopAnimation(self)
                    self.statusBarHost?.isBusy = false
                }
            } else {
                DispatchQueue.main.sync {
                    self.backgroundActivityIndicator?.stopAnimation(self)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.statusBarHost?.isBusy = false
                }
            }
        }
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        mainWindowController?.setUpViews()
        mainWindowController?.setContentViewHidden(true)

        let ds = BPFormulaeDataSource(mode: BPListMode.all.rawValue)
        self.formulaeDataSource = ds
        self.formulaeTableView?.dataSource = ds
        setUpInstalledPackageListHost()
        setUpUnifiedUpdatesHost()
        setUpStatusBarHost()

        if let sortColumn = BPPreferences.sortColumnIdentifier, !sortColumn.isEmpty {
            let ascending = BPPreferences.sortAscending
            let restored = NSSortDescriptor(key: sortColumn, ascending: ascending)
            formulaeTableView?.sortDescriptors = [restored]
            formulaeDataSource?.sortDescriptors = [restored]
            installedPackageListHost?.applySort(columnIdentifier: sortColumn, ascending: ascending)
        }
        formulaeTableView?.delegate = self
        formulaeTableView?.actionDelegate = self
        formulaeTableView?.setAccessibilityLabel(NSLocalizedString("Formulae", comment: ""))

        formulaeSplitView?.autosaveName = "BPFormulaeSplitView"

        if let tabView, tabView.tabViewItems.count > Int(BPContentTab.formulae.rawValue) {
            let formulaeTab = tabView.tabViewItem(at: Int(BPContentTab.formulae.rawValue))
            formulaeTab.view = formulaeSplitView
        }

        let updateVC = BPUpdateViewController(nibName: nil, bundle: nil)
        self.updateViewController = updateVC
        let updateView = updateVC.view
        if let tabView, tabView.tabViewItems.count > Int(BPContentTab.update.rawValue) {
            let updateTab = tabView.tabViewItem(at: Int(BPContentTab.update.rawValue))
            updateTab.view = updateView
        }

        let doctorVC = BPDoctorViewController(nibName: nil, bundle: nil)
        self.doctorViewController = doctorVC
        let doctorView = doctorVC.view
        if let tabView, tabView.tabViewItems.count > Int(BPContentTab.doctor.rawValue) {
            let doctorTab = tabView.tabViewItem(at: Int(BPContentTab.doctor.rawValue))
            doctorTab.view = doctorView
        }

        let servicesVC = BPServicesViewController(nibName: nil, bundle: nil)
        self.servicesViewController = servicesVC
        let servicesView = servicesVC.view
        if let tabView, tabView.tabViewItems.count > Int(BPContentTab.services.rawValue) {
            let servicesTab = tabView.tabViewItem(at: Int(BPContentTab.services.rawValue))
            servicesTab.view = servicesView
        }

        if let selectedVC = selectedFormulaeViewController, let container = selectedFormulaView {
            let detailView = selectedVC.view
            container.addSubview(detailView)
            detailView.translatesAutoresizingMaskIntoConstraints = false
            container.addConstraints(NSLayoutConstraint.constraints(
                withVisualFormat: "V:|-0-[view]-0-|",
                options: [],
                metrics: nil,
                views: ["view": detailView]
            ))
            container.addConstraints(NSLayoutConstraint.constraints(
                withVisualFormat: "H:|-0-[view]-0-|",
                options: [],
                metrics: nil,
                views: ["view": detailView]
            ))
        }

        sidebarController?.delegate = self
        sidebarController?.refreshSidebarBadges()
        sidebarController?.configureSidebarSettings()

        addToolbar()
        addLoadingView()

        let delegate = NSApplication.shared.delegate as? BPAppDelegate
        self.appDelegate = delegate
        delegate?.dockActionTarget = self
        delegate?.brewfileImportTarget = self
        delegate?.notificationNavigationTarget = self
        installCommandPaletteMenuItemIfAvailable()
        #if DEBUG
        installMockWarmNotificationMenu()
        installMockBrewfileMenu()
        #endif
    }

    #if DEBUG
    @objc open func installMockBrewfileMenu() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-BPMockBrew"),
              let index = arguments.firstIndex(of: "-BPMockBrewfileURL"),
              index + 1 < arguments.count else {
            return
        }
        let root = NSMenuItem(title: NSLocalizedString("Brewfile Test", comment: ""), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: root.title)
        let item = menu.addItem(
            withTitle: NSLocalizedString("Review Mock Brewfile", comment: ""),
            action: #selector(reviewMockBrewfile(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = arguments[index + 1]
        root.submenu = menu
        NSApp.mainMenu?.addItem(root)
    }

    @objc(reviewMockBrewfile:)
    open func reviewMockBrewfile(_ item: NSMenuItem) {
        guard let path = item.representedObject as? String else { return }
        importBrewfile(at: URL(fileURLWithPath: path))
    }

    @objc open func installMockWarmNotificationMenu() {
        let arguments = ProcessInfo.processInfo.arguments
        let targetIndex = arguments.firstIndex(of: "-BPMockWarmNotificationTarget")
        let hasWarmTarget = targetIndex != nil && (targetIndex! + 1) < arguments.count
        let holdsCatalog = arguments.contains("-BPMockHoldCatalogUntilReleased")
        guard arguments.contains("-BPMockBrew"), (hasWarmTarget || holdsCatalog) else { return }

        let root = NSMenuItem(title: NSLocalizedString("Notification Test", comment: ""), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: root.title)
        if hasWarmTarget, let targetIdx = targetIndex {
            let titles: [(String, Selector)] = [
                (NSLocalizedString("Search Mock Packages", comment: ""), #selector(beginMockNotificationSearch(_:))),
                (NSLocalizedString("Open Mock Notification", comment: ""), #selector(openMockNotification(_:))),
                (NSLocalizedString("Search Then Open Mock Notification", comment: ""), #selector(openMockNotificationDuringSearch(_:))),
                (NSLocalizedString("Search Then Clear Mock Search", comment: ""), #selector(clearMockSearchBeforeDebounce(_:)))
            ]
            for (title, action) in titles {
                let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
                item.target = self
                item.representedObject = arguments[targetIdx + 1]
            }
        }
        if holdsCatalog, let mockInterface = BPHomebrewInterface.sharedInterface() as? BPMockHomebrewInterface {
            let item = menu.addItem(
                withTitle: NSLocalizedString("Complete Mock Catalog", comment: ""),
                action: #selector(BPMockHomebrewInterface.releaseHeldCatalogs(_:)),
                keyEquivalent: ""
            )
            item.identifier = NSUserInterfaceItemIdentifier("mock.catalog.complete")
            item.target = mockInterface
        }
        root.submenu = menu
        NSApp.mainMenu?.addItem(root)
    }

    @objc(beginMockNotificationSearch:)
    open func beginMockNotificationSearch(_ sender: Any?) {
        toolbar?.searchField?.stringValue = Self.notificationSearchFixtureIdentifier
        performSearch(with: toolbar?.searchField?.stringValue ?? "")
    }

    @objc(openMockNotification:)
    open func openMockNotification(_ sender: NSMenuItem) {
        guard let target = sender.representedObject else { return }
        appDelegate?.navigate(forNotificationUserInfo: [BPBackgroundUpdater.outdatedNotificationTargetKey: target])
    }

    @objc(openMockNotificationDuringSearch:)
    open func openMockNotificationDuringSearch(_ sender: NSMenuItem) {
        beginMockNotificationSearch(sender)
        openMockNotification(sender)
    }

    @objc(clearMockSearchBeforeDebounce:)
    open func clearMockSearchBeforeDebounce(_ sender: Any?) {
        guard let field = toolbar?.searchField else { return }
        let change = Notification(name: NSControl.textDidChangeNotification, object: field)
        field.stringValue = Self.notificationSearchFixtureIdentifier
        field.delegate?.controlTextDidChange?(change)
        field.stringValue = ""
        field.delegate?.controlTextDidChange?(change)
    }
    #endif

    @objc open func addToolbar() {
        let tb = BPToolbar(identifier: NSToolbar.Identifier("MainToolbar"))
        tb.delegate = tb
        tb.controller = self
        self.toolbar = tb
        view.window?.toolbar = tb
        tb.displayMode = .iconOnly
        tb.lockItems()
    }

    @objc open func addDisabledView() {
        guard disabledView == nil else { return }
        let dv = BPDisabledView(frame: .zero)
        let manager = _homebrewManager
        dv.retryHandler = { [weak manager] in
            manager?.retryHomebrewDiscovery()
        }
        dv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dv)

        let referenceView = mainWindowController?.windowContentView ?? view
        NSLayoutConstraint.activate([
            NSLayoutConstraint(item: referenceView, attribute: .leading, relatedBy: .equal, toItem: dv, attribute: .leading, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: referenceView, attribute: .trailing, relatedBy: .equal, toItem: dv, attribute: .trailing, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: referenceView, attribute: .top, relatedBy: .equal, toItem: dv, attribute: .top, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: referenceView, attribute: .bottom, relatedBy: .equal, toItem: dv, attribute: .bottom, multiplier: 1, constant: 0)
        ])
        self.disabledView = dv
    }

    @objc open func addLoadingView() {
        let lv = BPLoadingView(frame: .zero)
        lv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lv)

        let referenceView = mainWindowController?.windowContentView ?? view
        NSLayoutConstraint.activate([
            NSLayoutConstraint(item: referenceView, attribute: .leading, relatedBy: .equal, toItem: lv, attribute: .leading, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: referenceView, attribute: .trailing, relatedBy: .equal, toItem: lv, attribute: .trailing, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: referenceView, attribute: .top, relatedBy: .equal, toItem: lv, attribute: .top, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: referenceView, attribute: .bottom, relatedBy: .equal, toItem: lv, attribute: .bottom, multiplier: 1, constant: 0)
        ])
        self.loadingView = lv
    }

    @objc open func applyDefaultDividerPositionIfNeeded() {
        guard !hasAppliedDefaultDividerPosition else { return }
        guard let splitView = formulaeSplitView else { return }
        let height = splitView.bounds.size.height
        guard height > 0 else { return }

        hasAppliedDefaultDividerPosition = true

        if let autosaveName = splitView.autosaveName, !autosaveName.isEmpty,
           UserDefaults.standard.object(forKey: "NSSplitView Subview Frames \(autosaveName)") != nil {
            return
        }

        splitView.setPosition(height - Self.kDefaultDetailPaneHeight, ofDividerAt: 0)
    }

    open override func viewDidLayout() {
        super.viewDidLayout()
        applyDefaultDividerPositionIfNeeded()
    }

    @objc(usesInstalledPackageListHostForMode:)
    open func usesInstalledPackageListHost(forMode mode: BPListMode) -> Bool {
        switch mode {
        case .all, .installed, .leaves, .pinned, .outdated, .search, .repositories, .installedCasks, .outdatedCasks, .allCasks:
            return true
        @unknown default:
            return false
        }
    }

    @objc open var isUsingUnifiedUpdatesHost: Bool {
        !searching && sidebarController?.sidebar?.selectedRow == Int(FormulaeSideBarItem.unifiedUpdates.rawValue)
    }

    @objc open var isUsingInstalledPackageListHost: Bool {
        guard !isUsingUnifiedUpdatesHost else { return false }
        let mode = BPListMode(rawValue: formulaeDataSource?.mode ?? 0) ?? .all
        return usesInstalledPackageListHost(forMode: mode)
    }

    @objc open func setUpUnifiedUpdatesHost() {
        let host = BPUnifiedUpdatesHost()
        host.onSelectionChanged = { [weak self] in
            guard let self, self.isUsingUnifiedUpdatesHost else { return }
            self.updateInterfaceItems()
        }
        host.onUpgradeSelected = { [weak self] _, _ in
            self?.upgradeSelectedFormulae(nil)
        }
        host.onUpgradeAll = { [weak self] in
            self?.upgradeAllOutdatedFormulae(nil)
        }
        self.unifiedUpdatesHost = host
    }

    @objc open func setUpStatusBarHost() {
        let host = BPStatusBarHost()
        host.onOpenCommandPalette = { [weak self] in
            self?.showCommandPalette(nil)
        }
        host.onOpenUnifiedUpdates = { [weak self] in
            self?.showUnifiedUpdates(nil)
        }
        self.statusBarHost = host

        if let footerContainer = label_information?.superview {
            label_information?.alphaValue = 0.0
            backgroundActivityIndicator?.alphaValue = 0.0
            let barView = host.viewController.view
            barView.translatesAutoresizingMaskIntoConstraints = false
            footerContainer.addSubview(barView)
            NSLayoutConstraint.activate([
                barView.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
                barView.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
                barView.bottomAnchor.constraint(equalTo: footerContainer.bottomAnchor),
                barView.heightAnchor.constraint(equalToConstant: 26.0)
            ])
        }
        syncStatusBarHost()
    }

    @objc open func syncStatusBarHost() {
        guard let statusBarHost else { return }
        let message = label_information?.stringValue ?? ""
        let installedCount = (_homebrewManager.installedFormulae?.count ?? 0) + (_homebrewManager.installedCasks?.count ?? 0)
        let outdatedCount = (_homebrewManager.outdatedFormulae?.count ?? 0) + (_homebrewManager.outdatedCasks?.count ?? 0)
        let pinnedCount = _homebrewManager.pinnedFormulae?.count ?? 0
        statusBarHost.update(
            message: message,
            isBusy: statusBarHost.isBusy,
            installedCount: installedCount,
            outdatedCount: outdatedCount,
            pinnedCount: pinnedCount
        )
    }

    @objc open func syncUnifiedUpdatesHostRows() {
        guard let unifiedUpdatesHost else { return }
        let formulae = _homebrewManager.outdatedFormulae ?? []
        var formulaNames: [String] = []
        var formulaVersions: [String] = []
        var formulaLatestVersions: [String] = []
        var formulaPinnedFlags: [NSNumber] = []
        formulaNames.reserveCapacity(formulae.count)
        formulaVersions.reserveCapacity(formulae.count)
        formulaLatestVersions.reserveCapacity(formulae.count)
        formulaPinnedFlags.reserveCapacity(formulae.count)

        for formula in formulae {
            formulaNames.append(formula.name ?? "")
            formulaVersions.append(formula.version ?? "")
            formulaLatestVersions.append(formula.shortLatestVersion ?? "")
            formulaPinnedFlags.append(NSNumber(value: _homebrewManager.isFormulaPinned(formula)))
        }

        let casks = _homebrewManager.outdatedCasks ?? []
        var caskNames: [String] = []
        var caskVersions: [String] = []
        var caskLatestVersions: [String] = []
        var caskPinnedFlags: [NSNumber] = []
        caskNames.reserveCapacity(casks.count)
        caskVersions.reserveCapacity(casks.count)
        caskLatestVersions.reserveCapacity(casks.count)
        caskPinnedFlags.reserveCapacity(casks.count)

        for cask in casks {
            caskNames.append(cask.name ?? "")
            caskVersions.append(cask.version ?? "")
            caskLatestVersions.append(cask.shortLatestVersion ?? "")
            caskPinnedFlags.append(NSNumber(value: _homebrewManager.isFormulaPinned(cask)))
        }

        unifiedUpdatesHost.update(
            formulaNames: formulaNames,
            formulaVersions: formulaVersions,
            formulaLatestVersions: formulaLatestVersions,
            formulaPinnedFlags: formulaPinnedFlags,
            caskNames: caskNames,
            caskVersions: caskVersions,
            caskLatestVersions: caskLatestVersions,
            caskPinnedFlags: caskPinnedFlags
        )
    }

    @objc open func setUpInstalledPackageListHost() {
        let host = BPInstalledPackageListHost()
        host.contextMenu = formulaeTableView?.menu

        host.onSelectionChanged = { [weak self] _, _ in
            guard let self, self.isUsingInstalledPackageListHost else { return }
            self.updateInterfaceItems()
        }
        host.onSortChanged = { [weak self] key, ascending in
            guard let self else { return }
            BPPreferences.sortColumnIdentifier = key
            BPPreferences.sortAscending = ascending
            if let key, !key.isEmpty {
                let descriptor = NSSortDescriptor(key: key, ascending: ascending)
                self.formulaeTableView?.sortDescriptors = [descriptor]
                self.formulaeDataSource?.sortDescriptors = [descriptor]
            } else {
                self.formulaeTableView?.sortDescriptors = []
                self.formulaeDataSource?.sortDescriptors = []
            }
        }
        host.onTableAction = { [weak self] request in
            guard let self, let req = BPFormulaeTableRequest(rawValue: request) else { return }
            self.handleInstalledPackageListAction(req)
        }
        host.onSpacePressed = { [weak self] in
            self?.showFormulaInfo(nil)
        }
        self.installedPackageListHost = host
    }

    @objc(sourceFormulaeForMode:)
    open func sourceFormulae(forMode mode: BPListMode) -> [BPFormula] {
        switch mode {
        case .all: return _homebrewManager.allFormulae ?? []
        case .installed: return _homebrewManager.installedFormulae ?? []
        case .leaves: return _homebrewManager.leavesFormulae ?? []
        case .pinned: return _homebrewManager.pinnedFormulae ?? []
        case .outdated: return _homebrewManager.outdatedFormulae ?? []
        case .search: return _homebrewManager.searchFormulae ?? []
        case .repositories: return _homebrewManager.repositoriesFormulae ?? []
        case .installedCasks: return _homebrewManager.installedCasks ?? []
        case .outdatedCasks: return _homebrewManager.outdatedCasks ?? []
        case .allCasks: return _homebrewManager.allCasks ?? []
        @unknown default: return []
        }
    }

    @objc open func syncInstalledPackageListHostRows() {
        guard let installedPackageListHost else { return }
        let descriptor = formulaeDataSource?.sortDescriptors?.first
        installedPackageListHost.applySort(
            columnIdentifier: descriptor?.key,
            ascending: descriptor?.ascending ?? true
        )

        let rawMode = formulaeDataSource?.mode ?? BPListMode.all.rawValue
        let mode = BPListMode(rawValue: rawMode) ?? .all
        let source = sourceFormulae(forMode: mode)
        let count = source.count
        var names: [String] = []
        var versions: [String] = []
        var latestVersions: [String] = []
        var statusRanks: [NSNumber] = []
        var pinnedFlags: [NSNumber] = []
        var caskFlags: [NSNumber] = []
        names.reserveCapacity(count)
        versions.reserveCapacity(count)
        latestVersions.reserveCapacity(count)
        statusRanks.reserveCapacity(count)
        pinnedFlags.reserveCapacity(count)
        caskFlags.reserveCapacity(count)

        for formula in source {
            names.append(formula.name ?? "")
            versions.append(formula.version ?? "")
            latestVersions.append(formula.shortLatestVersion ?? "")
            statusRanks.append(NSNumber(value: _homebrewManager.status(forFormula: formula).rawValue))
            pinnedFlags.append(NSNumber(value: _homebrewManager.isFormulaPinned(formula)))
            caskFlags.append(NSNumber(value: formula.cask))
        }

        installedPackageListHost.updateRowsForObjCMode(
            names: names,
            versions: versions,
            latestVersions: latestVersions,
            statusRanks: statusRanks,
            pinnedFlags: pinnedFlags,
            caskFlags: caskFlags,
            objcListMode: rawMode
        )
    }

    @objc(embedHostView:inContainer:)
    open func embedHostView(_ hostView: NSView?, inContainer container: NSView?) {
        guard let container, let hostView else { return }
        if hostView.superview !== container {
            hostView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(hostView)
            NSLayoutConstraint.activate([
                hostView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hostView.topAnchor.constraint(equalTo: container.topAnchor),
                hostView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        hostView.isHidden = false
    }

    @objc open func updateActiveListSurfaceVisibility() {
        let container = scrollView_formulae?.superview
        let installedView = installedPackageListHost?.viewController.view
        let unifiedView = unifiedUpdatesHost?.viewController.view
        if isUsingUnifiedUpdatesHost {
            scrollView_formulae?.isHidden = true
            if installedView?.superview != nil { installedView?.removeFromSuperview() }
            embedHostView(unifiedView, inContainer: container)
        } else if isUsingInstalledPackageListHost {
            scrollView_formulae?.isHidden = true
            if unifiedView?.superview != nil { unifiedView?.removeFromSuperview() }
            embedHostView(installedView, inContainer: container)
        } else {
            if installedView?.superview != nil { installedView?.removeFromSuperview() }
            if unifiedView?.superview != nil { unifiedView?.removeFromSuperview() }
            scrollView_formulae?.isHidden = false
        }
    }

    @objc(handleInstalledPackageListAction:)
    open func handleInstalledPackageListAction(_ request: BPFormulaeTableRequest) {
        guard let hostView = installedPackageListHost?.viewController.view else { return }
        guard isUsingInstalledPackageListHost,
              hostView.window != nil,
              !hostView.isHiddenOrHasHiddenAncestor,
              loadingView == nil,
              disabledView == nil,
              homebrewInstalled,
              appDelegate?.window?.attachedSheet == nil,
              let selectedTab = tabView?.selectedTabViewItem,
              tabView?.indexOfTabViewItem(selectedTab) == Int(BPContentTab.formulae.rawValue),
              appDelegate?.runningBackgroundTask != true else {
            return
        }
        guard let formulae = selectedFormulae(), !formulae.isEmpty else { return }
        var statuses: [NSNumber] = []
        statuses.reserveCapacity(formulae.count)
        for formula in formulae {
            statuses.append(NSNumber(value: _homebrewManager.status(forFormula: formula).rawValue))
        }
        let action = BPFormulaeTableActions.action(
            forRequest: request.rawValue,
            mode: formulaeDataSource?.mode ?? 0,
            formulae: formulae,
            statuses: statuses
        )
        switch action {
        case .install: installFormula(hostView)
        case .upgrade: upgradeSelectedFormulae(hostView)
        case .info: showFormulaInfo(hostView)
        case .uninstall: uninstallFormula(hostView)
        case .none: break
        @unknown default: break
        }
    }

    @objc open func updateInterfaceItems() {
        let selectedSidebarRow = sidebarController?.sidebar?.selectedRow ?? -1
        let selected = selectedFormulae() ?? []
        let selectedCount: UInt
        if isUsingUnifiedUpdatesHost {
            selectedCount = UInt(max(0, unifiedUpdatesHost?.selectedCount ?? 0))
        } else if isUsingInstalledPackageListHost {
            selectedCount = UInt(max(0, installedPackageListHost?.selectedCount ?? 0))
        } else {
            let selectedIndex = formulaeTableView?.selectedRow ?? -1
            selectedCount = selectedIndex >= 0 ? UInt(formulaeTableView?.selectedRowIndexes.count ?? 0) : 0
        }
        if selected.isEmpty {
            currentFormula = nil
        }

        let selectedStatus: BPFormulaStatus = selectedCount == 1
            ? BPHomebrewManager.sharedManager().status(forFormula: selectedFormula())
            : .notInstalled
        let toolbarMode = BPFormulaeTableActions.toolbarMode(
            forSidebarRow: selectedSidebarRow,
            selectedCount: selectedCount,
            selectedFormulaStatus: selectedStatus.rawValue
        )
        toolbar?.configure(for: toolbarMode)

        if searching
            || formulaeDataSource?.mode == BPListMode.search.rawValue
            || BPFormulaeTableActions.shouldShowFormulaInfo(forSidebarRow: selectedSidebarRow) {
            selectedFormulaView?.isHidden = false
            selectedFormulaeViewController?.formulae = selected
        } else {
            selectedFormulaView?.isHidden = true
        }
    }

    @objc open func configureForUnifiedUpdates() {
        formulaeTableView?.deselectAll(nil)
        installedPackageListHost?.deselectAll()
        unifiedUpdatesHost?.clearSelection()
        updateActiveListSurfaceVisibility()
        syncUnifiedUpdatesHostRows()
        updateInterfaceItems()
        refreshEmptyState()
    }

    @objc(configureTableForListing:)
    open func configureTable(forListing mode: BPListMode) {
        formulaeTableView?.deselectAll(nil)
        installedPackageListHost?.deselectAll()
        unifiedUpdatesHost?.clearSelection()
        formulaeDataSource?.mode = mode.rawValue
        formulaeTableView?.mode = mode
        updateActiveListSurfaceVisibility()
        if isUsingInstalledPackageListHost {
            syncInstalledPackageListHostRows()
        }
        formulaeTableView?.reloadData()
        updateInterfaceItems()
        refreshEmptyState()
    }

    @objc open func refreshEmptyState() {
        let container = scrollView_formulae?.superview ?? scrollView_formulae
        if isUsingUnifiedUpdatesHost {
            BPEmptyStateView.presentState(nil, over: container)
            return
        }
        let rows: Int
        if isUsingInstalledPackageListHost {
            rows = installedPackageListHost?.rowCount ?? 0
        } else if let tableView = formulaeTableView, let dataSource = formulaeDataSource {
            rows = dataSource.numberOfRows(in: tableView)
        } else {
            rows = 0
        }
        let loading = (loadingView != nil)

        var state: BPEmptyState?
        if BPEmptyState.shouldShow(forRowCount: rows, loading: loading) {
            state = BPEmptyState.state(
                forSidebarRow: sidebarController?.sidebar?.selectedRow ?? -1,
                searching: searching
            )
        }
        BPEmptyStateView.presentState(state, over: container)
    }

    // MARK: - Footer Information Label

    @objc open func updateInfoLabelWithSidebarSelection() {
        let selectedSidebarRow = sidebarController?.sidebar?.selectedRow ?? -1
        let key = BPFormulaeTableActions.footerLocalizationKey(
            forSidebarRow: selectedSidebarRow,
            searching: searching
        )
        let message = key.map { NSLocalizedString($0, comment: "") }
        updateInfoLabel(withText: message)
    }

    @objc(updateInfoLabelWithText:)
    open func updateInfoLabel(withText message: String?) {
        let resolved = message ?? ""
        label_information?.stringValue = resolved
        let window = view.window ?? appDelegate?.window
        window?.subtitle = resolved
        syncStatusBarHost()
    }

    // MARK: - Homebrew Manager Delegate

    @objc(homebrewManager:didBeginStepForMode:)
    nonisolated open func homebrewManager(_ manager: BPHomebrewManager, didBeginStepForMode mode: BPListMode) {
        MainActor.assumeIsolated {
            self.toolbar?.showsCancelReload = true
            guard !self.searching else { return }
            self.updateInfoLabel(withText: BPLoadingStatus.status(forListMode: mode.rawValue))
        }
    }

    @objc(homebrewManagerFinishedStepping:)
    nonisolated open func homebrewManagerFinishedStepping(_ manager: BPHomebrewManager) {
        MainActor.assumeIsolated {
            self.toolbar?.showsCancelReload = false
            guard !self.searching else { return }
            self.updateInfoLabelWithSidebarSelection()
        }
    }

    @IBAction @objc(cancelReload:)
    open func cancelReload(_ sender: Any?) {
        BPHomebrewManager.sharedManager().cancelReload()
    }

    @objc(homebrewManager:didPublishListForMode:)
    nonisolated open func homebrewManager(_ manager: BPHomebrewManager, didPublishListForMode mode: BPListMode) {
        MainActor.assumeIsolated {
            guard self.homebrewInstalled && !self.searching else { return }

            self.sidebarController?.refreshBadge(forListMode: mode.rawValue)
            self.syncStatusBarHost()

            if mode == .outdated {
                self.enableUpgradeFormulasMenu = !(manager.outdatedFormulae ?? []).isEmpty
            }

            if mode == .installed && self.loadingView != nil {
                self.revealContentForFirstPublishedList()
            }

            let isLoading = (self.loadingView != nil)
            let activeMode = self.formulaeDataSource?.mode ?? BPListMode.all.rawValue
            if BPFormulaeTableActions.shouldSyncUnifiedUpdates(
                forPublishedMode: mode.rawValue,
                isLoading: isLoading,
                isUsingUnifiedUpdatesHost: self.isUsingUnifiedUpdatesHost
            ) {
                self.syncUnifiedUpdatesHostRows()
                self.refreshEmptyState()
            } else if BPFormulaeTableActions.shouldRefreshVisibleList(
                forPublishedMode: mode.rawValue,
                activeMode: activeMode,
                isLoading: isLoading
            ) {
                self.formulaeDataSource?.refreshBackingArray()
                if self.isUsingInstalledPackageListHost {
                    self.syncInstalledPackageListHostRows()
                }
                self.formulaeTableView?.reloadData()
                self.refreshEmptyState()
            } else if BPFormulaeTableActions.shouldSyncInstalledHostMetadata(
                forPublishedMode: mode.rawValue,
                activeMode: activeMode,
                isLoading: isLoading,
                isUsingInstalledHost: self.isUsingInstalledPackageListHost
            ) || (!isLoading && self.isUsingInstalledPackageListHost && (mode == .installed || mode == .installedCasks)) {
                self.syncInstalledPackageListHostRows()
            }
        }
    }

    @objc open func revealContentForFirstPublishedList() {
        loadingView?.removeFromSuperview()
        loadingView = nil

        mainWindowController?.setContentViewHidden(false)
        label_information?.isHidden = false

        toolbar?.configure(for: .default)
        toolbar?.unlockItems()

        formulaeDataSource?.refreshBackingArray()
        updateActiveListSurfaceVisibility()
        if isUsingUnifiedUpdatesHost {
            syncUnifiedUpdatesHostRows()
        } else if isUsingInstalledPackageListHost {
            syncInstalledPackageListHostRows()
        }
        formulaeTableView?.reloadData()
        refreshEmptyState()
    }

    @objc(homebrewManagerFinishedUpdating:)
    nonisolated open func homebrewManagerFinishedUpdating(_ manager: BPHomebrewManager) {
        MainActor.assumeIsolated {
            self.loadingView?.removeFromSuperview()
            self.loadingView = nil

            guard self.homebrewInstalled else { return }

            self.formulaeTableView?.menu?.cancelTracking()

            let previouslySelectedFormula = self.currentFormula

            self.mainWindowController?.setContentViewHidden(false)
            self.label_information?.isHidden = false

            self.toolbar?.configure(for: .default)
            self.toolbar?.unlockItems()
            self.formulaeDataSource?.refreshBackingArray()

            let shouldReselectFirstRow = (self.sidebarController?.sidebar?.selectedRow ?? -1) < 0

            self.sidebarController?.refreshSidebarBadges()
            self.sidebarController?.sidebar?.reloadData()

            self.enableUpgradeFormulasMenu = !(BPHomebrewManager.sharedManager().outdatedFormulae ?? []).isEmpty

            if shouldReselectFirstRow {
                self.sidebarController?.sidebar?.selectRowIndexes(
                    IndexSet(integer: Int(FormulaeSideBarItem.installed.rawValue)),
                    byExtendingSelection: false
                )
            } else {
                self.sidebarController?.sidebar?.selectRowIndexes(
                    IndexSet(integer: max(0, self.lastSelectedSidebarIndex)),
                    byExtendingSelection: false
                )
            }

            self.restoreSelectedFormula(previouslySelectedFormula)
            self.refreshEmptyState()
        }
    }

    @objc(restoreSelectedFormula:)
    open func restoreSelectedFormula(_ formula: BPFormula?) {
        if isUsingUnifiedUpdatesHost {
            syncUnifiedUpdatesHostRows()
            return
        }
        if isUsingInstalledPackageListHost {
            syncInstalledPackageListHostRows()
            if let formula,
               installedPackageListHost?.selectPackage(named: formula.name ?? "", cask: formula.cask) == true {
                return
            }
            currentFormula = nil
            selectedFormulaeViewController?.formulae = nil
            return
        }

        let row = formula.map { formulaeDataSource?.indexOfFormula(named: $0.name ?? "", cask: $0.cask) ?? -1 } ?? -1
        if row < 0 {
            currentFormula = nil
            selectedFormulaeViewController?.formulae = nil
            return
        }
        formulaeTableView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        formulaeTableView?.scrollRowToVisible(row)
    }

    @objc(homebrewManager:didUpdateSearchResults:)
    nonisolated open func homebrewManager(_ manager: BPHomebrewManager, didUpdateSearchResults searchResults: [Any]?) {
        MainActor.assumeIsolated {
            self.loadSearchResults()
        }
    }

    @objc(homebrewManager:shouldDisplayNoBrewMessage:)
    nonisolated open func homebrewManager(_ manager: BPHomebrewManager, shouldDisplayNoBrewMessage yesOrNo: Bool) {
        MainActor.assumeIsolated {
            self.homebrewInstalled = !yesOrNo
            if yesOrNo {
                self.loadingView?.removeFromSuperview()
                self.loadingView = nil
                self.addDisabledView()
                self.disabledView?.showDiscoveryResult(manager.discoveryResult.rawValue, checking: manager.checkingHomebrew)
                self.label_information?.isHidden = true
                self.mainWindowController?.setContentViewHidden(true)
                self.toolbar?.lockItems()
            } else {
                self.disabledView?.removeFromSuperview()
                self.disabledView = nil
                if self.loadingView == nil {
                    self.addLoadingView()
                }
                self.toolbar?.lockItems()
            }
        }
    }

    @objc(homebrewManagerDidBeginDiscovery:)
    nonisolated open func homebrewManagerDidBeginDiscovery(_ manager: BPHomebrewManager) {
        MainActor.assumeIsolated {
            self.disabledView?.showDiscoveryResult(manager.discoveryResult.rawValue, checking: true)
        }
    }

    @objc(showFormulaInfoForCurrentlySelectedFormulaUsingInfoType:)
    open func showFormulaInfoForCurrentlySelectedFormula(usingInfoType type: BPFormulaInfoType) {
        let popover = formulaPopoverViewController.formulaPopover
        if popover?.isShown == true {
            popover?.close()
        }
        guard let formula = selectedFormula() else { return }

        formulaPopoverViewController.infoType = type
        formulaPopoverViewController.formula = formula

        if isUsingUnifiedUpdatesHost {
            if let anchorView = unifiedUpdatesHost?.viewController.view {
                popover?.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxX)
            }
            return
        }

        if isUsingInstalledPackageListHost {
            if let host = installedPackageListHost {
                let anchorView = host.viewController.view
                let anchorRect = host.rectOfSelectedRow(in: anchorView)
                popover?.show(relativeTo: anchorRect, of: anchorView, preferredEdge: .maxX)
            }
            return
        }

        guard let tableView = formulaeTableView, let scrollView = scrollView_formulae else { return }
        let selectedIndex = tableView.selectedRow
        var anchorRect = tableView.rect(ofRow: selectedIndex)
        anchorRect.origin = scrollView.convert(anchorRect.origin, from: tableView)
        popover?.show(relativeTo: anchorRect, of: scrollView, preferredEdge: .maxX)
    }

    // MARK: - Search Mode

    @objc open func loadSearchResults() {
        searchCoordinator.didReceiveResults(forSidebarRow: sidebarController?.sidebar?.selectedRow ?? 0)
        configureTable(forListing: .search)
    }

    @objc open func endSearchAndCleanup() {
        toolbar?.searchField?.stringValue = ""
        let originalRow = searchCoordinator.endSearchReturningSidebarRow()
        let row = BPSideBarController.restorableRow(
            from: originalRow,
            rowCount: sidebarController?.sidebar?.numberOfRows ?? 0
        )
        sidebarController?.sidebar?.selectRowIndexes(IndexSet(integer: Int(row.rawValue)), byExtendingSelection: false)
        updateInfoLabelWithSidebarSelection()
    }

    // MARK: - NSTableView Delegate

    @objc(formulaeTableView:requestAction:)
    nonisolated open func formulaeTableView(_ table: BPFormulaeTableView, requestAction request: BPFormulaeTableRequest) {
        let requestRaw = request.rawValue
        MainActor.assumeIsolated {
            guard table === self.formulaeTableView,
                  table.window != nil,
                  table.isEnabled,
                  !table.isHiddenOrHasHiddenAncestor,
                  self.loadingView == nil,
                  self.disabledView == nil,
                  self.homebrewInstalled,
                  self.appDelegate?.window?.attachedSheet == nil,
                  let selectedTab = self.tabView?.selectedTabViewItem,
                  self.tabView?.indexOfTabViewItem(selectedTab) == Int(BPContentTab.formulae.rawValue),
                  table.mode.rawValue == self.formulaeDataSource?.mode,
                  self.appDelegate?.runningBackgroundTask != true else {
                return
            }
            let rows = table.selectedRowIndexes
            guard !rows.isEmpty,
                  let lastRow = rows.last,
                  lastRow < table.numberOfRows,
                  let formulae = self.formulaeDataSource?.formulas(at: rows) as? [BPFormula],
                  formulae.count == rows.count else {
                return
            }
            var statuses: [NSNumber] = []
            statuses.reserveCapacity(formulae.count)
            for formula in formulae {
                statuses.append(NSNumber(value: self._homebrewManager.status(forFormula: formula).rawValue))
            }
            let action = BPFormulaeTableActions.action(
                forRequest: requestRaw,
                mode: table.mode.rawValue,
                formulae: formulae,
                statuses: statuses
            )
            switch action {
            case .install: self.installFormula(table)
            case .upgrade: self.upgradeSelectedFormulae(table)
            case .info: self.showFormulaInfo(table)
            case .uninstall: self.uninstallFormula(table)
            case .none: break
            @unknown default: break
            }
        }
    }

    open func tableViewSelectionDidChange(_ notification: Notification) {
        updateInterfaceItems()
    }

    // MARK: - BPSelectedFormulaViewController Delegate

    @objc(selectedFormulaViewDidUpdateFormulaInfoForFormula:)
    nonisolated open func selectedFormulaViewDidUpdateFormulaInfo(forFormula formula: Any?) {
        nonisolated(unsafe) let rawFormula = formula
        MainActor.assumeIsolated {
            if let f = rawFormula as? BPFormula {
                self.currentFormula = f
            }
        }
    }

    @objc(selectedFormulaViewDidRequestSelectRelatedFormulaNamed:)
    nonisolated open func selectedFormulaViewDidRequestSelectRelatedFormulaNamed(_ formulaName: String) {
        MainActor.assumeIsolated {
            guard !formulaName.isEmpty else { return }
            let isInstalled = (self._homebrewManager.installedFormulae ?? []).contains { $0.name == formulaName }
            let targetRow: FormulaeSideBarItem = isInstalled ? .installed : .all
            self.showOutdatedSidebarRow(targetRow)
            let formula = BPFormula.formula(withName: formulaName, version: nil, andLatestVersion: nil)
            formula.cask = false
            self.restoreSelectedFormula(formula)
        }
    }

    @objc nonisolated open func selectedFormulaViewDidRequestShowMoreInformation() {
        MainActor.assumeIsolated {
            self.showFormulaInfo(nil)
        }
    }

    @objc nonisolated open func selectedFormulaViewDidRequestOpenWebsite() {
        MainActor.assumeIsolated {
            self.openSelectedFormulaWebsite(nil)
        }
    }

    // MARK: - BPSideBarController Delegate

    @objc nonisolated open func sourceListSelectionDidChange() {
        MainActor.assumeIsolated {
            var tabIndex: BPContentTab = .formulae
            let selectedSidebarRow = self.sidebarController?.sidebar?.selectedRow ?? -1

            if self.searching {
                self.endSearchAndCleanup()
            }

            if selectedSidebarRow >= 0 {
                self.lastSelectedSidebarIndex = selectedSidebarRow
                BPPreferences.lastSelectedSidebarRow = selectedSidebarRow
            }

            self.formulaeTableView?.deselectAll(nil)
            self.installedPackageListHost?.deselectAll()
            self.unifiedUpdatesHost?.clearSelection()
            self.currentFormula = nil

            self.updateInterfaceItems()

            if selectedSidebarRow >= 0, let item = FormulaeSideBarItem(rawValue: UInt(selectedSidebarRow)) {
                switch item {
                case .installed:
                    self.configureTable(forListing: .installed)
                case .outdated:
                    self.configureTable(forListing: .outdated)
                case .all:
                    self.configureTable(forListing: .all)
                case .leaves:
                    self.configureTable(forListing: .leaves)
                case .pinned:
                    self.configureTable(forListing: .pinned)
                case .repositories:
                    self.configureTable(forListing: .repositories)
                case .installedCasks:
                    self.configureTable(forListing: .installedCasks)
                case .outdatedCasks:
                    self.configureTable(forListing: .outdatedCasks)
                case .allCasks:
                    self.configureTable(forListing: .allCasks)
                case .doctor:
                    tabIndex = .doctor
                case .update:
                    tabIndex = .update
                case .services:
                    tabIndex = .services
                    self.servicesViewController?.refreshServices()
                case .unifiedUpdates:
                    self.configureForUnifiedUpdates()
                case .formulaeCategory, .casksCategory, .toolsCategory:
                    break
                @unknown default:
                    break
                }
            }

            self.updateInfoLabelWithSidebarSelection()
            self.tabView?.selectTabViewItem(at: Int(tabIndex.rawValue))
            if tabIndex != .services {
                self.servicesViewController?.invalidateServiceDetails()
            }
        }
    }

    // MARK: - NSMenu Delegate

    open func menuNeedsUpdate(_ menu: NSMenu) {
        if isUsingInstalledPackageListHost {
            installedPackageListHost?.selectClickedRowIfNeeded()
            return
        }
        if let clickedRow = formulaeTableView?.clickedRow, clickedRow >= 0 {
            formulaeTableView?.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
    }

    // MARK: - IBActions

    @IBAction @objc(showFormulaInfo:)
    open func showFormulaInfo(_ sender: Any?) {
        showFormulaInfoForCurrentlySelectedFormula(usingInfoType: .general)
    }

    @IBAction @objc(showFormulaDependents:)
    open func showFormulaDependents(_ sender: Any?) {
        var onlyInstalledFormulae = true
        if let menuItem = sender as? NSMenuItem {
            onlyInstalledFormulae = !menuItem.isAlternate
        }
        let type: BPFormulaInfoType = onlyInstalledFormulae ? .installedDependents : .allDependents
        showFormulaInfoForCurrentlySelectedFormula(usingInfoType: type)
    }

    @IBAction @objc(installFormula:)
    open func installFormula(_ sender: Any?) {
        guard !hasBlockingBackgroundTask() else { return }
        guard let formula = selectedFormula(),
              let alert = BPPackageOperationPresenter.installAlert(forFormula: formula),
              let window = appDelegate?.window else {
            return
        }
        alert.beginSheetModal(for: window) { [weak self] returnCode in
            guard let self, returnCode == .alertFirstButtonReturn else { return }
            self.operationWindowController = BPInstallationWindowController.run(
                withOperation: .install,
                formulae: [formula],
                options: nil
            )
        }
    }

    @IBAction @objc(installFormulaWithOptions:)
    open func installFormulaWithOptions(_ sender: Any?) {
        guard !hasBlockingBackgroundTask() else { return }
        guard let formula = selectedFormula() else { return }
        if formula.cask {
            installFormula(sender)
            return
        }
        formulaOptionsWindowController = BPFormulaOptionsWindowController.runFormula(formula) { [weak self] options in
            guard let self else { return }
            self.operationWindowController = BPInstallationWindowController.run(
                withOperation: .install,
                formulae: [formula],
                options: options as? [String]
            )
        }
    }

    @IBAction @objc(uninstallFormula:)
    open func uninstallFormula(_ sender: Any?) {
        guard !hasBlockingBackgroundTask() else { return }
        guard let formula = selectedFormula(),
              let alert = BPPackageOperationPresenter.uninstallAlert(
                  forFormula: formula,
                  initialZapState: BPPreferences.zapCasksOnUninstall
              ),
              let window = appDelegate?.window else {
            return
        }
        let zapCheckbox = alert.accessoryView as? NSButton
        alert.beginSheetModal(for: window) { [weak self] returnCode in
            guard let self, returnCode == .alertFirstButtonReturn else { return }
            let zap = (zapCheckbox?.state == .on)
            if zapCheckbox != nil {
                BPPreferences.zapCasksOnUninstall = zap
            }
            self.operationWindowController = BPInstallationWindowController.run(
                withOperation: .uninstall,
                formulae: [formula],
                options: nil,
                zap: zap
            )
        }
    }

    @IBAction @objc(pinSelectedFormula:)
    open func pinSelectedFormula(_ sender: Any?) {
        guard let formula = selectedFormula(), !formula.cask else { return }
        _ = BPHomebrewInterface.sharedInterface().pinFormula(formula.name, withReturnBlock: nil)
    }

    @IBAction @objc(unpinSelectedFormula:)
    open func unpinSelectedFormula(_ sender: Any?) {
        guard let formula = selectedFormula(), !formula.cask else { return }
        _ = BPHomebrewInterface.sharedInterface().unpinFormula(formula.name, withReturnBlock: nil)
    }

    @IBAction @objc(upgradeSelectedFormulae:)
    open func upgradeSelectedFormulae(_ sender: Any?) {
        guard !hasBlockingBackgroundTask() else { return }
        guard let selectedFormulae = selectedFormulae(),
              let alert = BPPackageOperationPresenter.upgradeAlert(forFormulae: selectedFormulae),
              let window = appDelegate?.window else {
            return
        }
        alert.beginSheetModal(for: window) { [weak self] returnCode in
            guard let self, returnCode == .alertFirstButtonReturn else { return }
            self.operationWindowController = BPInstallationWindowController.run(
                withOperation: .upgrade,
                formulae: selectedFormulae,
                options: nil
            )
        }
    }

    @IBAction @objc(upgradeAllOutdatedFormulae:)
    nonisolated open func upgradeAllOutdatedFormulae(_ sender: Any?) {
        MainActor.assumeIsolated {
            guard !self.hasBlockingBackgroundTask() else { return }
            let snapshot = self._homebrewManager.updatesSnapshot
            guard let alert = BPPackageOperationPresenter.upgradeAllAlert(forSnapshot: snapshot),
                  let window = self.appDelegate?.window else {
                return
            }
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .alertFirstButtonReturn, !self.hasBlockingBackgroundTask() else { return }
                guard let selection = self._homebrewManager.selection(forConfirmedUpdatesSnapshot: snapshot),
                      !selection.isEmpty else {
                    let changed = BPPackageOperationPresenter.updatesChangedAlert()
                    if let win = self.appDelegate?.window {
                        changed.beginSheetModal(for: win, completionHandler: nil)
                    }
                    return
                }
                self.operationWindowController = BPInstallationWindowController.run(
                    withOperation: .upgrade,
                    formulae: selection,
                    options: nil
                )
            }
        }
    }

    @IBAction @objc(tapRepository:)
    open func tapRepository(_ sender: Any?) {
        guard !hasBlockingBackgroundTask() else { return }
        let alert = BPPackageOperationPresenter.tapInputAlert()
        let input = BPPackageOperationPresenter.tapInputHost(for: alert)?.inputField
        guard let window = appDelegate?.window else { return }

        alert.beginSheetModal(for: window) { [weak self] returnCode in
            guard let self, returnCode == .alertFirstButtonReturn else { return }
            let name = (input?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            guard BPHomebrewInterface.isValidTapName(name) else {
                let error = BPPackageOperationPresenter.invalidTapAlert()
                if let win = self.appDelegate?.window {
                    error.beginSheetModal(for: win, completionHandler: nil)
                }
                return
            }
            let lformula = BPFormula.formula(withName: name)
            self.operationWindowController = BPInstallationWindowController.run(
                withOperation: .tap,
                formulae: [lformula],
                options: nil
            )
        }
    }

    @IBAction @objc(untapRepository:)
    open func untapRepository(_ sender: Any?) {
        guard !hasBlockingBackgroundTask() else { return }
        guard let formula = selectedFormula(),
              let alert = BPPackageOperationPresenter.untapAlert(forFormula: formula),
              let window = appDelegate?.window else {
            return
        }
        alert.beginSheetModal(for: window) { [weak self] returnCode in
            guard let self, returnCode == .alertFirstButtonReturn else { return }
            self.operationWindowController = BPInstallationWindowController.run(
                withOperation: .untap,
                formulae: [formula],
                options: nil
            )
        }
    }

    @IBAction @objc(updateHomebrew:)
    nonisolated open func updateHomebrew(_ sender: Any?) {
        MainActor.assumeIsolated {
            self.sidebarController?.sidebar?.selectRowIndexes(
                IndexSet(integer: Int(FormulaeSideBarItem.update.rawValue)),
                byExtendingSelection: false
            )
            self.updateViewController?.runStopUpdate(nil)
        }
    }

    @IBAction @objc(showOutdatedFormulae:)
    nonisolated open func showOutdatedFormulae(_ sender: Any?) {
        MainActor.assumeIsolated {
            self.showOutdatedSidebarRow(.outdated)
        }
    }

    @IBAction @objc(showOutdatedCasks:)
    nonisolated open func showOutdatedCasks(_ sender: Any?) {
        MainActor.assumeIsolated {
            self.showOutdatedSidebarRow(.outdatedCasks)
        }
    }

    @IBAction @objc(showUnifiedUpdates:)
    nonisolated open func showUnifiedUpdates(_ sender: Any?) {
        MainActor.assumeIsolated {
            self.showOutdatedSidebarRow(.unifiedUpdates)
        }
    }

    @objc(showOutdatedSidebarRow:)
    open func showOutdatedSidebarRow(_ row: FormulaeSideBarItem) {
        toolbar?.searchField?.stringValue = ""
        searchCoordinator.cancelForNavigation()

        let alreadySelected = sidebarController?.sidebar?.selectedRow == Int(row.rawValue)
        sidebarController?.sidebar?.selectRowIndexes(
            IndexSet(integer: Int(row.rawValue)),
            byExtendingSelection: false
        )
        if alreadySelected {
            sourceListSelectionDidChange()
        }
    }

    @IBAction @objc(openSelectedFormulaWebsite:)
    open func openSelectedFormulaWebsite(_ sender: Any?) {
        guard let formula = selectedFormula(), let website = formula.website else { return }
        NSWorkspace.shared.open(website)
    }

    @objc(performSearchWithString:)
    open func performSearch(with searchPhrase: String?) {
        guard let searchPhrase, !searchPhrase.isEmpty else {
            endSearchAndCleanup()
            return
        }
        searchCoordinator.scheduleQuery(searchPhrase)
    }

    @IBAction @objc(beginFormulaSearch:)
    open func beginFormulaSearch(_ sender: Any?) {
        toolbar?.makeSearchFieldFirstResponder()
    }

    @objc open func installCommandPaletteMenuItemIfAvailable() {
        guard let items = NSApp.mainMenu?.items else { return }
        for topItem in items {
            guard let submenu = topItem.submenu else { continue }
            if submenu.indexOfItem(withTarget: self, andAction: #selector(updateHomebrew(_:))) >= 0 {
                BPAppDelegate.installCommandPaletteMenuItem(inToolsMenu: submenu, target: self)
                return
            }
        }
    }

    @objc(populateCommandPaletteHost:)
    open func populateCommandPaletteHost(_ host: BPCommandPaletteHost) {
        host.removeAllItems()

        let navigationEntries: [(String, String, String, String, FormulaeSideBarItem)] = [
            ("nav.installed", NSLocalizedString("Sidebar_Item_Installed", comment: ""), NSLocalizedString("Sidebar_Info_Installed", comment: ""), "checkmark.square", .installed),
            ("nav.outdated", NSLocalizedString("Sidebar_Item_Outdated", comment: ""), NSLocalizedString("Sidebar_Info_Outdated", comment: ""), "clock.arrow.circlepath", .outdated),
            ("nav.all", NSLocalizedString("Sidebar_Item_All", comment: ""), NSLocalizedString("Sidebar_Info_All", comment: ""), "books.vertical", .all),
            ("nav.leaves", NSLocalizedString("Sidebar_Item_Leaves", comment: ""), NSLocalizedString("Sidebar_Info_Leaves", comment: ""), "leaf", .leaves),
            ("nav.pinned", NSLocalizedString("Sidebar_Item_Pinned", comment: ""), NSLocalizedString("Sidebar_Info_Pinned", comment: ""), "pin", .pinned),
            ("nav.repos", NSLocalizedString("Sidebar_Item_Repos", comment: ""), NSLocalizedString("Sidebar_Info_Repos", comment: ""), "externaldrive", .repositories),
            ("nav.installedCasks", NSLocalizedString("Sidebar_Item_Installed", comment: ""), NSLocalizedString("Sidebar_Info_Casks", comment: ""), "macwindow.badge.plus", .installedCasks),
            ("nav.outdatedCasks", NSLocalizedString("Sidebar_Item_Outdated", comment: ""), NSLocalizedString("Sidebar_Info_OutdatedCasks", comment: ""), "arrow.down.app", .outdatedCasks),
            ("nav.allCasks", NSLocalizedString("Sidebar_Item_AllCasks", comment: ""), NSLocalizedString("Sidebar_Info_AllCasks", comment: ""), "square.grid.2x2", .allCasks),
            ("nav.doctor", NSLocalizedString("Sidebar_Item_Doctor", comment: ""), NSLocalizedString("Sidebar_Info_Doctor", comment: ""), "stethoscope", .doctor),
            ("nav.update", NSLocalizedString("Sidebar_Item_Update", comment: ""), NSLocalizedString("Sidebar_Info_Update", comment: ""), "arrow.triangle.2.circlepath", .update),
            ("nav.services", NSLocalizedString("Sidebar_Item_Services", comment: ""), NSLocalizedString("Sidebar_Info_Services", comment: ""), "gearshape.2", .services),
            ("nav.unifiedUpdates", NSLocalizedString("Sidebar_Item_Unified_Updates", comment: ""), NSLocalizedString("Sidebar_Info_Unified_Updates", comment: ""), "arrow.down.circle", .unifiedUpdates)
        ]

        for entry in navigationEntries {
            host.addNavigationItem(
                id: entry.0,
                title: entry.1,
                subtitle: entry.2,
                symbolName: entry.3,
                sidebarRow: Int(entry.4.rawValue)
            )
        }

        host.addActionItem(
            id: "action.updateHomebrew",
            title: NSLocalizedString("Toolbar_Homebrew_Update", comment: ""),
            subtitle: NSLocalizedString("Sidebar_Info_Update", comment: ""),
            symbolName: "arrow.triangle.2.circlepath",
            shortcutHint: "⌘U"
        )
        host.addActionItem(
            id: "action.upgradeAll",
            title: NSLocalizedString("Dock_Upgrade_All_Outdated", comment: ""),
            subtitle: NSLocalizedString("Sidebar_Info_Unified_Updates", comment: ""),
            symbolName: "arrow.down.circle.fill",
            shortcutHint: "⌥⌘U"
        )
        host.addActionItem(
            id: "action.cleanup",
            title: NSLocalizedString("Cleanup_Nothing_Title", comment: ""),
            subtitle: NSLocalizedString("Sidebar_VoiceOver_Tools", comment: ""),
            symbolName: "trash",
            shortcutHint: nil
        )
        host.addActionItem(
            id: "action.autoremove",
            title: NSLocalizedString("Remove Unused Dependencies", comment: ""),
            subtitle: NSLocalizedString("Sidebar_VoiceOver_Tools", comment: ""),
            symbolName: "scissors",
            shortcutHint: nil
        )
        host.addActionItem(
            id: "action.importBrewfile",
            title: NSLocalizedString("Import Brewfile", comment: ""),
            subtitle: NSLocalizedString("Review Brewfile", comment: ""),
            symbolName: "square.and.arrow.down",
            shortcutHint: nil
        )
        host.addActionItem(
            id: "action.exportBrewfile",
            title: NSLocalizedString("Panel_Export_Button", comment: ""),
            subtitle: NSLocalizedString("Panel_Export_Message", comment: ""),
            symbolName: "square.and.arrow.up",
            shortcutHint: nil
        )

        for formula in _homebrewManager.installedFormulae ?? [] {
            host.addPackageItem(
                name: formula.name ?? "",
                version: formula.version ?? "",
                cask: false
            )
        }
        for cask in _homebrewManager.installedCasks ?? [] {
            host.addPackageItem(
                name: cask.name ?? "",
                version: cask.version ?? "",
                cask: true
            )
        }
    }

    @IBAction @objc(showCommandPalette:)
    open func showCommandPalette(_ sender: Any?) {
        if commandPaletteHost == nil {
            let host = BPCommandPaletteHost()
            host.onNavigateToSidebarRow = { [weak self] row in
                guard let self, row >= 0, let item = FormulaeSideBarItem(rawValue: UInt(row)) else { return }
                self.showOutdatedSidebarRow(item)
            }
            host.onPerformAction = { [weak self] actionID in
                guard let self else { return }
                switch actionID {
                case "action.updateHomebrew":
                    self.updateHomebrew(nil)
                case "action.upgradeAll":
                    self.upgradeAllOutdatedFormulae(nil)
                case "action.cleanup":
                    self.runHomebrewCleanup(nil)
                case "action.autoremove":
                    self.removeUnusedDependencies(nil)
                case "action.importBrewfile":
                    self.runHomebrewImport(nil)
                case "action.exportBrewfile":
                    self.runHomebrewExport(nil)
                default:
                    break
                }
            }
            host.onSelectPackage = { [weak self] name, isCask in
                guard let self else { return }
                let targetRow: FormulaeSideBarItem = isCask ? .installedCasks : .installed
                self.showOutdatedSidebarRow(targetRow)
                let formula = BPFormula.formula(withName: name, version: nil, andLatestVersion: nil)
                formula.cask = isCask
                self.restoreSelectedFormula(formula)
            }
            host.onDismiss = { [weak self] in
                self?.dismissCommandPalette(nil)
            }
            self.commandPaletteHost = host
        }

        if let host = commandPaletteHost {
            populateCommandPaletteHost(host)
        }

        guard let parentWindow = view.window ?? appDelegate?.window,
              parentWindow.attachedSheet == nil else {
            return
        }

        if commandPaletteSheetWindow == nil, let host = commandPaletteHost {
            let sheet = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            sheet.title = NSLocalizedString("Command_Palette_Title", comment: "")
            sheet.contentViewController = host.viewController
            commandPaletteSheetWindow = sheet
        }

        if let sheet = commandPaletteSheetWindow {
            parentWindow.beginSheet(sheet, completionHandler: nil)
        }
    }

    @IBAction @objc(dismissCommandPalette:)
    open func dismissCommandPalette(_ sender: Any?) {
        let parentWindow = commandPaletteSheetWindow?.sheetParent ?? (view.window ?? appDelegate?.window)
        if let parentWindow, let sheet = commandPaletteSheetWindow {
            parentWindow.endSheet(sheet)
        }
    }

    @IBAction @objc(runHomebrewCleanup:)
    open func runHomebrewCleanup(_ sender: Any?) {
        guard !hasBlockingBackgroundTask(), !cleanupPreviewInFlight else { return }
        cleanupPreviewInFlight = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let preview = BPHomebrewInterface.sharedInterface().previewCleanup()
            DispatchQueue.main.async {
                guard let self else { return }
                self.cleanupPreviewInFlight = false
                self.presentCleanupConfirmation(for: preview)
            }
        }
    }

    @IBAction @objc(removeUnusedDependencies:)
    open func removeUnusedDependencies(_ sender: Any?) {
        guard !hasBlockingBackgroundTask(), appDelegate?.window?.attachedSheet == nil else { return }
        operationWindowController = BPAutoremoveWindowController.present(
            for: appDelegate?.window,
            interface: BPHomebrewInterface.sharedInterface(),
            manager: _homebrewManager
        )
    }

    @objc(presentCleanupConfirmationForPreview:)
    open func presentCleanupConfirmation(for preview: BPCleanupPreview) {
        guard !hasBlockingBackgroundTask(), let window = appDelegate?.window else { return }

        let alert = BPPackageOperationPresenter.cleanupAlert(for: preview)
        if preview.empty {
            alert.beginSheetModal(for: window, completionHandler: nil)
            return
        }

        alert.beginSheetModal(for: window) { [weak self] returnCode in
            guard let self, returnCode == .alertFirstButtonReturn else { return }
            self.operationWindowController = BPInstallationWindowController.run(
                withOperation: .cleanup,
                formulae: nil,
                options: nil
            )
        }
    }

    @IBAction @objc(runHomebrewExport:)
    open func runHomebrewExport(_ sender: Any?) {
        guard !hasBlockingBackgroundTask(), appDelegate?.window?.attachedSheet == nil else { return }
        appDelegate?.runningBackgroundTask = true

        let completion: (NSApplication.ModalResponse, URL?) -> Void = { [weak self] response, url in
            guard let self else { return }
            guard let destination = BPBrewfileExportOperation.exportURL(forSaveResponse: response.rawValue, url: url) else {
                self.appDelegate?.runningBackgroundTask = false
                return
            }
            DispatchQueue.main.async {
                self.operationWindowController = BPBundleWindowController.runExportOperation(withFile: destination)
            }
        }

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-BPMockBrew"),
           let index = arguments.firstIndex(of: "-BPMockExportURL"),
           index + 1 < arguments.count {
            let response: NSApplication.ModalResponse = arguments.contains("-BPMockExportCancel") ? .cancel : .OK
            completion(response, URL(fileURLWithPath: arguments[index + 1]))
            return
        }
        #endif

        guard let window = appDelegate?.window else {
            appDelegate?.runningBackgroundTask = false
            return
        }
        let savePanel = NSSavePanel()
        savePanel.nameFieldLabel = NSLocalizedString("Panel_Export_Message", comment: "")
        savePanel.prompt = NSLocalizedString("Panel_Export_Button", comment: "")
        savePanel.nameFieldStringValue = BPBrewfile.defaultFilename()
        savePanel.beginSheetModal(for: window) { response in
            completion(response, savePanel.url)
        }
    }

    @objc(importBrewfileAtURL:)
    nonisolated open func importBrewfile(at url: URL) {
        MainActor.assumeIsolated {
            guard !self.hasBlockingBackgroundTask(),
                  self.appDelegate?.window?.attachedSheet == nil else {
                return
            }
            self.appDelegate?.runningBackgroundTask = true
            let manager = BPHomebrewManager.sharedManager()
            let inventories = BPPackageOperationPresenter.brewfileInventories(
                forInstalledFormulae: manager.installedFormulae,
                installedCasks: manager.installedCasks,
                repositories: manager.repositoriesFormulae
            )
            BPBundleWindowController.reviewFile(url, inventories: inventories, parentWindow: self.appDelegate?.window) { [weak self] plan in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard let plan else {
                        self.appDelegate?.runningBackgroundTask = false
                        return
                    }
                    self.operationWindowController = BPBundleWindowController.runImportOperation(with: plan)
                }
            }
        }
    }

    @IBAction @objc(runHomebrewImport:)
    open func runHomebrewImport(_ sender: Any?) {
        guard !hasBlockingBackgroundTask(),
              appDelegate?.window?.attachedSheet == nil,
              let window = appDelegate?.window else {
            return
        }
        let openPanel = NSOpenPanel()
        openPanel.nameFieldLabel = NSLocalizedString("Panel_Import_Message", comment: "")
        openPanel.prompt = NSLocalizedString("Panel_Import_Button", comment: "")
        openPanel.nameFieldStringValue = BPBrewfile.defaultFilename()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.delegate = self

        openPanel.beginSheetModal(for: window) { [weak self] result in
            guard let self, let fileURL = openPanel.url, result.rawValue != 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.importBrewfile(at: fileURL)
            }
        }
    }

    @objc open func hasBlockingBackgroundTask() -> Bool {
        guard BPAppDelegate.shouldBlockOperation(whileRunningBackgroundTask: appDelegate?.runningBackgroundTask == true) else {
            return false
        }
        appDelegate?.displayBackgroundWarning()
        return true
    }

    @objc open func selectedFormula() -> BPFormula? {
        if isUsingUnifiedUpdatesHost {
            let selected = selectedFormulae()
            return selected?.count == 1 ? selected?.first : nil
        }
        if isUsingInstalledPackageListHost {
            guard let name = installedPackageListHost?.selectedPackageName, !name.isEmpty,
                  let ds = formulaeDataSource else {
                return nil
            }
            let index = ds.indexOfFormula(named: name, cask: installedPackageListHost?.selectedPackageCask == true)
            return ds.formula(at: index) as? BPFormula
        }
        guard let selectedIndex = formulaeTableView?.selectedRow else { return nil }
        return formulaeDataSource?.formula(at: selectedIndex) as? BPFormula
    }

    @objc open func selectedFormulae() -> [BPFormula]? {
        if isUsingUnifiedUpdatesHost {
            guard let host = unifiedUpdatesHost else { return nil }
            let resolved = BPPackageOperationPresenter.resolvedSelection(
                forFormulaNames: host.selectedFormulaNames,
                caskNames: host.selectedCaskNames,
                outdatedFormulae: _homebrewManager.outdatedFormulae,
                outdatedCasks: _homebrewManager.outdatedCasks
            ).compactMap { $0 as? BPFormula }
            return resolved.isEmpty ? nil : resolved
        }
        if isUsingInstalledPackageListHost {
            guard let host = installedPackageListHost else { return nil }
            let names = host.selectedPackageNames
            let casks = host.selectedPackageCasks
            guard !names.isEmpty, let ds = formulaeDataSource else { return nil }
            var selected: [BPFormula] = []
            selected.reserveCapacity(names.count)
            for (i, name) in names.enumerated() {
                let isCask = i < casks.count ? casks[i].boolValue : false
                let idx = ds.indexOfFormula(named: name, cask: isCask)
                if let formula = ds.formula(at: idx) as? BPFormula {
                    selected.append(formula)
                }
            }
            return selected.isEmpty ? nil : selected
        }
        guard let selectedIndexes = formulaeTableView?.selectedRowIndexes else { return nil }
        return formulaeDataSource?.formulas(at: selectedIndexes) as? [BPFormula]
    }

    @objc open func selectedFormulaNames() -> [String]? {
        selectedFormulae()?.compactMap(\.name)
    }

    // MARK: - Open Save Panels Delegate

    @objc(panel:shouldEnableURL:)
    nonisolated open func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        BPBrewfile.isBrewfileURL(url)
    }
}



