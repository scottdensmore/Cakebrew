#import "BPFormulaeTableAction.h"

@implementation BPFormulaeTableActions
+ (BPFormulaeTableAction)actionForRequest:(BPFormulaeTableRequest)request
                                   mode:(BPListMode)mode
                               formulae:(nullable NSArray<BPFormula *> *)formulae
                               statuses:(nullable NSArray<NSNumber *> *)statuses
{
    if (!formulae.count || formulae.count != statuses.count || mode < kBPListAll
        || mode > kBPListAllCasks || mode == kBPListRepositories) return BPFormulaeTableActionNone;
    BOOL outdatedList = mode == kBPListOutdated || mode == kBPListOutdatedCasks;
    BOOL installedList = mode == kBPListInstalled || mode == kBPListInstalledCasks
        || mode == kBPListLeaves || mode == kBPListPinned;
    BOOL caskList = mode == kBPListAllCasks || mode == kBPListInstalledCasks || mode == kBPListOutdatedCasks;
    for (NSUInteger index = 0; index < formulae.count; index++) {
        BPFormula *formula = formulae[index];
        NSNumber *number = statuses[index];
        if (![formula isKindOfClass:BPFormula.class] || !formula.name.length
            || ![number isKindOfClass:NSNumber.class]) return BPFormulaeTableActionNone;
        NSInteger status = number.integerValue;
        if (status < kBPFormulaNotInstalled || status > kBPFormulaOutdated
            || (mode != kBPListSearch && formula.cask != caskList)
            || (outdatedList && status != kBPFormulaOutdated)
            || (installedList && status == kBPFormulaNotInstalled)) return BPFormulaeTableActionNone;
    }
    if (request == BPFormulaeTableRequestUninstall) {
        return formulae.count == 1 && statuses.firstObject.integerValue != kBPFormulaNotInstalled
            ? BPFormulaeTableActionUninstall : BPFormulaeTableActionNone;
    }
    if (request != BPFormulaeTableRequestPrimary) return BPFormulaeTableActionNone;
    if (outdatedList) return BPFormulaeTableActionUpgrade;
    if (formulae.count != 1) return BPFormulaeTableActionNone;
    if (mode == kBPListInstalled || mode == kBPListInstalledCasks) return BPFormulaeTableActionInfo;
    if ((mode == kBPListAll || mode == kBPListAllCasks)
        && statuses.firstObject.integerValue == kBPFormulaNotInstalled) return BPFormulaeTableActionInstall;
    return BPFormulaeTableActionNone;
}

+ (BPToolbarMode)toolbarModeForSidebarRow:(NSInteger)sidebarRow
                            selectedCount:(NSUInteger)selectedCount
                    selectedFormulaStatus:(BPFormulaStatus)status
{
    if (sidebarRow == FormulaeSideBarItemRepositories) {
        return selectedCount > 0 ? BPToolbarModeUntap : BPToolbarModeTap;
    }
    if (sidebarRow == FormulaeSideBarItemInstalledCasks
        || sidebarRow == FormulaeSideBarItemOutdatedCasks
        || sidebarRow == FormulaeSideBarItemAllCasks) {
        if (selectedCount == 0) {
            return BPToolbarModeDefault;
        }
        if (sidebarRow == FormulaeSideBarItemOutdatedCasks) {
            return selectedCount > 1 ? BPToolbarModeUpdateMany : BPToolbarModeUpdateSingle;
        }
        if (sidebarRow == FormulaeSideBarItemAllCasks) {
            return status == kBPFormulaNotInstalled ? BPToolbarModeInstall : BPToolbarModeUninstall;
        }
        return BPToolbarModeUninstall;
    }
    if (selectedCount == 0 || sidebarRow < 0 || sidebarRow > (NSInteger)FormulaeSideBarItemToolsCategory) {
        return BPToolbarModeDefault;
    }
    if (selectedCount > 1) {
        return BPToolbarModeUpdateMany;
    }
    switch (status) {
        case kBPFormulaInstalled:
            return BPToolbarModeUninstall;
        case kBPFormulaOutdated:
            return sidebarRow == FormulaeSideBarItemOutdated ? BPToolbarModeUpdateSingle : BPToolbarModeUninstall;
        case kBPFormulaNotInstalled:
            return BPToolbarModeInstall;
    }
    return BPToolbarModeDefault;
}

+ (BOOL)shouldShowFormulaInfoForSidebarRow:(NSInteger)sidebarRow
{
    return sidebarRow != FormulaeSideBarItemRepositories;
}

+ (nullable NSString *)footerLocalizationKeyForSidebarRow:(NSInteger)sidebarRow
                                                searching:(BOOL)searching
{
    if (searching) {
        return @"Sidebar_Info_SearchResults";
    }
    return [BPSideBarController infoKeyForRow:sidebarRow];
}

+ (BOOL)shouldRefreshVisibleListForPublishedMode:(BPListMode)publishedMode
                                      activeMode:(BPListMode)activeMode
                                       isLoading:(BOOL)isLoading
{
    return !isLoading && activeMode == publishedMode;
}

+ (BOOL)shouldSyncInstalledHostMetadataForPublishedMode:(BPListMode)publishedMode
                                             activeMode:(BPListMode)activeMode
                                              isLoading:(BOOL)isLoading
                                   isUsingInstalledHost:(BOOL)isUsingInstalledHost
{
    return !isLoading
        && isUsingInstalledHost
        && activeMode != publishedMode
        && (publishedMode == kBPListPinned
            || publishedMode == kBPListOutdated
            || publishedMode == kBPListOutdatedCasks);
}
@end
