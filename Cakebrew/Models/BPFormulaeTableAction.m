#import "BPFormulaeTableAction.h"

@implementation BPFormulaeTableActions
+ (BPFormulaeTableAction)actionForRequest:(BPFormulaeTableRequest)request
                                   mode:(BPListMode)mode
                               formulae:(NSArray<BPFormula *> *)formulae
                               statuses:(NSArray<NSNumber *> *)statuses
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
@end
