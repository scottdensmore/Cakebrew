import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

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
