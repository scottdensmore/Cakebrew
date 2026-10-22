#import "BPFormulaeTableAction.h"
#import "BPCleanupPreview.h"
#import "BPUpdatesSnapshot.h"

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
    if (sidebarRow == FormulaeSideBarItemUnifiedUpdates) {
        if (selectedCount == 0) {
            return BPToolbarModeDefault;
        }
        return selectedCount > 1 ? BPToolbarModeUpdateMany : BPToolbarModeUpdateSingle;
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

+ (BOOL)shouldSyncUnifiedUpdatesForPublishedMode:(BPListMode)publishedMode
                                       isLoading:(BOOL)isLoading
                       isUsingUnifiedUpdatesHost:(BOOL)isUsingUnifiedUpdatesHost
{
    return !isLoading
        && isUsingUnifiedUpdatesHost
        && (publishedMode == kBPListOutdated
            || publishedMode == kBPListOutdatedCasks
            || publishedMode == kBPListPinned);
}
@end

@implementation BPPackageOperationPresenter

static NSString *BPOperationLocalizedFormat(NSString *key, NSString *fallback)
{
    return NSLocalizedStringWithDefaultValue(key, nil, NSBundle.mainBundle, fallback, @"");
}

+ (nullable NSAlert *)installAlertForFormula:(nullable BPFormula *)formula
{
    if (!formula || !formula.name.length) return nil;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Generic_Attention", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"Generic_Yes", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
    alert.informativeText = [NSString stringWithFormat:
                             BPOperationLocalizedFormat(@"Confirmation_Install_Formula",
                                                        @"Are you sure you want to install the formula '%@'?"),
                             formula.name];
    return alert;
}

+ (nullable NSAlert *)uninstallAlertForFormula:(nullable BPFormula *)formula
                               initialZapState:(BOOL)zapState
                                   zapCheckbox:(NSButton * _Nullable * _Nullable)outCheckbox
{
    if (!formula || !formula.name.length) return nil;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Generic_Attention", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"Generic_Yes", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
    alert.informativeText = [NSString stringWithFormat:
                             BPOperationLocalizedFormat(@"Confirmation_Uninstall_Formula",
                                                        @"Are you sure you want to uninstall the formula '%@'?"),
                             formula.name];

    NSButton *zapCheckbox = nil;
    if (formula.cask) {
        zapCheckbox = [NSButton checkboxWithTitle:NSLocalizedString(@"Confirmation_Uninstall_Cask_Zap", nil)
                                           target:nil
                                           action:nil];
        [zapCheckbox sizeToFit];
        zapCheckbox.state = zapState ? NSControlStateValueOn : NSControlStateValueOff;
        alert.accessoryView = zapCheckbox;
    }
    if (outCheckbox) {
        *outCheckbox = zapCheckbox;
    }
    return alert;
}

+ (nullable NSAlert *)upgradeAlertForFormulae:(nullable NSArray<BPFormula *> *)formulae
{
    if (!formulae.count) return nil;

    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:formulae.count];
    for (BPFormula *formula in formulae) {
        if ([formula isKindOfClass:BPFormula.class] && formula.name.length) {
            [names addObject:formula.name];
        }
    }
    if (!names.count) return nil;

    NSString *formulaNames = [names componentsJoinedByString:@", "];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Message_Update_Formulae_Title", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"Generic_Yes", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
    alert.informativeText = [NSString stringWithFormat:
                             BPOperationLocalizedFormat(@"Message_Update_Formulae_Body",
                                                        @"Are you sure you want to update these formulae: '%@'?"),
                             formulaNames];
    return alert;
}

+ (nullable NSString *)updatesReviewSummaryForSnapshot:(nullable BPUpdatesSnapshot *)snapshot
{
    if (!snapshot || !snapshot.hasEligibleUpdates) return nil;

    NSMutableArray<NSString *> *sections = [NSMutableArray array];
    if (snapshot.eligibleFormulae.count) {
        [sections addObject:[NSString stringWithFormat:
                             BPOperationLocalizedFormat(@"Updates_Formula_Targets", @"Formulae: %@"),
                             [snapshot.eligibleFormulae componentsJoinedByString:@", "]]];
    }
    if (snapshot.eligibleCasks.count) {
        [sections addObject:[NSString stringWithFormat:
                             BPOperationLocalizedFormat(@"Updates_Cask_Targets", @"Casks: %@"),
                             [snapshot.eligibleCasks componentsJoinedByString:@", "]]];
    }
    if (snapshot.excludedFormulae.count) {
        [sections addObject:[NSString stringWithFormat:
                             BPOperationLocalizedFormat(@"Updates_Pinned_Formula_Exclusions",
                                                        @"Pinned formulae will be skipped: %@"),
                             [snapshot.excludedFormulae componentsJoinedByString:@", "]]];
    }
    if (snapshot.excludedCasks.count) {
        [sections addObject:[NSString stringWithFormat:
                             BPOperationLocalizedFormat(@"Updates_Pinned_Cask_Exclusions",
                                                        @"Pinned casks will be skipped: %@"),
                             [snapshot.excludedCasks componentsJoinedByString:@", "]]];
    }
    return [sections componentsJoinedByString:@"\n\n"];
}

+ (nullable NSAlert *)upgradeAllAlertForSnapshot:(nullable BPUpdatesSnapshot *)snapshot
{
    NSString *summary = [self updatesReviewSummaryForSnapshot:snapshot];
    if (!summary) return nil;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Updates_Confirm_Title", nil);
    alert.informativeText = NSLocalizedString(@"Updates_Review_Body", nil);
    NSScrollView *review = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 440, 180)];
    review.hasVerticalScroller = YES;
    review.borderType = NSBezelBorder;
    NSTextView *targets = [[NSTextView alloc] initWithFrame:review.contentView.bounds];
    targets.editable = NO;
    targets.selectable = YES;
    targets.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    targets.textContainerInset = NSMakeSize(8, 8);
    targets.textContainer.widthTracksTextView = YES;
    targets.autoresizingMask = NSViewWidthSizable;
    targets.verticallyResizable = YES;
    targets.horizontallyResizable = NO;
    targets.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    targets.string = summary;
    targets.accessibilityIdentifier = @"updates.targets";
    targets.accessibilityLabel = NSLocalizedString(@"Updates_Review_Targets", nil);
    review.documentView = targets;
    alert.accessoryView = review;
    [alert addButtonWithTitle:NSLocalizedString(@"Updates_Confirm_Action", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
    alert.buttons.firstObject.accessibilityIdentifier = @"updates.confirm";
    return alert;
}

+ (NSAlert *)updatesChangedAlert
{
    NSAlert *changed = [[NSAlert alloc] init];
    changed.messageText = NSLocalizedString(@"Updates_Changed_Title", nil);
    changed.informativeText = NSLocalizedString(@"Updates_Changed_Body", nil);
    [changed addButtonWithTitle:NSLocalizedString(@"Generic_OK", nil)];
    return changed;
}

+ (NSAlert *)tapInputAlertWithInputField:(NSTextField * _Nullable * _Nullable)outField
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Message_Tap_Title", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"Generic_OK", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
    alert.informativeText = NSLocalizedString(@"Message_Tap_Body", nil);

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    alert.accessoryView = input;
    if (outField) {
        *outField = input;
    }
    return alert;
}

+ (NSAlert *)invalidTapAlert
{
    NSAlert *error = [[NSAlert alloc] init];
    error.messageText = NSLocalizedString(@"Message_Tap_Invalid_Title", nil);
    error.informativeText = NSLocalizedString(@"Message_Tap_Invalid_Body", nil);
    [error addButtonWithTitle:NSLocalizedString(@"Generic_OK", nil)];
    return error;
}

+ (nullable NSAlert *)untapAlertForFormula:(nullable BPFormula *)formula
{
    if (!formula || !formula.name.length) return nil;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Message_Untap_Title", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"Generic_OK", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
    alert.informativeText = [NSString stringWithFormat:
                             BPOperationLocalizedFormat(@"Message_Untap_Body",
                                                        @"Are you sure you want to untap the repository '%@'?"),
                             formula.name];
    return alert;
}

+ (NSString *)cleanupConfirmationBodyForPreview:(BPCleanupPreview *)preview
{
    NSString *items = preview.itemCount == 1 ?
        BPOperationLocalizedFormat(@"Cleanup_Item_Count_One", @"1 item") :
        [NSString localizedStringWithFormat:
         BPOperationLocalizedFormat(@"Cleanup_Item_Count_Other", @"%lu items"),
         (unsigned long)preview.itemCount];

    if (preview.reclaimableBytes == 0) {
        return [NSString localizedStringWithFormat:
                BPOperationLocalizedFormat(@"Confirmation_Cleanup_No_Size",
                                           @"Would remove %@ from Homebrew's cache and old installed versions.\n\nAre you sure you want to proceed?"),
                items];
    }

    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleBinary;

    NSString *size = [formatter stringFromByteCount:(long long)preview.reclaimableBytes];

    return [NSString localizedStringWithFormat:
            BPOperationLocalizedFormat(@"Confirmation_Cleanup",
                                       @"Would remove %@ (%@) from Homebrew's cache and old installed versions.\n\nAre you sure you want to proceed?"),
            items, size];
}

+ (NSAlert *)cleanupAlertForPreview:(BPCleanupPreview *)preview
{
    NSAlert *alert = [[NSAlert alloc] init];
    if (preview.isEmpty) {
        alert.messageText = NSLocalizedString(@"Cleanup_Nothing_Title", nil);
        alert.informativeText = NSLocalizedString(@"Cleanup_Nothing_Body", nil);
        [alert addButtonWithTitle:NSLocalizedString(@"Generic_OK", nil)];
        return alert;
    }

    alert.messageText = NSLocalizedString(@"Generic_Attention", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"Generic_Yes", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
    alert.informativeText = [self cleanupConfirmationBodyForPreview:preview];
    return alert;
}

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)brewfileInventoriesForInstalledFormulae:(nullable NSArray<BPFormula *> *)formulae
                                                                              installedCasks:(nullable NSArray<BPFormula *> *)casks
                                                                                repositories:(nullable NSArray<BPFormula *> *)repositories
{
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *inventories = [NSMutableDictionary dictionary];
    if (formulae) inventories[@"brew"] = [formulae valueForKey:@"name"];
    if (casks) inventories[@"cask"] = [casks valueForKey:@"name"];
    if (repositories) inventories[@"tap"] = [repositories valueForKey:@"name"];
    return [inventories copy];
}

+ (NSArray<BPFormula *> *)resolvedSelectionForFormulaNames:(NSArray<NSString *> *)formulaNames
                                                 caskNames:(NSArray<NSString *> *)caskNames
                                          outdatedFormulae:(nullable NSArray<BPFormula *> *)outdatedFormulae
                                             outdatedCasks:(nullable NSArray<BPFormula *> *)outdatedCasks
{
    NSMutableArray<BPFormula *> *result = [NSMutableArray arrayWithCapacity:formulaNames.count + caskNames.count];

    NSMutableDictionary<NSString *, BPFormula *> *formulaByName = [NSMutableDictionary dictionary];
    for (BPFormula *formula in outdatedFormulae) {
        if ([formula isKindOfClass:BPFormula.class] && formula.name.length) {
            formulaByName[formula.name] = formula;
        }
    }
    for (NSString *name in formulaNames) {
        if (![name isKindOfClass:NSString.class] || !name.length) continue;
        BPFormula *matched = formulaByName[name];
        if (matched) {
            [result addObject:matched];
        } else {
            BPFormula *fallback = [BPFormula formulaWithName:name];
            fallback.cask = NO;
            [result addObject:fallback];
        }
    }

    NSMutableDictionary<NSString *, BPFormula *> *caskByName = [NSMutableDictionary dictionary];
    for (BPFormula *cask in outdatedCasks) {
        if ([cask isKindOfClass:BPFormula.class] && cask.name.length) {
            caskByName[cask.name] = cask;
        }
    }
    for (NSString *name in caskNames) {
        if (![name isKindOfClass:NSString.class] || !name.length) continue;
        BPFormula *matched = caskByName[name];
        if (matched) {
            [result addObject:matched];
        } else {
            BPFormula *fallback = [BPFormula formulaWithName:name];
            fallback.cask = YES;
            [result addObject:fallback];
        }
    }

    return [result copy];
}

@end
