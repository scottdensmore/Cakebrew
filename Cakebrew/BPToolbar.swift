import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

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

