import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

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

