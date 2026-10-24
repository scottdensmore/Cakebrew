import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

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

