import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

internal func BPMainMenuLocalizedTitle(_ key: String, fallback: String) -> String {
    Bundle.main.localizedString(forKey: key, value: fallback, table: "MainMenu")
}

@MainActor
private final class BPInstalledPackageListPresentation: ObservableObject {
    @Published var state = BPInstalledPackageListState()
    @Published var sortOrder: [KeyPathComparator<BPInstalledPackageRow>] = []
    var contextMenu: NSMenu?
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


}

@MainActor
@objc(BPInstalledPackageListHost)
public final class BPInstalledPackageListHost: NSObject {
    public var content: some View { BPInstalledPackageListView(presentation: presentation) }
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
        let host = NSHostingController(rootView: BPInstalledPackageListView(presentation: presentation))
        host.sizingOptions = []
        viewController = host
        super.init()

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
        presentation.notifySelectionChanged()
    }

    @objc public func selectClickedRowIfNeeded() { }

    @objc(rectOfSelectedRowInView:)
    public func rectOfSelectedRow(in targetView: NSView) -> NSRect {
        NSRect(x: targetView.bounds.midX, y: targetView.bounds.midY, width: 1, height: 1)
    }

    private func syncUnderlyingTableSelection() { }

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
private struct BPInstalledPackageListView: View {
    @ObservedObject var presentation: BPInstalledPackageListPresentation
    @State private var returningPackage: BPInstalledPackageRow?

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

    private func request(_ action: Int, for ids: Set<BPFormulaInformationIdentity>) {
        presentation.state.select(ids: ids)
        presentation.notifySelectionChanged()
        presentation.onTableAction?(action)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if presentation.state.mode == .pinned {
                HStack {
                    Spacer()
                    Button("Return to Latest Release…", systemImage: "arrow.up.circle") {
                        returningPackage = presentation.state.selectedRow
                    }
                    .disabled(presentation.state.selectedIDs.count != 1)
                    .accessibilityIdentifier("pinned.returnLatest")
                }
                .padding(.horizontal, 12).padding(.top, 8)
            }
            modeTable
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .accessibilityLabel(NSLocalizedString("Formulae", comment: ""))
                .contextMenu(forSelectionType: BPFormulaInformationIdentity.self) { ids in
                    if presentation.state.mode == .pinned {
                        Button("Return to Latest Release…") {
                            if let id = ids.first, ids.count == 1 {
                                returningPackage = presentation.state.displayedRows.first { $0.id == id }
                            }
                        }
                        .disabled(ids.count != 1)
                        Divider()
                    }
                    Button("Install or Upgrade…") { request(0, for: ids) }.disabled(ids.isEmpty)
                    Button("Uninstall…") { request(1, for: ids) }.disabled(ids.isEmpty)
                    Button("Package Inspector") {
                        presentation.state.select(ids: ids)
                        presentation.notifySelectionChanged()
                        presentation.onSpacePressed?()
                    }.disabled(ids.count != 1)
                } primaryAction: { ids in
                    presentation.state.select(ids: ids)
                    presentation.notifySelectionChanged()
                    presentation.onTableAction?(0)
                }
                .onKeyPress(.space) { presentation.onSpacePressed?(); return .handled }
                .onDeleteCommand { presentation.onTableAction?(1) }
        }
        .sheet(item: $returningPackage) { BPPinnedReturnSheet(row: $0) }
    }
}

