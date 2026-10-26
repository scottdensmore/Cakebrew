import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

internal func BPMainMenuLocalizedTitle(_ key: String, fallback: String) -> String {
    Bundle.main.localizedString(forKey: key, value: fallback, table: "MainMenu")
}

@MainActor
final class BPInstalledPackageListPresentation: ObservableObject {
    @Published var state = BPInstalledPackageListState() {
        didSet { tableSelectionGeneration &+= 1 }
    }
    private var tableSelectionGeneration: UInt64 = 0
    @Published var summaries: [BPFormulaInformationIdentity: String] = [:]
    @Published var sortOrder: [KeyPathComparator<BPInstalledPackageRow>] = []
    var contextMenu: NSMenu?
    var isSyncingTableSelection = false
    var onSelectionChanged: ((String?, Bool) -> Void)?
    var onSortChanged: ((String?, Bool) -> Void)?
    var onTableAction: ((Int) -> Void)?
    var onSpacePressed: (() -> Void)?

    /// Table may write its selection binding during SwiftUI reconciliation.
    /// Publish the selection and notify the inspector after that update ends.
    /// A newer table request or any programmatic state change supersedes it.
    func selectFromTable(_ ids: Set<BPFormulaInformationIdentity>) {
        guard !isSyncingTableSelection else { return }
        tableSelectionGeneration &+= 1
        let generation = tableSelectionGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.tableSelectionGeneration == generation else { return }
            var next = self.state
            next.select(ids: ids)
            guard next.selectedIDs != self.state.selectedIDs else { return }
            self.state = next
            self.notifySelectionChanged()
        }
    }

    func receiveSummary(_ summary: String?, for identity: BPFormulaInformationIdentity) {
        guard state.index(ofName: identity.name, cask: identity.cask) >= 0,
              let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty, summaries[identity] != summary else { return }
        summaries[identity] = summary
    }

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

    /// The SwiftUI scene passes cached metadata directly, without fetching info
    /// or converting package rows into parallel Objective-C arrays.
    public func updatePackages(_ rows: [BPInstalledPackageRow], mode: BPPackageListMode) {
        let previousSelection = presentation.state.selectedIDs
        presentation.state.replaceRows(rows, mode: mode)
        let ids = Set(rows.map(\.id))
        presentation.summaries = presentation.summaries.filter { ids.contains($0.key) }
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
private struct BPPackageRowContent<Content: View>: View {
    @AppStorage(BPPreferences.compactPackageRowsKey) private var compactRows = false
    let alignment: Alignment
    private let content: Content

    init(alignment: Alignment = .leading, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        content.frame(maxWidth: .infinity, minHeight: compactRows ? 28 : 44, alignment: alignment)
    }
}

@MainActor
private struct BPPackageNameCell: View {
    @ObservedObject var presentation: BPInstalledPackageListPresentation
    @AppStorage(BPPreferences.compactPackageRowsKey) private var compactRows = false
    let row: BPInstalledPackageRow

    private var subtitle: String {
        if let summary = presentation.summaries[row.id] ?? row.summary { return summary }
        if presentation.state.mode == .repositories { return NSLocalizedString("Homebrew repository", comment: "") }
        let kind = NSLocalizedString(row.cask ? "Cask" : "Formula", comment: "")
        let parts = row.name.split(separator: "/")
        return parts.count > 1 ? "\(kind) · \(parts.dropLast().joined(separator: "/"))" : kind
    }

    var body: some View {
        BPPackageRowContent {
            HStack(spacing: compactRows ? 8 : 12) {
                Image(systemName: presentation.state.mode == .repositories ? "externaldrive" : (row.cask ? "app" : "shippingbox"))
                    .font(.system(size: compactRows ? 14 : 21, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: compactRows ? 18 : 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(row.name)
                            .font(compactRows ? .body : .body.weight(.medium))
                            .lineLimit(1)
                            .accessibilityValue(row.name)
                            .accessibilityIdentifier("package.row.\(row.name)")
                        if row.isPinned {
                            Label(NSLocalizedString("Sidebar_Item_Pinned", comment: ""), systemImage: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    if !compactRows {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityIdentifier("package.summary.\(row.name)")
                    }
                }
                .padding(.vertical, compactRows ? 0 : 6)
            }
        }
        .help(subtitle)
    }

}

@MainActor
private struct BPInstalledPackageListView: View {
    @ObservedObject var presentation: BPInstalledPackageListPresentation
    @State private var returningPackage: BPInstalledPackageRow?
    @AppStorage(BPPreferences.compactPackageRowsKey) private var compactRows = false

    private var selectionSetBinding: Binding<Set<BPFormulaInformationIdentity>> {
        Binding(
            get: { presentation.state.selectedIDs },
            set: { presentation.selectFromTable($0) }
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

    private func nameCell(_ row: BPInstalledPackageRow) -> some View {
        BPPackageNameCell(presentation: presentation, row: row)
    }

    private func versionCell(_ row: BPInstalledPackageRow, latest: Bool = false) -> some View {
        let version = latest ? row.latestVersion : row.version
        return BPPackageRowContent(alignment: .trailing) {
            Text(version)
                .font(.callout.weight(latest ? .medium : .regular))
                .monospacedDigit()
                .foregroundStyle(latest ? .primary : .secondary)
                .lineLimit(1)
                .accessibilityValue(version)
                .help(version)
        }
    }

    private func statusText(for statusRank: Int) -> String {
        switch statusRank {
        case 1: return NSLocalizedString("Formula_Status_Installed", comment: "")
        case 2: return NSLocalizedString("Update available", comment: "")
        default: return NSLocalizedString("Formula_Status_Not_Installed", comment: "")
        }
    }

    private func statusCell(_ row: BPInstalledPackageRow) -> some View {
        let text = statusText(for: row.statusRank)
        return BPPackageRowContent(alignment: .trailing) {
            HStack(spacing: 5) {
                if row.statusRank == 2 {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                Text(text)
                    .font(.caption.weight(row.statusRank == 2 ? .medium : .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel(text)
                    .accessibilityValue(text)
                    .accessibilityIdentifier("package.status.\(row.name)")
            }
            .help(text)
        }
    }

    @ViewBuilder
    private var modeTable: some View {
        let mode = presentation.state.mode
        if !mode.showsVersionColumn {
            Table(presentation.state.displayedRows, selection: selectionSetBinding, sortOrder: sortOrderBinding) {
                TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                    nameCell(row)
                }.width(min: 180, ideal: 360)
            }
        } else if mode.showsLatestVersionColumn {
            Table(presentation.state.displayedRows, selection: selectionSetBinding, sortOrder: sortOrderBinding) {
                TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                    nameCell(row)
                }.width(min: 180, ideal: 360)
                TableColumn(BPMainMenuLocalizedTitle("h5d-xc-Jih.headerCell.title", fallback: "Version"), value: \.version) { row in
                    versionCell(row)
                }.width(min: 75, ideal: 100, max: 160)
                TableColumn(BPMainMenuLocalizedTitle("d93-10-421.headerCell.title", fallback: "Latest Version"), value: \.latestVersion) { row in
                    versionCell(row, latest: true)
                }.width(min: 90, ideal: 110, max: 160)
            }
        } else if mode.showsStatusColumn && !mode.showsInstalledVersionColumn {
            Table(presentation.state.displayedRows, selection: selectionSetBinding, sortOrder: sortOrderBinding) {
                TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                    nameCell(row)
                }.width(min: 180, ideal: 360)
                TableColumn(BPMainMenuLocalizedTitle("Be6-3F-p4b.headerCell.title", fallback: "Status"), value: \.statusRank) { row in
                    statusCell(row)
                }.width(min: 100, ideal: 135, max: 160)
            }
        } else if mode.showsStatusColumn {
            Table(presentation.state.displayedRows, selection: selectionSetBinding, sortOrder: sortOrderBinding) {
                TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                    nameCell(row)
                }.width(min: 180, ideal: 360)
                TableColumn(BPMainMenuLocalizedTitle("h5d-xc-Jih.headerCell.title", fallback: "Version"), value: \.version) { row in
                    versionCell(row)
                }.width(min: 75, ideal: 100, max: 160)
                TableColumn(BPMainMenuLocalizedTitle("Be6-3F-p4b.headerCell.title", fallback: "Status"), value: \.statusRank) { row in
                    statusCell(row)
                }.width(min: 100, ideal: 135, max: 160)
            }
        } else {
            Table(presentation.state.displayedRows, selection: selectionSetBinding, sortOrder: sortOrderBinding) {
                TableColumn(BPMainMenuLocalizedTitle("A78-TI-Q8X.headerCell.title", fallback: "Name"), value: \.name) { row in
                    nameCell(row)
                }.width(min: 180, ideal: 360)
                TableColumn(BPMainMenuLocalizedTitle("h5d-xc-Jih.headerCell.title", fallback: "Version"), value: \.version) { row in
                    versionCell(row)
                }.width(min: 75, ideal: 100, max: 160)
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
                // Table caches its measured row height. A density change needs
                // a fresh layout; selection and sorting live in presentation.
                .id(compactRows)
                .tableStyle(.inset)
                .alternatingRowBackgrounds(.disabled)
                .scrollContentBackground(.hidden)
                .background(.background)
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
                .onReceive(NotificationCenter.default.publisher(for: BPFormula.didUpdateNotification).receive(on: RunLoop.main)) { notification in
                    guard let formula = notification.object as? BPFormula, let name = formula.name else { return }
                    let identity = BPFormulaInformationIdentity(name: name, cask: formula.cask, mode: .general)
                    presentation.receiveSummary(formula.shortDescription, for: identity)
                }
        }
        .sheet(item: $returningPackage) { BPPinnedReturnSheet(row: $0) }
    }
}


#if DEBUG
@MainActor
private struct BPPackageBrowserPreview: View {
    private let host: BPInstalledPackageListHost = {
        let host = BPInstalledPackageListHost()
        host.updatePackages([
            BPInstalledPackageRow(name: "ffmpeg", cask: false, version: "7.1.1", latestVersion: "7.1.1", statusRank: 1, isPinned: false, summary: "Record, convert, and stream audio and video"),
            BPInstalledPackageRow(name: "git", cask: false, version: "2.47.0", latestVersion: "2.48.1", statusRank: 2, isPinned: false, summary: "Distributed version control"),
            BPInstalledPackageRow(name: "node@22", cask: false, version: "22.11.0", latestVersion: "22.11.0", statusRank: 1, isPinned: true, summary: "JavaScript runtime built on V8"),
            BPInstalledPackageRow(name: "ripgrep", cask: false, version: "14.1.0", latestVersion: "14.1.0", statusRank: 1, isPinned: false, summary: "Search your files with speed and precision"),
            BPInstalledPackageRow(name: "visual-studio-code", cask: true, version: "1.96.2", latestVersion: "1.96.2", statusRank: 1, isPinned: false, summary: "Code editor with integrated debugging"),
            BPInstalledPackageRow(name: "wget", cask: false, version: "1.25.0", latestVersion: "1.25.0", statusRank: 1, isPinned: false, summary: "Retrieve files from the web")
        ], mode: .search)
        return host
    }()

    var body: some View {
        host.content.frame(width: 720, height: 460)
    }
}

#Preview("Package Browser · Light") {
    BPPackageBrowserPreview().preferredColorScheme(.light)
}

#Preview("Package Browser · Dark") {
    BPPackageBrowserPreview().preferredColorScheme(.dark)
}
#endif
