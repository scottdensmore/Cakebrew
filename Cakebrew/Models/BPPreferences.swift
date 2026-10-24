import CryptoKit
import Darwin
import Foundation

@objc(BPPreferences)
public final class BPPreferences: NSObject {
    public static let backgroundCheckEnabledKey = "BPBackgroundCheckEnabled"
    public static let backgroundCheckIntervalKey = "BPBackgroundCheckInterval"
    public static let greedyCaskUpgradesKey = "BPGreedyCaskUpgrades"
    public static let lastSelectedSidebarRowKey = "BPLastSelectedSidebarRow"
    public static let sortColumnIdentifierKey = "BPSortColumnIdentifier"
    public static let sortAscendingKey = "BPSortAscending"
    public static let zapCasksOnUninstallKey = "BPZapCasksOnUninstall"
    public static let automaticAppUpdateCheckEnabledKey = "BPAutomaticAppUpdateCheckEnabled"
    public static let showMenuBarExtraKey = "BPShowMenuBarExtra"

    @objc public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            backgroundCheckEnabledKey: true,
            backgroundCheckIntervalKey: 21600.0,
            greedyCaskUpgradesKey: false,
            lastSelectedSidebarRowKey: 1,
            sortAscendingKey: true,
            zapCasksOnUninstallKey: false,
            automaticAppUpdateCheckEnabledKey: true,
            showMenuBarExtraKey: false
        ])
    }

    @objc public static var backgroundCheckEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: backgroundCheckEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: backgroundCheckEnabledKey) }
    }

    @objc public static var backgroundCheckInterval: TimeInterval {
        get { UserDefaults.standard.double(forKey: backgroundCheckIntervalKey) }
        set { UserDefaults.standard.set(newValue, forKey: backgroundCheckIntervalKey) }
    }

    @objc public static var lastSelectedSidebarRow: Int {
        get { UserDefaults.standard.integer(forKey: lastSelectedSidebarRowKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastSelectedSidebarRowKey) }
    }

    @objc public static var sortColumnIdentifier: String? {
        get { UserDefaults.standard.string(forKey: sortColumnIdentifierKey) }
        set {
            guard let newValue, !newValue.isEmpty else {
                UserDefaults.standard.removeObject(forKey: sortColumnIdentifierKey)
                return
            }
            UserDefaults.standard.set(newValue, forKey: sortColumnIdentifierKey)
        }
    }

    @objc public static var sortAscending: Bool {
        get { UserDefaults.standard.bool(forKey: sortAscendingKey) }
        set { UserDefaults.standard.set(newValue, forKey: sortAscendingKey) }
    }

    @objc public static var zapCasksOnUninstall: Bool {
        get { UserDefaults.standard.bool(forKey: zapCasksOnUninstallKey) }
        set { UserDefaults.standard.set(newValue, forKey: zapCasksOnUninstallKey) }
    }

    @objc public static var greedyCaskUpgrades: Bool {
        get { UserDefaults.standard.bool(forKey: greedyCaskUpgradesKey) }
        set { UserDefaults.standard.set(newValue, forKey: greedyCaskUpgradesKey) }
    }

    @objc public static var automaticAppUpdateCheckEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: automaticAppUpdateCheckEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: automaticAppUpdateCheckEnabledKey) }
    }

    @objc public static var showMenuBarExtra: Bool {
        get { UserDefaults.standard.bool(forKey: showMenuBarExtraKey) }
        set { UserDefaults.standard.set(newValue, forKey: showMenuBarExtraKey) }
    }
}
