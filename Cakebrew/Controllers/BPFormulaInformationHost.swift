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

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                Text(BPSelectedFormulaLocalizedTitle("F2k-Nm-vhK.title", fallback: "Selected Formula Information"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("formula.detail.header")

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
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
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
        case .version, .latestVersion, .status:
            presentation.sortOrder = [KeyPathComparator(\BPInstalledPackageRow.version, order: order)]
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
                let column: BPInstalledPackageSortColumn = (first.keyPath == \BPInstalledPackageRow.name) ? .name : .version
                presentation.state.setSort(column: column, ascending: ascending)
                presentation.onSortChanged?(column.rawValue, ascending)
            }
        )
    }

    var body: some View {
        Table(presentation.state.displayedRows, selection: selectionBinding, sortOrder: sortOrderBinding) {
            TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                HStack(spacing: 4) {
                    Text(row.name)
                        .lineLimit(1)
                        .accessibilityValue(row.name)
                        .accessibilityIdentifier("package.row.\(row.name)")
                    if row.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: NSFont.smallSystemFontSize))
                            .accessibilityLabel(NSLocalizedString("Sidebar_Item_Pinned", comment: ""))
                    }
                }
            }
            TableColumn(BPMainMenuLocalizedTitle("h5d-xc-Jih.headerCell.title", fallback: "Version"), value: \.version) { row in
                Text(row.version)
                    .lineLimit(1)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .background(BPInstalledTableBridgeIntrospector(presentation: presentation))
    }
}
