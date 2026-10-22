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
            Text(titleText)
                .font(.headline)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(titleIdentifier)
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
}

@MainActor
@objc(BPSelectedFormulaHost)
public final class BPSelectedFormulaHost: NSObject {
    private let presentation = BPSelectedFormulaPresentation()
    @objc public let viewController: NSViewController

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
                    if let path = copyableInstallPath {
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

    @objc public var selectedPackageName: String? {
        presentation.state.selectedRow?.name
    }

    @objc public var selectedPackageCask: Bool {
        presentation.state.selectedRow?.cask ?? false
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
        let previousSelection = presentation.state.selectedID
        presentation.state.replaceRows(rows, isCaskList: cask)
        syncUnderlyingTableSelection()
        if presentation.state.selectedID != previousSelection {
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
        let previousSelection = presentation.state.selectedID
        presentation.state.replaceRows(rows, mode: resolvedMode)
        syncUnderlyingTableSelection()
        if presentation.state.selectedID != previousSelection {
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
        presentation.ensureTableViewAttached()?.deselectAll(nil)
        presentation.notifySelectionChanged()
    }

    @objc public func selectClickedRowIfNeeded() {
        guard let tableView = presentation.ensureTableViewAttached() else { return }
        let clicked = tableView.clickedRow
        guard clicked >= 0 && clicked < presentation.state.displayedRows.count else { return }
        if presentation.state.selectRow(at: clicked) {
            tableView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
            presentation.notifySelectionChanged()
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
        let row = presentation.state.selectedRowIndex
        if row >= 0 && row < tableView.numberOfRows {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
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
        if let table = view as? NSTableView {
            return table
        }
        for subview in view.subviews {
            if let found = findTableView(in: subview) {
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

    private var selectionBinding: Binding<BPFormulaInformationIdentity?> {
        Binding(
            get: { presentation.state.selectedID },
            set: { newValue in
                let oldSelection = presentation.state.selectedID
                presentation.state.select(id: newValue)
                if presentation.state.selectedID != oldSelection {
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
    }

    @ViewBuilder
    private var modeTable: some View {
        let mode = presentation.state.mode
        if !mode.showsVersionColumn {
            Table(presentation.state.displayedRows, selection: selectionBinding, sortOrder: sortOrderBinding) {
                TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                    nameCell(row)
                }
            }
        } else if mode.showsLatestVersionColumn {
            Table(presentation.state.displayedRows, selection: selectionBinding, sortOrder: sortOrderBinding) {
                TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                    nameCell(row)
                }
                TableColumn(BPMainMenuLocalizedTitle("h5d-xc-Jih.headerCell.title", fallback: "Version"), value: \.version) { row in
                    Text(row.version)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                TableColumn(BPMainMenuLocalizedTitle("d93-10-421.headerCell.title", fallback: "Latest Version"), value: \.latestVersion) { row in
                    Text(row.latestVersion)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
            }
        } else if mode.showsStatusColumn {
            Table(presentation.state.displayedRows, selection: selectionBinding, sortOrder: sortOrderBinding) {
                TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                    nameCell(row)
                }
                TableColumn(BPMainMenuLocalizedTitle("h5d-xc-Jih.headerCell.title", fallback: "Version"), value: \.version) { row in
                    Text(row.version)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                }
                TableColumn(BPMainMenuLocalizedTitle("Be6-3F-p4b.headerCell.title", fallback: "Status"), value: \.statusRank) { row in
                    statusBadge(for: row.statusRank)
                }
            }
        } else {
            Table(presentation.state.displayedRows, selection: selectionBinding, sortOrder: sortOrderBinding) {
                TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                    nameCell(row)
                }
                TableColumn(BPMainMenuLocalizedTitle("h5d-xc-Jih.headerCell.title", fallback: "Version"), value: \.version) { row in
                    Text(row.version)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
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
    @Published var helperStatusText: String = ""
    @Published var helperActionTitle: String?

    var onBackgroundCheckChanged: ((Bool) -> Void)?
    var onIntervalChanged: ((Double) -> Void)?
    var onGreedyChanged: ((Bool) -> Void)?
    var onAutomaticAppUpdateCheckChanged: ((Bool) -> Void)?
    var onCheckForAppUpdates: (() -> Void)?
    var onHelperAction: (() -> Void)?
}

@MainActor
@objc(BPPreferencesHost)
public final class BPPreferencesHost: NSObject {
    private let presentation = BPPreferencesPresentation()
    @objc public let viewController: NSViewController

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
