import CryptoKit
import Darwin
import Foundation

@objc(FormulaeSideBarItem)
public enum FormulaeSideBarItem: UInt {
    @objc(FormulaeSideBarItemFormulaeCategory) case formulaeCategory = 0
    @objc(FormulaeSideBarItemInstalled) case installed = 1
    @objc(FormulaeSideBarItemOutdated) case outdated = 2
    @objc(FormulaeSideBarItemAll) case all = 3
    @objc(FormulaeSideBarItemLeaves) case leaves = 4
    @objc(FormulaeSideBarItemPinned) case pinned = 5
    @objc(FormulaeSideBarItemRepositories) case repositories = 6
    @objc(FormulaeSideBarItemCasksCategory) case casksCategory = 7
    @objc(FormulaeSideBarItemInstalledCasks) case installedCasks = 8
    @objc(FormulaeSideBarItemOutdatedCasks) case outdatedCasks = 9
    @objc(FormulaeSideBarItemAllCasks) case allCasks = 10
    @objc(FormulaeSideBarItemToolsCategory) case toolsCategory = 11
    @objc(FormulaeSideBarItemDoctor) case doctor = 12
    @objc(FormulaeSideBarItemUpdate) case update = 13
    @objc(FormulaeSideBarItemServices) case services = 14
    @objc(FormulaeSideBarItemUnifiedUpdates) case unifiedUpdates = 15
}

@objc(BPFormulaInfoType)
public enum BPFormulaInfoType: Int {
    @objc(kBPFormulaInfoTypeGeneral) case general = 0
    @objc(kBPFormulaInfoTypeInstalledDependents) case installedDependents = 1
    @objc(kBPFormulaInfoTypeAllDependents) case allDependents = 2
}

@objc(BPFormulaeTableAction)
public enum BPFormulaeTableAction: Int {
    @objc(BPFormulaeTableActionNone) case none = 0
    @objc(BPFormulaeTableActionInstall) case install = 1
    @objc(BPFormulaeTableActionUpgrade) case upgrade = 2
    @objc(BPFormulaeTableActionInfo) case info = 3
    @objc(BPFormulaeTableActionUninstall) case uninstall = 4
}

@objc(BPFormulaeTableActions)
public final class BPFormulaeTableActions: NSObject {
    // BPListMode raw constants
    private static let modeAll = 0
    private static let modeInstalled = 1
    private static let modeLeaves = 2
    private static let modeOutdated = 3
    private static let modeSearch = 4
    private static let modeRepositories = 5
    private static let modePinned = 6
    private static let modeInstalledCasks = 7
    private static let modeOutdatedCasks = 8
    private static let modeAllCasks = 9

    // BPFormulaStatus raw constants
    private static let statusNotInstalled = 0
    private static let statusInstalled = 1
    private static let statusOutdated = 2

    // BPFormulaeTableRequest raw constants
    private static let requestPrimary = 0
    private static let requestUninstall = 1

    @objc(actionForRequest:mode:formulae:statuses:)
    public static func action(
        forRequest request: Int,
        mode: Int,
        formulae: [Any]?,
        statuses: [Any]?
    ) -> BPFormulaeTableAction {
        guard let formulae, let statuses,
              !formulae.isEmpty,
              formulae.count == statuses.count,
              mode >= modeAll,
              mode <= modeAllCasks,
              mode != modeRepositories else {
            return .none
        }

        let outdatedList = (mode == modeOutdated || mode == modeOutdatedCasks)
        let installedList = (mode == modeInstalled || mode == modeInstalledCasks || mode == modeLeaves || mode == modePinned)
        let caskList = (mode == modeAllCasks || mode == modeInstalledCasks || mode == modeOutdatedCasks)

        var parsedStatuses: [Int] = []
        parsedStatuses.reserveCapacity(formulae.count)

        for index in 0..<formulae.count {
            guard let formula = bpAsFormula(formulae[index]),
                  let name = formula.name, !name.isEmpty,
                  let number = statuses[index] as? NSNumber else {
                return .none
            }
            let status = number.intValue
            if status < statusNotInstalled || status > statusOutdated
                || (mode != modeSearch && formula.cask != caskList)
                || (outdatedList && status != statusOutdated)
                || (installedList && status == statusNotInstalled) {
                return .none
            }
            parsedStatuses.append(status)
        }

        if request == requestUninstall {
            return (formulae.count == 1 && parsedStatuses[0] != statusNotInstalled) ? .uninstall : .none
        }
        if request != requestPrimary {
            return .none
        }
        if outdatedList {
            return .upgrade
        }
        if formulae.count != 1 {
            return .none
        }
        if mode == modeInstalled || mode == modeInstalledCasks {
            return .info
        }
        if (mode == modeAll || mode == modeAllCasks) && parsedStatuses[0] == statusNotInstalled {
            return .install
        }
        return .none
    }

    @objc(toolbarModeForSidebarRow:selectedCount:selectedFormulaStatus:)
    public static func toolbarMode(
        forSidebarRow sidebarRow: Int,
        selectedCount: UInt,
        selectedFormulaStatus status: Int
    ) -> BPToolbarMode {
        if sidebarRow == Int(FormulaeSideBarItem.repositories.rawValue) {
            return selectedCount > 0 ? .untap : .tap
        }
        if sidebarRow == Int(FormulaeSideBarItem.unifiedUpdates.rawValue) {
            if selectedCount == 0 {
                return .default
            }
            return selectedCount > 1 ? .updateMany : .updateSingle
        }
        if sidebarRow == Int(FormulaeSideBarItem.installedCasks.rawValue)
            || sidebarRow == Int(FormulaeSideBarItem.outdatedCasks.rawValue)
            || sidebarRow == Int(FormulaeSideBarItem.allCasks.rawValue) {
            if selectedCount == 0 {
                return .default
            }
            if sidebarRow == Int(FormulaeSideBarItem.outdatedCasks.rawValue) {
                return selectedCount > 1 ? .updateMany : .updateSingle
            }
            if sidebarRow == Int(FormulaeSideBarItem.allCasks.rawValue) {
                return status == statusNotInstalled ? .install : .uninstall
            }
            return .uninstall
        }
        if selectedCount == 0 || sidebarRow < 0 || sidebarRow > Int(FormulaeSideBarItem.toolsCategory.rawValue) {
            return .default
        }
        if selectedCount > 1 {
            return .updateMany
        }
        switch status {
        case statusInstalled:
            return .uninstall
        case statusOutdated:
            return sidebarRow == Int(FormulaeSideBarItem.outdated.rawValue) ? .updateSingle : .uninstall
        case statusNotInstalled:
            return .install
        default:
            return .default
        }
    }

    @objc(shouldShowFormulaInfoForSidebarRow:)
    public static func shouldShowFormulaInfo(forSidebarRow sidebarRow: Int) -> Bool {
        sidebarRow != Int(FormulaeSideBarItem.repositories.rawValue)
    }

    @objc(footerLocalizationKeyForSidebarRow:searching:)
    public static func footerLocalizationKey(forSidebarRow sidebarRow: Int, searching: Bool) -> String? {
        if searching {
            return "Sidebar_Info_SearchResults"
        }
        return sidebarInfoKey(forRow: sidebarRow)
    }

    @objc(sidebarInfoKeyForRow:)
    public static func sidebarInfoKey(forRow row: Int) -> String? {
        guard row >= 0, let item = FormulaeSideBarItem(rawValue: UInt(row)) else { return nil }
        switch item {
        case .installed:      return "Sidebar_Info_Installed"
        case .outdated:       return "Sidebar_Info_Outdated"
        case .all:            return "Sidebar_Info_All"
        case .leaves:         return "Sidebar_Info_Leaves"
        case .pinned:         return "Sidebar_Info_Pinned"
        case .repositories:   return "Sidebar_Info_Repos"
        case .installedCasks: return "Sidebar_Info_Casks"
        case .outdatedCasks:  return "Sidebar_Info_OutdatedCasks"
        case .allCasks:       return "Sidebar_Info_AllCasks"
        case .doctor:         return "Sidebar_Info_Doctor"
        case .update:         return "Sidebar_Info_Update"
        case .services:       return "Sidebar_Info_Services"
        case .unifiedUpdates: return "Sidebar_Info_Unified_Updates"
        case .formulaeCategory, .casksCategory, .toolsCategory:
            return nil
        }
    }

    @objc(shouldRefreshVisibleListForPublishedMode:activeMode:isLoading:)
    public static func shouldRefreshVisibleList(
        forPublishedMode publishedMode: Int,
        activeMode: Int,
        isLoading: Bool
    ) -> Bool {
        !isLoading && activeMode == publishedMode
    }

    @objc(shouldSyncInstalledHostMetadataForPublishedMode:activeMode:isLoading:isUsingInstalledHost:)
    public static func shouldSyncInstalledHostMetadata(
        forPublishedMode publishedMode: Int,
        activeMode: Int,
        isLoading: Bool,
        isUsingInstalledHost: Bool
    ) -> Bool {
        !isLoading
            && isUsingInstalledHost
            && activeMode != publishedMode
            && (publishedMode == modePinned
                || publishedMode == modeOutdated
                || publishedMode == modeOutdatedCasks)
    }

    @objc(shouldSyncUnifiedUpdatesForPublishedMode:isLoading:isUsingUnifiedUpdatesHost:)
    public static func shouldSyncUnifiedUpdates(
        forPublishedMode publishedMode: Int,
        isLoading: Bool,
        isUsingUnifiedUpdatesHost: Bool
    ) -> Bool {
        !isLoading
            && isUsingUnifiedUpdatesHost
            && (publishedMode == modeOutdated
                || publishedMode == modeOutdatedCasks
                || publishedMode == modePinned)
    }
}
