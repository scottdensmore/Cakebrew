#import <XCTest/XCTest.h>
#import "BPFormulaeTableView.h"
#import "BPFormulaeTableAction.h"
#import "BPCleanupPreview.h"
#import "BPUpdatesSnapshot.h"
#import "BPFormulaInformation-Swift.h"

@interface BPFormulaeTableView (ActionTesting)
- (void)performDoubleClickAction:(id)sender;
@end

@interface BPTableActionRecorder : NSObject <BPFormulaeTableActionDelegate>
@property NSInteger count;
@property BPFormulaeTableRequest request;
@end
@implementation BPTableActionRecorder
- (void)formulaeTableView:(BPFormulaeTableView *)table requestAction:(BPFormulaeTableRequest)request
{ self.count++; self.request = request; }
@end

@interface BPTableActionWindowStub : NSObject
@property (weak) NSResponder *firstResponder;
@end
@implementation BPTableActionWindowStub
@end

@interface BPActionTestTable : BPFormulaeTableView
@property (strong) BPTableActionWindowStub *testWindow;
@property NSInteger testSelectedRow;
@property NSInteger spaceCount;
@property NSInteger testClickedRow;
@end
@implementation BPActionTestTable
- (NSWindow *)window { return (NSWindow *)self.testWindow; }
- (NSInteger)selectedRow { return self.testSelectedRow; }
- (NSInteger)clickedRow { return self.testClickedRow; }
- (NSInteger)numberOfRows { return 2; }
- (NSIndexSet *)selectedRowIndexes { return self.testSelectedRow < 0 ? [NSIndexSet indexSet] : [NSIndexSet indexSetWithIndex:(NSUInteger)self.testSelectedRow]; }
- (void)spaceBarPressed { self.spaceCount++; }
@end

@interface BPFormulaeTableActionTests : XCTestCase
@property (strong) BPActionTestTable *table;
@property (strong) BPTableActionRecorder *recorder;
@end
@implementation BPFormulaeTableActionTests
- (void)testNativeDoubleActionOnlyRequestsPrimaryForASelectedExistingRow
{
    XCTAssertNotEqual(self.table.doubleAction, NULL, @"Native table doubleAction must be wired");
    if (!self.table.doubleAction) return;
    XCTAssertEqual(self.table.target, self.table);
    XCTAssertEqual(self.table.doubleAction, @selector(performDoubleClickAction:));
    [self.table performDoubleClickAction:self.table];
    XCTAssertEqual(self.recorder.count, 1);
    XCTAssertEqual(self.recorder.request, BPFormulaeTableRequestPrimary);
    for (NSNumber *row in @[@-1, @1, @2, @99]) {
        self.table.testClickedRow = row.integerValue;
        [self.table performDoubleClickAction:self.table];
        XCTAssertEqual(self.recorder.count, 1, @"Empty space, header, stale and unselected rows cannot act");
        XCTAssertEqual(self.table.testSelectedRow, 0, @"Guarding the action must not change selection");
    }
}
- (void)setUp
{
    [super setUp];
    self.table = [[BPActionTestTable alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
    [self.table awakeFromNib];
    self.table.testWindow = [BPTableActionWindowStub new];
    self.table.testWindow.firstResponder = self.table;
    self.table.testSelectedRow = 0;
    self.recorder = [BPTableActionRecorder new];
    self.table.actionDelegate = self.recorder;
}
- (void)tearDown
{
    self.table.testWindow = nil;
    self.table = nil;
    self.recorder = nil;
    [super tearDown];
}
- (NSEvent *)key:(unichar)key flags:(NSEventModifierFlags)flags repeat:(BOOL)repeat type:(NSEventType)type
{
    NSString *characters = [NSString stringWithCharacters:&key length:1];
    return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0 context:nil characters:characters charactersIgnoringModifiers:characters isARepeat:repeat keyCode:0];
}
- (void)testPlainReturnKeypadEnterAndBothDeletesDispatchTypedRequests
{
    for (NSNumber *key in @[@0x0d, @0x03, @0x7f, @0xf728]) {
        self.recorder.count = 0;
        XCTAssertTrue([self.table performKeyEquivalent:[self key:key.unsignedShortValue flags:0 repeat:NO type:NSEventTypeKeyDown]]);
        XCTAssertEqual(self.recorder.count, 1);
        XCTAssertEqual(self.recorder.request, key.unsignedShortValue < 0x7f ? BPFormulaeTableRequestPrimary : BPFormulaeTableRequestUninstall);
    }
}
- (void)testShortcutModifiersAndRepeatsNeverDispatchNewActions
{
    for (NSNumber *key in @[@0x0d, @0x03, @0x7f, @0xf728]) {
        for (NSNumber *flag in @[@(NSEventModifierFlagCommand), @(NSEventModifierFlagOption), @(NSEventModifierFlagControl), @(NSEventModifierFlagShift)]) {
            XCTAssertFalse([self.table performKeyEquivalent:[self key:key.unsignedShortValue flags:flag.unsignedIntegerValue repeat:NO type:NSEventTypeKeyDown]]);
        }
        XCTAssertFalse([self.table performKeyEquivalent:[self key:key.unsignedShortValue flags:0 repeat:YES type:NSEventTypeKeyDown]]);
    }
    XCTAssertEqual(self.recorder.count, 0);
}
- (void)testCapsLockFunctionAndNumericPadDoNotBlockRowActions
{
    for (NSNumber *flag in @[@(NSEventModifierFlagCapsLock), @(NSEventModifierFlagFunction), @(NSEventModifierFlagNumericPad)]) {
        XCTAssertTrue([self.table performKeyEquivalent:[self key:0x03 flags:flag.unsignedIntegerValue repeat:NO type:NSEventTypeKeyDown]]);
    }
    XCTAssertEqual(self.recorder.count, 3);
}
- (void)testKeyUpOtherKeysNoSelectionAndOtherFocusDoNotDispatch
{
    XCTAssertFalse([self.table performKeyEquivalent:[self key:0x0d flags:0 repeat:NO type:NSEventTypeKeyUp]]);
    XCTAssertFalse([self.table performKeyEquivalent:[self key:'a' flags:0 repeat:NO type:NSEventTypeKeyDown]]);
    self.table.testSelectedRow = -1;
    XCTAssertFalse([self.table performKeyEquivalent:[self key:0x0d flags:0 repeat:NO type:NSEventTypeKeyDown]]);
    self.table.testSelectedRow = 0;
    self.table.testWindow = nil;
    XCTAssertFalse([self.table performKeyEquivalent:[self key:0x0d flags:0 repeat:NO type:NSEventTypeKeyDown]]);
    XCTAssertEqual(self.recorder.count, 0);
}
- (void)testSpacePreservesExistingModifiedAndRepeatingBehavior
{
    XCTAssertTrue([self.table performKeyEquivalent:[self key:' ' flags:NSEventModifierFlagCommand repeat:YES type:NSEventTypeKeyDown]]);
    XCTAssertEqual(self.table.spaceCount, 1);
    XCTAssertEqual(self.recorder.count, 0);
}
- (BPFormula *)formula:(BOOL)cask
{
    BPFormula *formula = [BPFormula formulaWithName:@"fixture"];
    formula.cask = cask;
    return formula;
}
- (void)testSingleSelectionMappingForEveryListNamespaceAndStatus
{
    for (NSInteger mode = kBPListAll; mode <= kBPListAllCasks; mode++) {
        for (NSNumber *cask in @[@NO, @YES]) {
            for (NSInteger status = kBPFormulaNotInstalled; status <= kBPFormulaOutdated; status++) {
                BOOL namespaceMatches = mode == kBPListSearch ||
                    (cask.boolValue == (mode == kBPListAllCasks || mode == kBPListInstalledCasks || mode == kBPListOutdatedCasks));
                BOOL valid = namespaceMatches && mode != kBPListRepositories;
                BPFormulaeTableAction primary = BPFormulaeTableActionNone;
                if (valid && (mode == kBPListAll || mode == kBPListAllCasks) && status == kBPFormulaNotInstalled) primary = BPFormulaeTableActionInstall;
                if (valid && (mode == kBPListInstalled || mode == kBPListInstalledCasks) && status != kBPFormulaNotInstalled) primary = BPFormulaeTableActionInfo;
                if (valid && (mode == kBPListOutdated || mode == kBPListOutdatedCasks) && status == kBPFormulaOutdated) primary = BPFormulaeTableActionUpgrade;
                // An installed/outdated list with a contradictory status is stale.
                BOOL stale = ((mode == kBPListInstalled || mode == kBPListInstalledCasks || mode == kBPListLeaves || mode == kBPListPinned) && status == kBPFormulaNotInstalled)
                    || ((mode == kBPListOutdated || mode == kBPListOutdatedCasks) && status != kBPFormulaOutdated);
                BPFormulaeTableAction deletion = valid && !stale && status != kBPFormulaNotInstalled ? BPFormulaeTableActionUninstall : BPFormulaeTableActionNone;
                NSArray *formulae = @[[self formula:cask.boolValue]];
                XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestPrimary mode:mode formulae:formulae statuses:@[@(status)]]), primary, @"mode=%ld cask=%@ status=%ld", (long)mode, cask, (long)status);
                XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestUninstall mode:mode formulae:formulae statuses:@[@(status)]]), deletion, @"mode=%ld cask=%@ status=%ld", (long)mode, cask, (long)status);
            }
        }
    }
}
- (void)testOnlyHomogeneousOutdatedMultiSelectionCanUpgrade
{
    for (NSInteger mode = kBPListAll; mode <= kBPListAllCasks; mode++) {
        BOOL casks = mode == kBPListOutdatedCasks;
        NSArray *formulae = @[[self formula:casks], [self formula:casks]];
        BPFormulaeTableAction expected = mode == kBPListOutdated || mode == kBPListOutdatedCasks ? BPFormulaeTableActionUpgrade : BPFormulaeTableActionNone;
        XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestPrimary mode:mode formulae:formulae statuses:@[@2, @2]]), expected);
        XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestUninstall mode:mode formulae:formulae statuses:@[@2, @2]]), BPFormulaeTableActionNone);
    }
    XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestPrimary mode:kBPListOutdated formulae:@[[self formula:NO], [self formula:YES]] statuses:@[@2, @2]]), BPFormulaeTableActionNone);
    XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestPrimary mode:kBPListOutdated formulae:@[[self formula:NO], [self formula:NO]] statuses:@[@2, @1]]), BPFormulaeTableActionNone);
}
- (void)testMissingMalformedUnknownAndStaleSelectionsFailClosed
{
    NSArray *invalidFormulae = @[@[], @[@"not a model"], @[[BPFormula formulaWithName:@""]]];
    for (NSArray *formulae in invalidFormulae) {
        XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestPrimary mode:kBPListAll formulae:formulae statuses:@[@0]]), BPFormulaeTableActionNone);
    }
    NSArray *one = @[[self formula:NO]];
    for (NSArray *statuses in @[@[], @[@99], @[@-1], @[@"bad"], @[@0, @0]]) {
        XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestPrimary mode:kBPListAll formulae:one statuses:statuses]), BPFormulaeTableActionNone);
    }
    XCTAssertEqual(([BPFormulaeTableActions actionForRequest:99 mode:kBPListAll formulae:one statuses:@[@0]]), BPFormulaeTableActionNone);
    XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestPrimary mode:99 formulae:one statuses:@[@0]]), BPFormulaeTableActionNone);
}
- (void)testReturnIsHandledByTheFocusedSelectedTable
{
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
    XCTAssertTrue([self.table performKeyEquivalent:event], @"Return should be handled locally by the focused selected formula table");
}
- (void)testToolbarModeForRepositoriesSidebarRow
{
    for (NSInteger status = kBPFormulaNotInstalled; status <= kBPFormulaOutdated; status++) {
        XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:FormulaeSideBarItemRepositories
                                                          selectedCount:0
                                                  selectedFormulaStatus:(BPFormulaStatus)status],
                       BPToolbarModeTap);
        XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:FormulaeSideBarItemRepositories
                                                          selectedCount:1
                                                  selectedFormulaStatus:(BPFormulaStatus)status],
                       BPToolbarModeUntap);
        XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:FormulaeSideBarItemRepositories
                                                          selectedCount:3
                                                  selectedFormulaStatus:(BPFormulaStatus)status],
                       BPToolbarModeUntap);
    }
}
- (void)testToolbarModeForCaskSidebarRows
{
    NSArray<NSNumber *> *caskRows = @[
        @(FormulaeSideBarItemInstalledCasks),
        @(FormulaeSideBarItemOutdatedCasks),
        @(FormulaeSideBarItemAllCasks)
    ];
    for (NSNumber *row in caskRows) {
        for (NSInteger status = kBPFormulaNotInstalled; status <= kBPFormulaOutdated; status++) {
            XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:row.integerValue
                                                              selectedCount:0
                                                      selectedFormulaStatus:(BPFormulaStatus)status],
                           BPToolbarModeDefault);
        }
    }
    for (NSInteger status = kBPFormulaNotInstalled; status <= kBPFormulaOutdated; status++) {
        XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:FormulaeSideBarItemInstalledCasks
                                                          selectedCount:1
                                                  selectedFormulaStatus:(BPFormulaStatus)status],
                       BPToolbarModeUninstall);
        XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:FormulaeSideBarItemInstalledCasks
                                                          selectedCount:2
                                                  selectedFormulaStatus:(BPFormulaStatus)status],
                       BPToolbarModeUninstall);
        XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:FormulaeSideBarItemOutdatedCasks
                                                          selectedCount:1
                                                  selectedFormulaStatus:(BPFormulaStatus)status],
                       BPToolbarModeUpdateSingle);
        XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:FormulaeSideBarItemOutdatedCasks
                                                          selectedCount:2
                                                  selectedFormulaStatus:(BPFormulaStatus)status],
                       BPToolbarModeUpdateMany);
    }
    XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:FormulaeSideBarItemAllCasks
                                                      selectedCount:1
                                              selectedFormulaStatus:kBPFormulaNotInstalled],
                   BPToolbarModeInstall);
    XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:FormulaeSideBarItemAllCasks
                                                      selectedCount:1
                                              selectedFormulaStatus:kBPFormulaInstalled],
                   BPToolbarModeUninstall);
    XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:FormulaeSideBarItemAllCasks
                                                      selectedCount:1
                                              selectedFormulaStatus:kBPFormulaOutdated],
                   BPToolbarModeUninstall);
}
- (void)testToolbarModeForFormulaSidebarRowsToolsAndOutOfBounds
{
    NSArray<NSNumber *> *formulaRows = @[
        @(FormulaeSideBarItemInstalled),
        @(FormulaeSideBarItemOutdated),
        @(FormulaeSideBarItemAll),
        @(FormulaeSideBarItemLeaves),
        @(FormulaeSideBarItemPinned)
    ];
    for (NSNumber *row in formulaRows) {
        for (NSInteger status = kBPFormulaNotInstalled; status <= kBPFormulaOutdated; status++) {
            XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:row.integerValue
                                                              selectedCount:0
                                                      selectedFormulaStatus:(BPFormulaStatus)status],
                           BPToolbarModeDefault);
            XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:row.integerValue
                                                              selectedCount:2
                                                      selectedFormulaStatus:(BPFormulaStatus)status],
                           BPToolbarModeUpdateMany);
        }
        XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:row.integerValue
                                                          selectedCount:1
                                                  selectedFormulaStatus:kBPFormulaNotInstalled],
                       BPToolbarModeInstall);
        XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:row.integerValue
                                                          selectedCount:1
                                                  selectedFormulaStatus:kBPFormulaInstalled],
                       BPToolbarModeUninstall);
        BPToolbarMode expectedOutdated = row.integerValue == FormulaeSideBarItemOutdated
            ? BPToolbarModeUpdateSingle
            : BPToolbarModeUninstall;
        XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:row.integerValue
                                                          selectedCount:1
                                                  selectedFormulaStatus:kBPFormulaOutdated],
                       expectedOutdated);
        XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:row.integerValue
                                                          selectedCount:1
                                                  selectedFormulaStatus:(BPFormulaStatus)99],
                       BPToolbarModeDefault);
    }

    NSArray<NSNumber *> *nonFormulaRows = @[
        @(-1),
        @(-99),
        @(FormulaeSideBarItemDoctor),
        @(FormulaeSideBarItemUpdate),
        @(FormulaeSideBarItemServices),
        @(99)
    ];
    for (NSNumber *row in nonFormulaRows) {
        for (NSNumber *count in @[@0, @1, @2]) {
            XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:row.integerValue
                                                              selectedCount:count.unsignedIntegerValue
                                                      selectedFormulaStatus:kBPFormulaInstalled],
                           BPToolbarModeDefault);
        }
    }

    for (NSInteger status = kBPFormulaNotInstalled; status <= kBPFormulaOutdated; status++) {
        XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:FormulaeSideBarItemUnifiedUpdates
                                                          selectedCount:0
                                                  selectedFormulaStatus:(BPFormulaStatus)status],
                       BPToolbarModeDefault);
        XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:FormulaeSideBarItemUnifiedUpdates
                                                          selectedCount:1
                                                  selectedFormulaStatus:(BPFormulaStatus)status],
                       BPToolbarModeUpdateSingle);
        XCTAssertEqual([BPFormulaeTableActions toolbarModeForSidebarRow:FormulaeSideBarItemUnifiedUpdates
                                                          selectedCount:2
                                                  selectedFormulaStatus:(BPFormulaStatus)status],
                       BPToolbarModeUpdateMany);
    }
}
- (void)testShouldShowFormulaInfoHidesDetailOnlyOnRepositoriesRow
{
    for (NSInteger row = -1; row <= (NSInteger)FormulaeSideBarItemServices + 2; row++) {
        BOOL expected = (row != FormulaeSideBarItemRepositories);
        XCTAssertEqual([BPFormulaeTableActions shouldShowFormulaInfoForSidebarRow:row],
                       expected,
                       @"row=%ld", (long)row);
    }
}
- (void)testFooterLocalizationKeyPrefersSearchAndDelegatesRowMapping
{
    for (NSInteger row = -1; row <= (NSInteger)FormulaeSideBarItemServices + 1; row++) {
        XCTAssertEqualObjects([BPFormulaeTableActions footerLocalizationKeyForSidebarRow:row searching:YES],
                              @"Sidebar_Info_SearchResults",
                              @"row=%ld", (long)row);
        XCTAssertEqualObjects([BPFormulaeTableActions footerLocalizationKeyForSidebarRow:row searching:NO],
                              [BPSideBarController infoKeyForRow:row],
                              @"row=%ld", (long)row);
    }
    XCTAssertNil([BPFormulaeTableActions footerLocalizationKeyForSidebarRow:FormulaeSideBarItemFormulaeCategory searching:NO]);
    XCTAssertNil([BPFormulaeTableActions footerLocalizationKeyForSidebarRow:FormulaeSideBarItemCasksCategory searching:NO]);
    XCTAssertNil([BPFormulaeTableActions footerLocalizationKeyForSidebarRow:FormulaeSideBarItemToolsCategory searching:NO]);
    XCTAssertNil([BPFormulaeTableActions footerLocalizationKeyForSidebarRow:-1 searching:NO]);
    XCTAssertEqualObjects([BPFormulaeTableActions footerLocalizationKeyForSidebarRow:FormulaeSideBarItemInstalled searching:NO],
                          @"Sidebar_Info_Installed");
}
- (void)testShouldRefreshVisibleListRequiresLoadedMatchingMode
{
    for (NSInteger published = kBPListAll; published <= kBPListAllCasks; published++) {
        for (NSInteger active = kBPListAll; active <= kBPListAllCasks; active++) {
            XCTAssertFalse([BPFormulaeTableActions shouldRefreshVisibleListForPublishedMode:(BPListMode)published
                                                                                 activeMode:(BPListMode)active
                                                                                  isLoading:YES]);
            XCTAssertEqual([BPFormulaeTableActions shouldRefreshVisibleListForPublishedMode:(BPListMode)published
                                                                                 activeMode:(BPListMode)active
                                                                                  isLoading:NO],
                           published == active);
        }
    }
}
- (void)testShouldSyncInstalledHostMetadataOnlyForSecondaryMetadataListsWhenLoadedAndHosted
{
    for (NSInteger published = kBPListAll; published <= kBPListAllCasks; published++) {
        for (NSInteger active = kBPListAll; active <= kBPListAllCasks; active++) {
            BOOL isMetadataMode = (published == kBPListPinned
                                   || published == kBPListOutdated
                                   || published == kBPListOutdatedCasks);
            for (NSNumber *loading in @[@NO, @YES]) {
                for (NSNumber *hosted in @[@NO, @YES]) {
                    BOOL expected = !loading.boolValue && hosted.boolValue && (active != published) && isMetadataMode;
                    XCTAssertEqual([BPFormulaeTableActions shouldSyncInstalledHostMetadataForPublishedMode:(BPListMode)published
                                                                                                activeMode:(BPListMode)active
                                                                                                 isLoading:loading.boolValue
                                                                                      isUsingInstalledHost:hosted.boolValue],
                                   expected,
                                   @"published=%ld active=%ld loading=%@ hosted=%@",
                                   (long)published, (long)active, loading, hosted);
                }
            }
        }
    }
}
- (void)testShouldSyncUnifiedUpdatesForPublishedMode
{
    for (NSInteger published = kBPListAll; published <= kBPListAllCasks; published++) {
        BOOL isUpdatesMode = (published == kBPListOutdated
                              || published == kBPListOutdatedCasks
                              || published == kBPListPinned);
        for (NSNumber *loading in @[@NO, @YES]) {
            for (NSNumber *hosted in @[@NO, @YES]) {
                BOOL expected = !loading.boolValue && hosted.boolValue && isUpdatesMode;
                XCTAssertEqual([BPFormulaeTableActions shouldSyncUnifiedUpdatesForPublishedMode:(BPListMode)published
                                                                                      isLoading:loading.boolValue
                                                                      isUsingUnifiedUpdatesHost:hosted.boolValue],
                               expected);
            }
        }
    }
}

#pragma mark - BPPackageOperationPresenter

- (void)testPresenterInstallAndUninstallAlertsAndZapCheckbox
{
    XCTAssertNil([BPPackageOperationPresenter installAlertForFormula:nil]);
    XCTAssertNil([BPPackageOperationPresenter installAlertForFormula:[BPFormula formulaWithName:@""]]);

    BPFormula *formula = [BPFormula formulaWithName:@"wget"];
    NSAlert *installAlert = [BPPackageOperationPresenter installAlertForFormula:formula];
    XCTAssertNotNil(installAlert);
    XCTAssertEqual(installAlert.buttons.count, 2u);
    XCTAssertTrue([installAlert.informativeText containsString:@"wget"]);

    XCTAssertNil([BPPackageOperationPresenter uninstallAlertForFormula:nil initialZapState:YES zapCheckbox:NULL]);
    NSButton *formulaCheckbox = nil;
    NSAlert *uninstallFormulaAlert = [BPPackageOperationPresenter uninstallAlertForFormula:formula
                                                                           initialZapState:YES
                                                                               zapCheckbox:&formulaCheckbox];
    XCTAssertNotNil(uninstallFormulaAlert);
    XCTAssertNil(formulaCheckbox);
    XCTAssertNil(uninstallFormulaAlert.accessoryView);
    XCTAssertTrue([uninstallFormulaAlert.informativeText containsString:@"wget"]);

    BPFormula *cask = [BPFormula formulaWithName:@"firefox"];
    cask.cask = YES;
    NSButton *caskCheckboxOn = nil;
    NSAlert *uninstallCaskAlertOn = [BPPackageOperationPresenter uninstallAlertForFormula:cask
                                                                          initialZapState:YES
                                                                              zapCheckbox:&caskCheckboxOn];
    XCTAssertNotNil(uninstallCaskAlertOn);
    XCTAssertNotNil(caskCheckboxOn);
    XCTAssertEqual(caskCheckboxOn.state, NSControlStateValueOn);
    XCTAssertEqual(uninstallCaskAlertOn.accessoryView, caskCheckboxOn);

    NSButton *caskCheckboxOff = nil;
    [BPPackageOperationPresenter uninstallAlertForFormula:cask
                                          initialZapState:NO
                                              zapCheckbox:&caskCheckboxOff];
    XCTAssertEqual(caskCheckboxOff.state, NSControlStateValueOff);
}

- (void)testPresenterUpgradeSelectedAndUpgradeAllAlertsAndSummaries
{
    XCTAssertNil([BPPackageOperationPresenter upgradeAlertForFormulae:nil]);
    XCTAssertNil([BPPackageOperationPresenter upgradeAlertForFormulae:@[]]);
    XCTAssertNil([BPPackageOperationPresenter upgradeAlertForFormulae:@[[BPFormula formulaWithName:@""]]]);

    BPFormula *git = [BPFormula formulaWithName:@"git"];
    BPFormula *iterm = [BPFormula formulaWithName:@"iterm2"];
    iterm.cask = YES;
    NSAlert *upgradeAlert = [BPPackageOperationPresenter upgradeAlertForFormulae:@[git, iterm]];
    XCTAssertNotNil(upgradeAlert);
    XCTAssertEqual(upgradeAlert.buttons.count, 2u);
    XCTAssertTrue([upgradeAlert.informativeText containsString:@"git, iterm2"]);

    XCTAssertNil([BPPackageOperationPresenter updatesReviewSummaryForSnapshot:nil]);
    XCTAssertNil([BPPackageOperationPresenter upgradeAllAlertForSnapshot:nil]);

    BPUpdatesSnapshot *emptySnapshot = [[BPUpdatesSnapshot alloc]
        initWithGeneration:1
        formulaItems:@[]
        caskItems:@[]
        pinnedFormulaNames:@[]
        pinnedCaskNames:@[]];
    XCTAssertNil([BPPackageOperationPresenter updatesReviewSummaryForSnapshot:emptySnapshot]);
    XCTAssertNil([BPPackageOperationPresenter upgradeAllAlertForSnapshot:emptySnapshot]);

    BPFormula *pinnedFormula = [BPFormula formulaWithName:@"openssl"];
    BPFormula *pinnedCask = [BPFormula formulaWithName:@"docker"];
    pinnedCask.cask = YES;
    BPUpdatesSnapshot *mixedSnapshot = [[BPUpdatesSnapshot alloc]
        initWithGeneration:2
        formulae:@[git, pinnedFormula]
        casks:@[iterm, pinnedCask]
        pinnedFormulae:@[pinnedFormula]
        pinnedCasks:@[pinnedCask]];
    NSString *summary = [BPPackageOperationPresenter updatesReviewSummaryForSnapshot:mixedSnapshot];
    XCTAssertNotNil(summary);
    XCTAssertTrue([summary containsString:@"git"]);
    XCTAssertTrue([summary containsString:@"iterm2"]);
    XCTAssertTrue([summary containsString:@"openssl"]);
    XCTAssertTrue([summary containsString:@"docker"]);

    NSAlert *upgradeAllAlert = [BPPackageOperationPresenter upgradeAllAlertForSnapshot:mixedSnapshot];
    XCTAssertNotNil(upgradeAllAlert);
    XCTAssertEqual(upgradeAllAlert.buttons.count, 2u);
    XCTAssertEqualObjects(upgradeAllAlert.buttons.firstObject.accessibilityIdentifier, @"updates.confirm");
    XCTAssertTrue([upgradeAllAlert.accessoryView isKindOfClass:NSScrollView.class]);

    NSAlert *changedAlert = [BPPackageOperationPresenter updatesChangedAlert];
    XCTAssertNotNil(changedAlert);
    XCTAssertEqual(changedAlert.buttons.count, 1u);
}

- (void)testPresenterTapUntapCleanupBrewfileInventoriesAndResolvedSelection
{
    NSTextField *inputField = nil;
    NSAlert *tapAlert = [BPPackageOperationPresenter tapInputAlertWithInputField:&inputField];
    XCTAssertNotNil(tapAlert);
    XCTAssertNotNil(inputField);
    XCTAssertNotNil(tapAlert.accessoryView);
    BPTapInputHost *tapHost = [BPPackageOperationPresenter tapInputHostForAlert:tapAlert];
    XCTAssertNotNil(tapHost);
    XCTAssertEqual(tapHost.inputField, inputField);
    XCTAssertFalse(tapHost.isValidFormat);
    tapHost.repositoryName = @"homebrew/cask";
    XCTAssertTrue(tapHost.isValidFormat);
    XCTAssertEqualObjects(inputField.stringValue, @"homebrew/cask");
    XCTAssertEqual(tapAlert.buttons.count, 2u);

    NSAlert *invalidTap = [BPPackageOperationPresenter invalidTapAlert];
    XCTAssertNotNil(invalidTap);
    XCTAssertEqual(invalidTap.buttons.count, 1u);

    XCTAssertNil([BPPackageOperationPresenter untapAlertForFormula:nil]);
    BPFormula *repo = [BPFormula formulaWithName:@"homebrew/cask"];
    NSAlert *untapAlert = [BPPackageOperationPresenter untapAlertForFormula:repo];
    XCTAssertNotNil(untapAlert);
    XCTAssertTrue([untapAlert.informativeText containsString:@"homebrew/cask"]);

    BPCleanupPreview *emptyPreview = [BPCleanupPreview previewFromOutput:@""];
    NSAlert *emptyCleanupAlert = [BPPackageOperationPresenter cleanupAlertForPreview:emptyPreview];
    XCTAssertEqual(emptyCleanupAlert.buttons.count, 1u);
    XCTAssertNil([BPPackageOperationPresenter cleanupPreviewHostForAlert:emptyCleanupAlert]);

    BPCleanupPreview *noSizePreview = [BPCleanupPreview previewFromOutput:@"Would remove: /tmp/a\n"];
    NSString *noSizeBody = [BPPackageOperationPresenter cleanupConfirmationBodyForPreview:noSizePreview];
    XCTAssertGreaterThan(noSizeBody.length, 0u);
    NSAlert *nonEmptyCleanupAlert = [BPPackageOperationPresenter cleanupAlertForPreview:noSizePreview];
    XCTAssertEqual(nonEmptyCleanupAlert.buttons.count, 2u);
    BPCleanupPreviewHost *cleanupHost = [BPPackageOperationPresenter cleanupPreviewHostForAlert:nonEmptyCleanupAlert];
    XCTAssertNotNil(cleanupHost);
    XCTAssertEqual(cleanupHost.itemCount, 1);

    BPCleanupPreview *sizedPreview = [BPCleanupPreview previewFromOutput:
        @"Would remove: /tmp/a (10KB)\nWould remove: /tmp/b (20KB)\n==> This operation would free approximately 100MB of disk space.\n"];
    NSString *sizedBody = [BPPackageOperationPresenter cleanupConfirmationBodyForPreview:sizedPreview];
    XCTAssertGreaterThan(sizedBody.length, 0u);

    BPFormula *brewPkg = [BPFormula formulaWithName:@"wget"];
    BPFormula *caskPkg = [BPFormula formulaWithName:@"firefox"];
    caskPkg.cask = YES;
    NSDictionary<NSString *, NSArray<NSString *> *> *inventories =
        [BPPackageOperationPresenter brewfileInventoriesForInstalledFormulae:@[brewPkg]
                                                              installedCasks:@[caskPkg]
                                                                repositories:@[repo]];
    XCTAssertEqualObjects(inventories[@"brew"], @[@"wget"]);
    XCTAssertEqualObjects(inventories[@"cask"], @[@"firefox"]);
    XCTAssertEqualObjects(inventories[@"tap"], @[@"homebrew/cask"]);
    XCTAssertEqualObjects(([BPPackageOperationPresenter brewfileInventoriesForInstalledFormulae:nil
                                                                                 installedCasks:nil
                                                                                   repositories:nil]), @{});

    // Heterogeneous resolution preserves namespace flags and uses live manager models when present
    BPFormula *sharedFormula = [BPFormula formulaWithName:@"shared" andVersion:@"1.0"];
    BPFormula *sharedCask = [BPFormula formulaWithName:@"shared" andVersion:@"2.0"];
    sharedCask.cask = YES;
    NSArray<BPFormula *> *resolved = [BPPackageOperationPresenter
        resolvedSelectionForFormulaNames:@[@"shared", @"fallback-formula"]
                               caskNames:@[@"shared", @"fallback-cask"]
                        outdatedFormulae:@[sharedFormula]
                           outdatedCasks:@[sharedCask]];
    XCTAssertEqual(resolved.count, 4u);
    XCTAssertEqual(resolved[0], sharedFormula);
    XCTAssertFalse(resolved[0].cask);
    XCTAssertEqualObjects(resolved[1].name, @"fallback-formula");
    XCTAssertFalse(resolved[1].cask);
    XCTAssertEqual(resolved[2], sharedCask);
    XCTAssertTrue(resolved[2].cask);
    XCTAssertEqualObjects(resolved[3].name, @"fallback-cask");
    XCTAssertTrue(resolved[3].cask);
}
@end
