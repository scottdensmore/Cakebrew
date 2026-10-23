#import <XCTest/XCTest.h>
#import "BPFormulaPopoverViewController.h"
#import "BPSelectedFormulaViewController.h"
#import "BPHomebrewViewController.h"
#import "BPHomebrewManager.h"
#import "BPHomebrewInterface.h"
#import "BPMockHomebrewInterface.h"
#import "BPSideBarController.h"
#import "BPFormulaeDataSource.h"
#import "BPFormulaeTableView.h"
#import "BPToolbar.h"
#import "BPDoctorViewController.h"
#import "BPUpdateViewController.h"
#import "BPServicesViewController.h"
#import "BPInstallationWindowController.h"
#import "BPFormulaOptionsWindowController.h"
#import "BPAutoremoveWindowController.h"
#import "BPBundleWindowController.h"
#import "BPBrewfilePlan.h"
#import "BPDisabledView.h"
#import "BPLoadingView.h"
#import "BPEmptyState.h"
#import "BPEmptyStateView.h"
#import "BPPreferences.h"
#import "BPPreferencesWindowController.h"
#import "BPAutoScrollTextView.h"
#import "BPMainWindowController.h"
#import "BPStyle.h"
#import "BPTask.h"
#import "DCOAboutWindowController.h"
#import "BPFormulaeTableAction.h"
#import "BPCleanupPreview.h"
#import "BPFormulaInformation-Swift.h"

@interface BPHomebrewInterface (BPTestingInjection)
+ (void)setSharedInterfaceForTesting:(BPHomebrewInterface *)interface;
- (instancetype)initUniqueInstance;
@end

@interface BPToolbar (BPTestingAccess)
@property (assign) BPToolbarMode currentMode;
@end

@interface BPHomebrewViewController (BPTestingAccess)
- (BPFormula *)selectedFormula;
- (void)performSearchWithString:(NSString *)searchPhrase;
- (BOOL)isSearching;
@end

@interface BPInstallationWindowController (BPTestingAccess)
@property (nonatomic) BPWindowOperation windowOperation;
@property (strong, nonatomic) NSArray *formulae;
@property (strong, nonatomic) NSArray *options;
@property (nonatomic) BOOL zapCask;
- (void)cleanupAfterTask;
@end

@interface BPFormulaOptionsWindowController (BPTestingAccess)
@property (nonatomic, strong) NSMutableArray *availableOptions;
@property (strong) BPFormula *formula;
@property (strong, nonatomic) BPFormulaOptionsHost *optionsHost;
- (NSArray *)allSelectedOptions;
@end

// Model loads and AppKit animations are replaced at the boundary. The production
// controller still registers and receives real NSNotificationCenter events.
@interface BPInformationTestPopover : NSObject
@property (strong) NSViewController *contentViewController;
@property NSPopoverBehavior behavior;
@end
@implementation BPInformationTestPopover
@end

@interface BPInformationTestHost : NSObject
@property (strong) NSViewController *viewController;
@property (copy) NSString *name;
@property BOOL cask;
@property BPFormulaInfoType infoType;
@property (copy) NSString *information;
@property uint64_t generation;
@property BOOL open;
@end
@implementation BPInformationTestHost
- (instancetype)init
{
    self = [super init];
    if (self) {
        _viewController = [NSViewController new];
    }
    return self;
}
- (uint64_t)beginWithName:(NSString *)name cask:(BOOL)cask
{
    return [self beginWithName:name cask:cask infoType:kBPFormulaInfoTypeGeneral];
}
- (uint64_t)beginWithName:(NSString *)name cask:(BOOL)cask infoType:(BPFormulaInfoType)infoType
{
    self.name = name;
    self.cask = cask;
    self.infoType = infoType;
    self.information = nil;
    self.open = YES;
    return ++_generation;
}
- (void)receiveInformation:(NSString *)information website:(NSURL *)website name:(NSString *)name
                     cask:(BOOL)cask generation:(uint64_t)generation
{
    [self receiveInformation:information website:website name:name cask:cask
                    infoType:kBPFormulaInfoTypeGeneral generation:generation];
}
- (void)receiveInformation:(NSString *)information website:(NSURL *)website name:(NSString *)name
                     cask:(BOOL)cask infoType:(BPFormulaInfoType)infoType generation:(uint64_t)generation
{
    if (self.open && generation == self.generation && self.infoType == infoType
        && self.cask == cask && [self.name isEqualToString:name]) {
        self.information = information;
    }
}
- (void)close
{
    self.open = NO;
    self.name = nil;
    self.information = nil;
}
@end

@interface BPSelectedFormulaTestHost : NSObject
@property (strong) NSViewController *viewController;
@property (copy) NSString *name;
@property BOOL cask;
@property BOOL installed;
@property BOOL pinned;
@property (copy) NSString *shortDescription;
@property (copy) NSArray<NSString *> *dependents;
@property BOOL isMultiple;
@property BOOL isEmpty;
@property uint64_t generation;
@end
@implementation BPSelectedFormulaTestHost
- (instancetype)init
{
    self = [super init];
    if (self) {
        _viewController = [NSViewController new];
        _viewController.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 120)];
        _isEmpty = YES;
    }
    return self;
}
- (void)clearSelection
{
    self.isEmpty = YES;
    self.isMultiple = NO;
    self.name = nil;
    self.dependents = nil;
    ++_generation;
}
- (void)showMultipleSelection
{
    self.isEmpty = NO;
    self.isMultiple = YES;
    self.name = nil;
    self.dependents = nil;
    ++_generation;
}
- (uint64_t)beginSelectionWithName:(NSString *)name cask:(BOOL)cask installed:(BOOL)installed
                            pinned:(BOOL)pinned installPath:(NSString *)installPath
                     latestVersion:(NSString *)latestVersion dependencies:(NSString *)dependencies
                         conflicts:(NSString *)conflicts shortDescription:(NSString *)shortDescription
{
    self.isEmpty = NO;
    self.isMultiple = NO;
    self.name = name;
    self.cask = cask;
    self.installed = installed;
    self.pinned = pinned;
    self.shortDescription = shortDescription;
    self.dependents = nil;
    return ++_generation;
}
- (void)updateSelectionWithName:(NSString *)name cask:(BOOL)cask installed:(BOOL)installed
                         pinned:(BOOL)pinned installPath:(NSString *)installPath
                  latestVersion:(NSString *)latestVersion dependencies:(NSString *)dependencies
                      conflicts:(NSString *)conflicts shortDescription:(NSString *)shortDescription
{
    if (!self.isEmpty && !self.isMultiple && self.cask == cask && [self.name isEqualToString:name]) {
        self.installed = installed;
        self.pinned = pinned;
        self.shortDescription = shortDescription;
    }
}
- (void)receiveDependents:(NSArray<NSString *> *)dependents name:(NSString *)name
                     cask:(BOOL)cask generation:(uint64_t)generation
{
    if (!self.isEmpty && !self.isMultiple && generation == self.generation
        && self.cask == cask && [self.name isEqualToString:name]) {
        self.dependents = dependents;
    }
}
@end

@interface BPInformationCachedFormula : BPFormula
@end
@implementation BPInformationCachedFormula
- (NSString *)information { return @"cached mock information"; }
@end

@interface BPFormulaInformationLifecycleTests : XCTestCase
@property (strong) BPFormulaPopoverViewController *controller;
@property (strong) BPInformationTestPopover *popover;
@property (strong) BPInformationTestHost *host;
@property (strong) BPFormula *formula;
@end

@implementation BPFormulaInformationLifecycleTests
- (void)setUp
{
    [super setUp];
    self.controller = [BPFormulaPopoverViewController new];
    self.popover = [BPInformationTestPopover new];
    self.popover.behavior = NSPopoverBehaviorSemitransient;
    self.host = [BPInformationTestHost new];
    self.formula = [BPInformationCachedFormula formulaWithName:@"mockwget"];
    self.controller.formulaPopover = (NSPopover *)self.popover;
    [self.controller awakeFromNib];
    [self.controller setValue:self.host forKey:@"informationHost"];
    self.controller.formula = self.formula;
}

- (void)tearDown
{
    // Release the fake popover's retained controller before releasing our owner.
    self.popover.contentViewController = nil;
    self.controller = nil;
    self.popover = nil;
    self.host = nil;
    self.formula = nil;
    [super tearDown];
}

- (void)postCloseNotification:(NSNotificationName)name
{
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:self.popover];
}

- (void)finishOldCloseOnNextRunLoop
{
    XCTestExpectation *finished = [self expectationWithDescription:@"old close animation finished"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self postCloseNotification:NSPopoverDidCloseNotification];
        [finished fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testGeneralInformationUsesTransientBehaviorAndDependentsRestoreSemitransient
{
    XCTAssertEqual(self.popover.behavior, NSPopoverBehaviorTransient);
    self.controller.infoType = kBPFormulaInfoTypeInstalledDependents;
    XCTAssertEqual(self.popover.behavior, NSPopoverBehaviorSemitransient);
    self.controller.infoType = kBPFormulaInfoTypeGeneral;
    XCTAssertEqual(self.popover.behavior, NSPopoverBehaviorTransient);
    self.controller.infoType = kBPFormulaInfoTypeAllDependents;
    XCTAssertEqual(self.popover.behavior, NSPopoverBehaviorSemitransient);
    self.controller.infoType = kBPFormulaInfoTypeGeneral;
    XCTAssertEqual(self.popover.behavior, NSPopoverBehaviorTransient);
}

- (void)testOldAnimatedCloseCannotClearReopenedInformation
{
    [self postCloseNotification:NSPopoverWillCloseNotification];
    self.controller.formula = self.formula;
    XCTAssertEqualObjects(self.host.information, @"cached mock information");
    // The old animation completes after the next presentation has begun.
    [self finishOldCloseOnNextRunLoop];
    XCTAssertTrue(self.host.open);
    XCTAssertEqualObjects(self.host.name, @"mockwget");
    XCTAssertEqualObjects(self.host.information, @"cached mock information");
}

- (void)testDependentModeCloseCannotClearReturningInformation
{
    [self postCloseNotification:NSPopoverWillCloseNotification];
    self.controller.infoType = kBPFormulaInfoTypeInstalledDependents;
    XCTAssertFalse(self.host.open);
    // Close the dependent view, then begin information before its animation ends.
    [self postCloseNotification:NSPopoverWillCloseNotification];
    self.controller.infoType = kBPFormulaInfoTypeGeneral;
    self.controller.formula = self.formula;
    [self finishOldCloseOnNextRunLoop];
    XCTAssertTrue(self.host.open);
    XCTAssertEqualObjects(self.host.information, @"cached mock information");
}

- (void)testCurrentPresentationIsInvalidatedWhenClosingBegins
{
    XCTAssertTrue(self.host.open);
    [self postCloseNotification:NSPopoverWillCloseNotification];
    XCTAssertFalse(self.host.open, @"Late provider responses must be rejected during closing animation");
    XCTAssertNil(self.host.information);
}

- (void)testUnrelatedPopoverCloseDoesNotInvalidateInformation
{
    BPInformationTestPopover *other = [BPInformationTestPopover new];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSPopoverWillCloseNotification object:other];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSPopoverDidCloseNotification object:other];
    XCTAssertTrue(self.host.open);
    XCTAssertEqualObjects(self.host.information, @"cached mock information");
}

- (void)testDependentsModesHostSwiftViewControllerAndRejectStaleResponses
{
    XCTestExpectation *delivered = [self expectationWithDescription:@"dependents delivered"];
    self.controller.dependentsProvider = ^NSString *(NSString *name, BOOL onlyInstalled) {
        return onlyInstalled ? [NSString stringWithFormat:@"%@-installed-dep", name]
                             : [NSString stringWithFormat:@"%@-all-dep", name];
    };
    self.controller.infoType = kBPFormulaInfoTypeInstalledDependents;
    self.controller.formula = [BPFormula formulaWithName:@"mockwget"];
    XCTAssertEqual(self.popover.contentViewController, self.host.viewController);
    XCTAssertEqual(self.host.infoType, kBPFormulaInfoTypeInstalledDependents);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [delivered fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    XCTAssertEqualObjects(self.host.information, @"mockwget-installed-dep");

    XCTestExpectation *allDelivered = [self expectationWithDescription:@"all dependents delivered"];
    self.controller.infoType = kBPFormulaInfoTypeAllDependents;
    self.controller.formula = [BPFormula formulaWithName:@"mockwget"];
    XCTAssertEqual(self.host.infoType, kBPFormulaInfoTypeAllDependents);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [allDelivered fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    XCTAssertEqualObjects(self.host.information, @"mockwget-all-dep");
}

- (void)testSelectedFormulaControllerRoutesSingleMultipleEmptyAndNotificationUpdates
{
    BPSelectedFormulaViewController *selected = [BPSelectedFormulaViewController new];
    BPSelectedFormulaTestHost *inspectorHost = [BPSelectedFormulaTestHost new];
    [selected setValue:inspectorHost forKey:@"inspectorHost"];
    __unused NSView *loadedView = selected.view;

    BPFormula *formula = [BPFormula formulaWithName:@"shared"];
    [formula setValue:@"Initial description" forKey:@"shortDescription"];
    BPFormula *sameNamedCask = [BPFormula formulaWithName:@"shared"];
    sameNamedCask.cask = YES;
    [sameNamedCask setValue:@"Cask description" forKey:@"shortDescription"];

    selected.formulae = @[formula];
    XCTAssertFalse(inspectorHost.isEmpty);
    XCTAssertFalse(inspectorHost.isMultiple);
    XCTAssertEqualObjects(inspectorHost.name, @"shared");
    XCTAssertFalse(inspectorHost.cask);
    XCTAssertEqualObjects(inspectorHost.shortDescription, @"Initial description");

    // Notification from a same-named cask must not overwrite the selected formula.
    [formula setValue:@"Updated formula description" forKey:@"shortDescription"];
    [[NSNotificationCenter defaultCenter] postNotificationName:BPFormulaDidUpdateNotification object:sameNamedCask];
    [[NSNotificationCenter defaultCenter] postNotificationName:BPFormulaDidUpdateNotification object:formula];
    XCTestExpectation *notified = [self expectationWithDescription:@"main queue notification processed"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [notified fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    XCTAssertEqualObjects(inspectorHost.shortDescription, @"Updated formula description");

    selected.formulae = @[formula, sameNamedCask];
    XCTAssertTrue(inspectorHost.isMultiple);

    selected.formulae = @[];
    XCTAssertTrue(inspectorHost.isEmpty);
}

- (void)testInstalledPackageListHostSyncsSelectionSortAndActionCallbacks
{
    BPInstalledPackageListHost *listHost = [[BPInstalledPackageListHost alloc] init];
    NSMutableArray<NSString *> *selectionEvents = [NSMutableArray array];
    NSMutableArray<NSString *> *sortEvents = [NSMutableArray array];
    NSMutableArray<NSNumber *> *actionEvents = [NSMutableArray array];

    listHost.onSelectionChanged = ^(NSString * _Nullable name, BOOL cask) {
        [selectionEvents addObject:name ? [NSString stringWithFormat:@"%@:%d", name, cask] : @"none"];
    };
    listHost.onSortChanged = ^(NSString * _Nullable key, BOOL ascending) {
        [sortEvents addObject:[NSString stringWithFormat:@"%@:%d", key ?: @"", ascending]];
    };
    listHost.onTableAction = ^(NSInteger request) {
        [actionEvents addObject:@(request)];
    };

    [listHost updateRowsWithNames:@[@"wget", @"ack"]
                         versions:@[@"1.24", @"3.7"]
                   latestVersions:@[@"1.24", @"3.7"]
                      statusRanks:@[@1, @1]
                      pinnedFlags:@[@NO, @YES]
                             cask:NO];

    XCTAssertEqual(listHost.rowCount, 2);
    XCTAssertEqual([listHost indexOfPackageNamed:@"ack" cask:NO], 1);
    XCTAssertEqual([listHost indexOfPackageNamed:@"ack" cask:YES], -1);

    [listHost applySortColumnIdentifier:@"Name" ascending:YES];
    XCTAssertEqual([listHost indexOfPackageNamed:@"ack" cask:NO], 0);
    XCTAssertEqual([listHost indexOfPackageNamed:@"wget" cask:NO], 1);

    XCTAssertTrue([listHost selectPackageNamed:@"wget" cask:NO]);
    XCTAssertEqual(listHost.selectedRow, 1);
    XCTAssertEqualObjects(listHost.selectedPackageName, @"wget");
    XCTAssertFalse(listHost.selectedPackageCask);
    XCTAssertEqualObjects(selectionEvents.lastObject, @"wget:0");

    [listHost deselectAll];
    XCTAssertEqual(listHost.selectedRow, -1);
    XCTAssertNil(listHost.selectedPackageName);
    XCTAssertEqualObjects(selectionEvents.lastObject, @"none");
}

- (void)testInstalledPackageListHostKeyboardRoutingAndPopoverAnchorFallback
{
    BPInstalledPackageListHost *listHost = [[BPInstalledPackageListHost alloc] init];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window.contentView addSubview:listHost.viewController.view];
    listHost.viewController.view.frame = window.contentView.bounds;
    [window makeFirstResponder:listHost.viewController.view];

    __block NSInteger spacePresses = 0;
    NSMutableArray<NSNumber *> *actions = [NSMutableArray array];
    listHost.onSpacePressed = ^{
        spacePresses++;
    };
    listHost.onTableAction = ^(NSInteger request) {
        [actions addObject:@(request)];
    };

    [listHost updateRowsWithNames:@[@"wget"]
                         versions:@[@"1.24"]
                   latestVersions:@[@"1.24"]
                      statusRanks:@[@1]
                      pinnedFlags:@[@NO]
                             cask:NO];
    XCTAssertTrue([listHost selectPackageNamed:@"wget" cask:NO]);

    NSEvent *(^makeKey)(unichar, NSEventModifierFlags, BOOL) = ^NSEvent *(unichar ch, NSEventModifierFlags flags, BOOL repeat) {
        NSString *chars = [NSString stringWithCharacters:&ch length:1];
        return [NSEvent keyEventWithType:NSEventTypeKeyDown
                                location:NSZeroPoint
                           modifierFlags:flags
                               timestamp:0
                            windowNumber:window.windowNumber
                                 context:nil
                              characters:chars
             charactersIgnoringModifiers:chars
                               isARepeat:repeat
                                 keyCode:0];
    };

    XCTAssertTrue([listHost handleKeyDownEvent:makeKey(' ', 0, NO)]);
    XCTAssertEqual(spacePresses, 1);

    XCTAssertTrue([listHost handleKeyDownEvent:makeKey(NSCarriageReturnCharacter, 0, NO)]);
    XCTAssertTrue([listHost handleKeyDownEvent:makeKey(NSEnterCharacter, 0, NO)]);
    XCTAssertTrue([listHost handleKeyDownEvent:makeKey(NSDeleteCharacter, 0, NO)]);
    XCTAssertTrue([listHost handleKeyDownEvent:makeKey(NSDeleteFunctionKey, 0, NO)]);
    XCTAssertEqualObjects(actions, (@[@0, @0, @1, @1]));

    // Modifiers and repeats are rejected for Return/Delete
    XCTAssertFalse([listHost handleKeyDownEvent:makeKey(NSCarriageReturnCharacter, NSEventModifierFlagCommand, NO)]);
    XCTAssertFalse([listHost handleKeyDownEvent:makeKey(NSDeleteCharacter, 0, YES)]);
    XCTAssertEqual(actions.count, 4u);

    NSRect anchor = [listHost rectOfSelectedRowInView:listHost.viewController.view];
    XCTAssertFalse(NSIsEmptyRect(anchor));
}

- (NSTableView *)findTableViewInView:(NSView *)view
{
    if ([view isKindOfClass:[NSTableView class]]) {
        return (NSTableView *)view;
    }
    for (NSView *subview in view.subviews) {
        NSTableView *found = [self findTableViewInView:subview];
        if (found) return found;
    }
    return nil;
}

- (void)testInstalledPackageListHostAttachesBridgeToUnderlyingTableViewAndSyncsMenuAndRowGeometry
{
    BPInstalledPackageListHost *listHost = [[BPInstalledPackageListHost alloc] init];
    NSMenu *contextMenu = [[NSMenu alloc] init];
    listHost.contextMenu = contextMenu;

    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 400)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    listHost.viewController.view.frame = window.contentView.bounds;
    [window.contentView addSubview:listHost.viewController.view];

    [listHost updateRowsWithNames:@[@"ack", @"wget"]
                         versions:@[@"3.7", @"1.24"]
                   latestVersions:@[@"3.7", @"1.24"]
                      statusRanks:@[@1, @1]
                      pinnedFlags:@[@YES, @NO]
                             cask:NO];

    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
    [window.contentView layoutSubtreeIfNeeded];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.10]];

    NSTableView *underlyingTable = [self findTableViewInView:listHost.viewController.view];
    XCTAssertNotNil(underlyingTable, @"SwiftUI Table must mount an underlying NSTableView");
    XCTAssertEqual(underlyingTable.menu, contextMenu, @"Bridge must wire the context menu to the underlying NSTableView");
    XCTAssertNotNil(underlyingTable.target, @"Bridge must wire doubleAction target");
    XCTAssertNotEqual(underlyingTable.doubleAction, NULL, @"Bridge must wire doubleAction selector");
    XCTAssertEqual(underlyingTable.numberOfRows, 2);

    XCTAssertTrue([listHost selectPackageNamed:@"wget" cask:NO]);
    XCTAssertEqual(underlyingTable.selectedRow, 1);

    NSRect rowRect = [listHost rectOfSelectedRowInView:listHost.viewController.view];
    XCTAssertFalse(NSIsEmptyRect(rowRect));
    XCTAssertGreaterThan(rowRect.size.width, 100.0);

    NSRect firstRowRect = [underlyingTable rectOfRow:0];
    NSPoint firstRowPointInWindow = [underlyingTable convertPoint:NSMakePoint(NSMidX(firstRowRect), NSMidY(firstRowRect)) toView:nil];
    NSEvent *rightClick = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown
                                             location:firstRowPointInWindow
                                        modifierFlags:0
                                            timestamp:0
                                         windowNumber:window.windowNumber
                                              context:nil
                                          eventNumber:0
                                           clickCount:1
                                             pressure:1.0];
    XCTAssertEqual([underlyingTable menuForEvent:rightClick], contextMenu);
    XCTAssertEqual(underlyingTable.clickedRow, 0);
    [listHost selectClickedRowIfNeeded];
    XCTAssertEqual(listHost.selectedRow, 0);
    XCTAssertEqualObjects(listHost.selectedPackageName, @"ack");
}

@end

// MARK: - End-to-End In-Process Feature Journey Suite

@interface BPEndToEndFeatureJourneyTests : XCTestCase
@property (strong) BPMockHomebrewInterface *mockInterface;
@property (strong) BPSideBarController *retainedSidebarController;
@property (strong) NSMenu *retainedFormulaMenu;
@property (copy) NSString *savedSortColumn;
@property BOOL savedSortAscending;
@property NSInteger savedSidebarRow;
@property BOOL savedBackgroundCheck;
@property NSTimeInterval savedBackgroundInterval;
@property BOOL savedGreedy;
@property BOOL savedAutoAppUpdates;
@property BOOL savedShowMenuBarExtra;
@end

@implementation BPEndToEndFeatureJourneyTests

- (void)setUp
{
    [super setUp];
    self.savedSortColumn = [BPPreferences sortColumnIdentifier];
    self.savedSortAscending = [BPPreferences sortAscending];
    self.savedSidebarRow = [BPPreferences lastSelectedSidebarRow];
    self.savedBackgroundCheck = [BPPreferences backgroundCheckEnabled];
    self.savedBackgroundInterval = [BPPreferences backgroundCheckInterval];
    self.savedGreedy = [BPPreferences greedyCaskUpgrades];
    self.savedAutoAppUpdates = [BPPreferences automaticAppUpdateCheckEnabled];
    self.savedShowMenuBarExtra = [BPPreferences showMenuBarExtra];

    [BPPreferences setSortColumnIdentifier:nil];
    [BPPreferences setSortAscending:YES];
    [BPPreferences setLastSelectedSidebarRow:FormulaeSideBarItemInstalled];
    [BPPreferences setShowMenuBarExtra:NO];

    self.mockInterface = [(BPMockHomebrewInterface *)[NSClassFromString(@"BPMockHomebrewInterface") alloc] initUniqueInstance];
    [BPHomebrewInterface setSharedInterfaceForTesting:self.mockInterface];
    [BPAppDelegateRef setRunningBackgroundTask:NO];
    [[BPHomebrewManager sharedManager] setValue:@NO forKey:@"reloadInFlight"];
    [[BPHomebrewManager sharedManager] setValue:@NO forKey:@"discoveryInFlight"];
    [self populateMockHomebrewCatalog];
}

- (void)tearDown
{
    [BPAppDelegateRef setRunningBackgroundTask:NO];
    [BPHomebrewInterface setSharedInterfaceForTesting:nil];
    self.mockInterface = nil;
    self.retainedSidebarController = nil;
    self.retainedFormulaMenu = nil;

    [BPPreferences setSortColumnIdentifier:self.savedSortColumn];
    [BPPreferences setSortAscending:self.savedSortAscending];
    [BPPreferences setLastSelectedSidebarRow:self.savedSidebarRow];
    [BPPreferences setBackgroundCheckEnabled:self.savedBackgroundCheck];
    [BPPreferences setBackgroundCheckInterval:self.savedBackgroundInterval];
    [BPPreferences setGreedyCaskUpgrades:self.savedGreedy];
    [BPPreferences setAutomaticAppUpdateCheckEnabled:self.savedAutoAppUpdates];
    [BPPreferences setShowMenuBarExtra:self.savedShowMenuBarExtra];
    [BPAppDelegateRef updateMenuBarExtra];
    [super tearDown];
}

- (void)populateMockHomebrewCatalog
{
    BPHomebrewManager *manager = [BPHomebrewManager sharedManager];
    NSArray<BPFormula *> *installed = [self.mockInterface listMode:kBPListInstalled];
    NSArray<BPFormula *> *installedCasks = [self.mockInterface listMode:kBPListInstalledCasks];
    NSArray<BPFormula *> *leaves = [self.mockInterface listMode:kBPListLeaves];
    NSArray<BPFormula *> *pinned = [self.mockInterface listMode:kBPListPinned];
    NSArray<BPFormula *> *outdated = [self.mockInterface listMode:kBPListOutdated];
    NSArray<BPFormula *> *outdatedCasks = [self.mockInterface listMode:kBPListOutdatedCasks];
    NSArray<BPFormula *> *allFormulae = [self.mockInterface listMode:kBPListAll];
    NSArray<BPFormula *> *allCasks = [self.mockInterface listMode:kBPListAllCasks];
    NSArray<BPFormula *> *repos = [self.mockInterface listMode:kBPListRepositories];

    [manager setValue:installed forKey:@"installedFormulae"];
    [manager setValue:installedCasks forKey:@"installedCasks"];
    [manager setValue:leaves forKey:@"leavesFormulae"];
    [manager setValue:pinned forKey:@"pinnedFormulae"];
    [manager setValue:outdated forKey:@"outdatedFormulae"];
    [manager setValue:outdatedCasks forKey:@"outdatedCasks"];
    [manager setValue:allFormulae forKey:@"allFormulae"];
    [manager setValue:allCasks forKey:@"allCasks"];
    [manager setValue:repos forKey:@"repositoriesFormulae"];
    [manager setValue:@[] forKey:@"searchFormulae"];
}

- (BPHomebrewViewController *)makeWiredHomebrewViewControllerInWindow:(NSWindow * __autoreleasing *)outWindow
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 680)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    BPHomebrewViewController *vc = [[BPHomebrewViewController alloc] init];
    NSView *rootView = [[NSView alloc] initWithFrame:window.contentView.bounds];
    vc.view = rootView;
    [window.contentView addSubview:rootView];

    NSSplitView *formulaeSplitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 120, 800, 480)];
    BPFormulaeTableView *tableView = [[BPFormulaeTableView alloc] initWithFrame:scrollView.bounds];
    scrollView.documentView = tableView;
    NSView *selectedFormulaContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 120)];
    [formulaeSplitView addSubview:scrollView];
    [formulaeSplitView addSubview:selectedFormulaContainer];

    NSTabView *tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    for (NSUInteger idx = 0; idx < 4; idx++) {
        NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:@(idx)];
        [tabView addTabViewItem:item];
    }
    [rootView addSubview:tabView];

    NSTextField *infoLabel = [NSTextField labelWithString:@""];
    [rootView addSubview:infoLabel];
    NSMenu *formulaMenu = [[NSMenu alloc] initWithTitle:@"Formula"];
    for (NSString *title in @[@"Install Formula", @"Uninstall Formula", @"Update Formula",
                              @"More Information", @"Formula Website", @"Pin Formula",
                              @"Unpin Formula", @"Install Formula with Options..."]) {
        [formulaMenu addItemWithTitle:title action:NULL keyEquivalent:@""];
    }
    self.retainedFormulaMenu = formulaMenu;

    BPSideBarController *sidebarController = [[BPSideBarController alloc] init];
    self.retainedSidebarController = sidebarController;
    NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 200, 600)];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"MainColumn"];
    [outline addTableColumn:col];
    outline.outlineTableColumn = col;
    [rootView addSubview:outline];
    sidebarController.sidebar = outline;
    outline.dataSource = sidebarController;
    outline.delegate = sidebarController;
    [outline reloadData];
    [outline expandItem:nil expandChildren:YES];

    [vc setValue:formulaeSplitView forKey:@"formulaeSplitView"];
    vc.scrollView_formulae = scrollView;
    vc.formulaeTableView = tableView;
    [vc setValue:selectedFormulaContainer forKey:@"selectedFormulaView"];
    vc.tabView = tabView;
    vc.label_information = infoLabel;
    vc.menu_formula = formulaMenu;
    vc.sidebarController = sidebarController;

    [vc viewDidLoad];
    [(id<BPHomebrewManagerDelegate>)vc homebrewManagerFinishedUpdating:[BPHomebrewManager sharedManager]];

    if (outWindow) {
        *outWindow = window;
    }
    return vc;
}

- (void)testEndToEndAllTenPackageListModesAndSearchThroughHomebrewViewController
{
    NSWindow *window = nil;
    BPHomebrewViewController *vc = [self makeWiredHomebrewViewControllerInWindow:&window];
    BPInstalledPackageListHost *listHost = [vc valueForKey:@"installedPackageListHost"];
    BPToolbar *toolbar = [vc valueForKey:@"toolbar"];
    XCTAssertNotNil(listHost);
    XCTAssertNotNil(toolbar);
    XCTAssertNil([vc valueForKey:@"loadingView"], @"Loading overlay must be dismissed when catalog finishes updating");

    struct {
        FormulaeSideBarItem row;
        NSInteger expectedCount;
        __unsafe_unretained NSString *sampleName;
        BOOL isCask;
        BPToolbarMode expectedToolbarModeWhenSelected;
    } modes[] = {
        { FormulaeSideBarItemInstalled, 3, @"mockwget", NO, BPToolbarModeUninstall },
        { FormulaeSideBarItemInstalledCasks, 2, @"mockchrome", YES, BPToolbarModeUninstall },
        { FormulaeSideBarItemOutdated, 1, @"mockgit", NO, BPToolbarModeUpdateSingle },
        { FormulaeSideBarItemOutdatedCasks, 1, @"mockchrome", YES, BPToolbarModeUpdateSingle },
        { FormulaeSideBarItemAll, 4, @"mockhtop", NO, BPToolbarModeInstall },
        { FormulaeSideBarItemAllCasks, 3, @"mockfirefox", YES, BPToolbarModeInstall },
        { FormulaeSideBarItemLeaves, 1, @"mockwget", NO, BPToolbarModeUninstall },
        { FormulaeSideBarItemPinned, 1, @"mockgit", NO, BPToolbarModeUninstall },
        { FormulaeSideBarItemRepositories, 2, @"homebrew/core", NO, BPToolbarModeUntap },
    };

    for (size_t i = 0; i < sizeof(modes) / sizeof(modes[0]); i++) {
        NSInteger sidebarRow = modes[i].row;
        [vc.sidebarController.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)sidebarRow]
                                  byExtendingSelection:NO];
        [(id<BPSideBarControllerDelegate>)vc sourceListSelectionDidChange];

        XCTAssertEqual(listHost.rowCount, modes[i].expectedCount,
                       @"Row count mismatch for sidebar row %ld", (long)sidebarRow);
        XCTAssertGreaterThan(vc.label_information.stringValue.length, 0u);

        if (sidebarRow == FormulaeSideBarItemRepositories) {
            [listHost deselectAll];
            XCTAssertEqual(toolbar.currentMode, BPToolbarModeTap);
        }

        XCTAssertTrue([listHost selectPackageNamed:modes[i].sampleName cask:modes[i].isCask],
                      @"Expected package %@ in sidebar row %ld", modes[i].sampleName, (long)sidebarRow);
        if (sidebarRow == FormulaeSideBarItemRepositories) {
            BPFormula *selectedRepo = [vc selectedFormula];
            XCTAssertEqualObjects(selectedRepo.name, modes[i].sampleName);
        } else {
            XCTAssertEqualObjects(vc.currentFormula.name, modes[i].sampleName);
        }
        XCTAssertEqual(toolbar.currentMode, modes[i].expectedToolbarModeWhenSelected,
                       @"Unexpected toolbar mode for sidebar row %ld", (long)sidebarRow);
    }

    // 10th mode: Search across formulae and casks
    [[BPHomebrewManager sharedManager] setValue:nil forKey:@"searchFormulae"];
    [vc performSearchWithString:@"mock"];
    NSDate *searchDeadline = [NSDate dateWithTimeIntervalSinceNow:1.5];
    while ([BPHomebrewManager sharedManager].searchFormulae.count == 0 && searchDeadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    [(id<BPHomebrewManagerDelegate>)vc homebrewManager:[BPHomebrewManager sharedManager]
                               didUpdateSearchResults:[BPHomebrewManager sharedManager].searchFormulae];
    XCTAssertGreaterThan(listHost.rowCount, 0, @"Search mode must populate BPInstalledPackageListHost");
    XCTAssertTrue([listHost selectPackageNamed:@"mockwget" cask:NO]);
    XCTAssertEqualObjects(vc.currentFormula.name, @"mockwget");

    // Exercise Formula Info Popover from BPHomebrewViewController
    [vc showFormulaInfo:nil];
    BPFormulaPopoverViewController *popoverVC = [vc valueForKey:@"formulaPopoverViewController"];
    XCTAssertNotNil(popoverVC);
    XCTAssertEqualObjects(popoverVC.formula.name, @"mockwget");

    // Clear search and verify restoration of previous sidebar row
    [vc performSearchWithString:@""];
    XCTAssertFalse([vc isSearching]);
}

- (void)testEndToEndPinAndUnpinFormulaThroughHomebrewViewController
{
    NSWindow *window = nil;
    BPHomebrewViewController *vc = [self makeWiredHomebrewViewControllerInWindow:&window];
    BPInstalledPackageListHost *listHost = [vc valueForKey:@"installedPackageListHost"];

    [vc.sidebarController.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:FormulaeSideBarItemInstalled]
                              byExtendingSelection:NO];
    [(id<BPSideBarControllerDelegate>)vc sourceListSelectionDidChange];
    XCTAssertTrue([listHost selectPackageNamed:@"mockwget" cask:NO]);
    XCTAssertFalse(vc.currentFormulaPinned);

    [vc pinSelectedFormula:nil];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.20]];
    XCTAssertFalse(BPAppDelegateRef.isRunningBackgroundTask);

    XCTAssertTrue([listHost selectPackageNamed:@"mockgit" cask:NO]);
    XCTAssertTrue(vc.currentFormulaPinned);
    [vc unpinSelectedFormula:nil];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.20]];
    XCTAssertFalse(BPAppDelegateRef.isRunningBackgroundTask);
}

- (void)testEndToEndUnifiedUpdatesDashboardFilteringSelectionAndActions
{
    // Add an unpinned outdated formula alongside pinned mockgit and outdated cask mockchrome
    BPHomebrewManager *manager = [BPHomebrewManager sharedManager];
    BPFormula *outdatedGit = [BPFormula formulaWithName:@"mockgit" version:@"2.43.0" andLatestVersion:@"2.44.0"];
    BPFormula *outdatedNode = [BPFormula formulaWithName:@"mocknode" version:@"20.0.0" andLatestVersion:@"21.0.0"];
    BPFormula *outdatedChrome = [BPFormula formulaWithName:@"mockchrome" version:@"120.0" andLatestVersion:@"121.0"];
    outdatedChrome.cask = YES;
    [manager setValue:@[outdatedGit, outdatedNode] forKey:@"outdatedFormulae"];
    [manager setValue:@[outdatedChrome] forKey:@"outdatedCasks"];

    NSWindow *window = nil;
    BPHomebrewViewController *vc = [self makeWiredHomebrewViewControllerInWindow:&window];
    BPUnifiedUpdatesHost *updatesHost = [vc valueForKey:@"unifiedUpdatesHost"];
    BPToolbar *toolbar = [vc valueForKey:@"toolbar"];
    XCTAssertNotNil(updatesHost);
    XCTAssertNotNil(toolbar);

    [vc showUnifiedUpdates:nil];
    XCTAssertEqual(vc.sidebarController.sidebar.selectedRow, FormulaeSideBarItemUnifiedUpdates);
    XCTAssertFalse(updatesHost.isEmpty);
    XCTAssertTrue(updatesHost.hasEligibleUpdates);
    XCTAssertTrue(updatesHost.hasFormulaUpdates);
    XCTAssertTrue(updatesHost.hasCaskUpdates);
    XCTAssertEqual(updatesHost.rowCount, 3);

    // Select All Eligible skips pinned mockgit and selects mocknode + mockchrome
    [updatesHost selectAllEligible];
    XCTAssertEqual(updatesHost.selectedCount, 2);
    XCTAssertEqualObjects(updatesHost.selectedFormulaNames, @[@"mocknode"]);
    XCTAssertEqualObjects(updatesHost.selectedCaskNames, @[@"mockchrome"]);
    XCTAssertEqual(toolbar.currentMode, BPToolbarModeUpdateMany);

    // Group selection buttons
    [updatesHost selectFormulaGroup];
    XCTAssertEqualObjects(updatesHost.selectedFormulaNames, @[@"mocknode"]);
    XCTAssertEqual(updatesHost.selectedCaskNames.count, 0u);
    XCTAssertEqual(toolbar.currentMode, BPToolbarModeUpdateSingle);

    [updatesHost selectCaskGroup];
    XCTAssertEqual(updatesHost.selectedFormulaNames.count, 0u);
    XCTAssertEqualObjects(updatesHost.selectedCaskNames, @[@"mockchrome"]);
    XCTAssertEqual(toolbar.currentMode, BPToolbarModeUpdateSingle);

    // Filter query
    updatesHost.filterQuery = @"chrome";
    XCTAssertEqualObjects(updatesHost.filterQuery, @"chrome");
    updatesHost.filterQuery = @"";

    // Clear selection
    [updatesHost clearSelection];
    XCTAssertEqual(updatesHost.selectedCount, 0);
    XCTAssertEqual(toolbar.currentMode, BPToolbarModeDefault);
}

- (void)testEndToEndDoctorAndUpdateConsoleToolsRunStreamAndClear
{
    BPDoctorViewController *doctorVC = [[BPDoctorViewController alloc] initWithNibName:nil bundle:nil];
    __unused NSView *doctorView = doctorVC.view;
    BPConsoleToolHost *doctorHost = [doctorVC valueForKey:@"consoleHost"];
    BPAutoScrollTextView *doctorTextView = [doctorVC valueForKey:@"doctorTextView"];
    XCTAssertNotNil(doctorHost);
    XCTAssertNotNil(doctorTextView);

    doctorHost.onRun();
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    [doctorTextView flushPendingOutput];
    XCTAssertFalse(doctorHost.isRunning);
    XCTAssertTrue([doctorTextView.string containsString:@"MOCK_DOCTOR_OK"]);
    XCTAssertTrue([doctorTextView.string containsString:@"Checking for common problems..."]);
    XCTAssertTrue([doctorTextView.string containsString:@"MOCK_DOCTOR_DONE"]);

    doctorHost.onClear();
    XCTAssertEqualObjects(doctorTextView.string, @"");

    BPUpdateViewController *updateVC = [[BPUpdateViewController alloc] initWithNibName:nil bundle:nil];
    __unused NSView *updateView = updateVC.view;
    BPConsoleToolHost *updateHost = [updateVC valueForKey:@"consoleHost"];
    BPAutoScrollTextView *updateTextView = [updateVC valueForKey:@"updateTextView"];
    XCTAssertNotNil(updateHost);
    XCTAssertNotNil(updateTextView);

    updateHost.onRun();
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    [updateTextView flushPendingOutput];
    XCTAssertFalse(updateHost.isRunning);
    XCTAssertTrue([updateTextView.string containsString:@"MOCK_UPDATE_OK"]);

    updateHost.onClear();
    XCTAssertEqualObjects(updateTextView.string, @"");
}

- (void)testEndToEndServicesControllerStartStopRestartDetailsAndCopyOutput
{
    BPServicesViewController *servicesVC = [[BPServicesViewController alloc] initWithNibName:nil bundle:nil];
    __unused NSView *servicesView = servicesVC.view;
    BPServicesHost *servicesHost = [servicesVC valueForKey:@"servicesHost"];
    NSTableView *tableView = [servicesVC valueForKey:@"tableView"];
    NSTextView *detailsText = [servicesVC valueForKey:@"detailsText"];
    XCTAssertNotNil(servicesHost);
    XCTAssertNotNil(tableView);
    XCTAssertNotNil(detailsText);

    [servicesVC refreshServices];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.20]];
    XCTAssertEqual(tableView.numberOfRows, 2);

    // Select running service mockpostgres (row 0)
    [tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTableViewSelectionDidChangeNotification object:tableView];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.20]];

    XCTAssertTrue([detailsText.string containsString:@"mockpostgres"]);
    XCTAssertTrue([detailsText.string containsString:@"/cakebrew-mock-missing/service.plist"]);

    // Copy raw output to pasteboard
    [NSPasteboard.generalPasteboard clearContents];
    servicesHost.onCopyOutput();
    NSString *copied = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    XCTAssertTrue([copied containsString:@"\"name\":\"mockpostgres\""]);

    // Stop, Restart, and Start operations through SwiftUI host callbacks
    servicesHost.onStop();
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    XCTAssertFalse([[servicesVC valueForKey:@"operationInFlight"] boolValue]);

    [tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTableViewSelectionDidChangeNotification object:tableView];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];

    servicesHost.onRestart();
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    XCTAssertFalse([[servicesVC valueForKey:@"operationInFlight"] boolValue]);

    // Select stopped service mockredis (row 1) and start it
    [tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTableViewSelectionDidChangeNotification object:tableView];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];

    servicesHost.onStart();
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    XCTAssertFalse([[servicesVC valueForKey:@"operationInFlight"] boolValue]);
}

- (void)runSingleInstallationOperation:(BPWindowOperation)op
                              formulae:(NSArray<BPFormula *> *)formulae
                               options:(NSArray<NSString *> *)options
                                   zap:(BOOL)zap
                        expectedMarker:(NSString *)expectedMarker
{
    BPInstallationWindowController *wc = [[BPInstallationWindowController alloc] initWithWindowNibName:@"BPInstallationWindow"];
    wc.windowOperation = op;
    wc.formulae = formulae;
    wc.options = options;
    wc.zapCask = zap;

    __unused NSWindow *win = wc.window;
    [wc windowDidLoad];
    BPInstallationHost *installHost = [wc valueForKey:@"installationHost"];
    BPAutoScrollTextView *recordTextView = [wc valueForKey:@"recordTextView"];
    XCTAssertNotNil(installHost);
    XCTAssertNotNil(recordTextView);

    __block BOOL completedFlag = NO;
    [wc setCompletionBlock:^(BOOL completed) {
        completedFlag = completed;
    }];
    [wc executeInstallation];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while ([[wc valueForKey:@"isRunningTask"] boolValue] && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    XCTAssertFalse([[wc valueForKey:@"isRunningTask"] boolValue], @"Installation task must finish");
    [recordTextView flushPendingOutput];
    [wc cleanupAfterTask];
    XCTAssertTrue(completedFlag, @"Operation %@ should report completion=YES", expectedMarker);
    XCTAssertTrue([recordTextView.string containsString:expectedMarker],
                  @"Expected '%@' in transcript, got: %@", expectedMarker, recordTextView.string);
}

- (void)testEndToEndInstallationWindowControllerAllOperations
{
    BPFormula *firefoxCask = [BPFormula formulaWithName:@"mockfirefox"];
    firefoxCask.cask = YES;
    BPFormula *chromeCask = [BPFormula formulaWithName:@"mockchrome"];
    chromeCask.cask = YES;

    [self runSingleInstallationOperation:kBPWindowOperationInstall
                                formulae:@[[BPFormula formulaWithName:@"mockhtop"]]
                                 options:@[@"--with-debug"]
                                     zap:NO
                          expectedMarker:@"MOCK_INSTALL_OK"];

    [self runSingleInstallationOperation:kBPWindowOperationInstall
                                formulae:@[firefoxCask]
                                 options:nil
                                     zap:NO
                          expectedMarker:@"MOCK_INSTALL_CASK_OK"];

    [self runSingleInstallationOperation:kBPWindowOperationUninstall
                                formulae:@[[BPFormula formulaWithName:@"mockwget"]]
                                 options:nil
                                     zap:NO
                          expectedMarker:@"MOCK_UNINSTALL_OK"];

    [self runSingleInstallationOperation:kBPWindowOperationUninstall
                                formulae:@[chromeCask]
                                 options:nil
                                     zap:NO
                          expectedMarker:@"MOCK_UNINSTALL_CASK_OK"];

    [self runSingleInstallationOperation:kBPWindowOperationUninstall
                                formulae:@[chromeCask]
                                 options:nil
                                     zap:YES
                          expectedMarker:@"MOCK_UNINSTALL_CASK_ZAP_OK"];

    [self runSingleInstallationOperation:kBPWindowOperationUpgrade
                                formulae:@[[BPFormula formulaWithName:@"mockgit"]]
                                 options:nil
                                     zap:NO
                          expectedMarker:@"MOCK_UPGRADE_OK"];

    [self runSingleInstallationOperation:kBPWindowOperationTap
                                formulae:@[[BPFormula formulaWithName:@"homebrew/cask-fonts"]]
                                 options:nil
                                     zap:NO
                          expectedMarker:@"MOCK_TAP_OK"];

    [self runSingleInstallationOperation:kBPWindowOperationUntap
                                formulae:@[[BPFormula formulaWithName:@"homebrew/core"]]
                                 options:nil
                                     zap:NO
                          expectedMarker:@"MOCK_UNTAP_OK"];

    [self runSingleInstallationOperation:kBPWindowOperationCleanup
                                formulae:nil
                                 options:nil
                                     zap:NO
                          expectedMarker:@"MOCK_CLEANUP_OK"];
}

- (void)testEndToEndFormulaOptionsWindowControllerLoadsOptionsTogglesAndReturnsSelection
{
    BPFormula *formula = [BPFormula formulaWithName:@"mockwget"];
    [formula setNeedsInformation:YES];
    NSArray *options = [formula options];
    XCTAssertEqual(options.count, 2u, @"Mock formula info must parse --with-debug and --HEAD options");

    BPFormulaOptionsWindowController *wc = [[BPFormulaOptionsWindowController alloc] initWithWindowNibName:@"BPFormulaOptionsWindow"];
    wc.formula = formula;
    NSMutableArray *availableOptions = [NSMutableArray array];
    for (BPFormulaOption *option in options) {
        [availableOptions addObject:[@{
            @"formulaOptionCommand": option.name,
            @"isFormulaOptionCommandApplied": @NO,
            @"formulaOptionDescription": option.explanation ?: @""
        } mutableCopy]];
    }
    wc.availableOptions = availableOptions;
    __unused NSWindow *window = wc.window;

    XCTAssertNotNil(wc.optionsHost);
    XCTAssertEqual(wc.allSelectedOptions.count, 0u);

    [wc.optionsHost setApplied:YES forOptionNamed:@"--with-debug"];
    [wc.optionsHost setApplied:YES forOptionNamed:@"--HEAD"];
    XCTAssertEqualObjects(wc.allSelectedOptions, (@[@"--with-debug", @"--HEAD"]));

    [wc.optionsHost setApplied:NO forOptionNamed:@"--HEAD"];
    XCTAssertEqualObjects(wc.allSelectedOptions, @[@"--with-debug"]);
}

- (void)testEndToEndAutoremoveWindowControllerPreviewAndReviewedRemoval
{
    NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    BPAutoremoveWindowController *controller = [BPAutoremoveWindowController presentForWindow:parent
                                                                                    interface:self.mockInterface
                                                                                      manager:[BPHomebrewManager sharedManager]];
    XCTAssertNotNil(controller);
    BPAutoremoveHost *host = [controller valueForKey:@"autoremoveHost"];
    BPAutoScrollTextView *outputView = [controller valueForKey:@"outputView"];
    NSTextField *statusLabel = [controller valueForKey:@"statusLabel"];
    NSButton *removeButton = [controller valueForKey:@"removeButton"];
    XCTAssertNotNil(host);

    // Wait for previewAutoremoveWithProgress: to complete
    NSDate *previewDeadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while ([[controller valueForKey:@"busy"] boolValue] && previewDeadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    XCTAssertTrue(removeButton.enabled);
    XCTAssertTrue([outputView.string containsString:@"mockunused"]);

    // Trigger reviewed removal via SwiftUI host callback
    host.onRemove();
    NSDate *removeDeadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while ([[controller valueForKey:@"busy"] boolValue] && removeDeadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    [outputView flushPendingOutput];
    XCTAssertTrue([outputView.string containsString:@"MOCK_AUTOREMOVE_OK"]);
    XCTAssertTrue([statusLabel.stringValue containsString:@"removed"]);

    // Close the sheet
    host.onCancelOrClose();
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.10]];
    XCTAssertFalse(BPAppDelegateRef.isRunningBackgroundTask);
}

- (void)testEndToEndBundleWindowControllerImportAndExportFlows
{
    NSURL *tempDir = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:tempDir withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSURL *brewfileURL = [tempDir URLByAppendingPathComponent:@"Brewfile"];
    NSString *brewfileContents = @"brew \"mockwget\"\ncask \"mockchrome\"\ntap \"homebrew/core\"\n";
    XCTAssertTrue([brewfileContents writeToURL:brewfileURL atomically:YES encoding:NSUTF8StringEncoding error:NULL]);

    NSError *planError = nil;
    BPBrewfilePlan *plan = [BPBrewfilePlan planWithURL:brewfileURL
                                           inventories:@{
                                               @"brew": @[@"mockwget"],
                                               @"cask": @[],
                                               @"tap": @[@"homebrew/core"]
                                           }
                                                 error:&planError];
    XCTAssertNil(planError);
    XCTAssertNotNil(plan);
    XCTAssertTrue(plan.canInstall);

    // 1. Run Brewfile Import flow
    BPBundleWindowController *importWC = [[BPBundleWindowController alloc] initWithWindowNibName:@"BPBundleWindow"];
    __unused NSWindow *importWindow = importWC.window;
    [importWC windowDidLoad];
    [importWC performSelector:@selector(runImportOperationWithPlan:) withObject:plan];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.35]];

    BPAutoScrollTextView *importTextView = [importWC valueForKey:@"textViewImport"];
    [importTextView flushPendingOutput];
    XCTAssertTrue([importTextView.string containsString:@"MOCK_IMPORT_OK"],
                  @"Expected MOCK_IMPORT_OK in import output, got: %@", importTextView.string);

    // 2. Run Brewfile Export flow
    NSURL *exportURL = [tempDir URLByAppendingPathComponent:@"ExportedBrewfile"];
    BPBundleWindowController *exportWC = [[BPBundleWindowController alloc] initWithWindowNibName:@"BPBundleWindow"];
    __unused NSWindow *exportWindow = exportWC.window;
    [exportWC windowDidLoad];
    [exportWC performSelector:@selector(runExportOperationWithFile:) withObject:exportURL];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.35]];

    NSButton *exportCloseButton = [exportWC valueForKey:@"buttonClose"];
    BPBundleOperationHost *exportHost = [exportWC valueForKey:@"bundleHost"];
    XCTAssertTrue(exportCloseButton.enabled);
    XCTAssertNotNil(exportHost);
    XCTAssertFalse([[exportWC valueForKey:@"exportOperation"] isRunning]);

    [[NSFileManager defaultManager] removeItemAtURL:tempDir error:NULL];
}

- (void)testEndToEndOverlaysDisabledLoadingEmptyStateAndPreferencesHost
{
    // 1. BPDisabledView + BPDisabledHost
    BPDisabledView *disabledView = [[BPDisabledView alloc] initWithFrame:NSMakeRect(0, 0, 500, 360)];
    __block NSInteger retryCount = 0;
    disabledView.retryHandler = ^{
        retryCount++;
    };
    [disabledView showDiscoveryResult:BPHomebrewDiscoveryMissing checking:YES];
    [disabledView showDiscoveryResult:BPHomebrewDiscoveryMissing checking:NO];
    [disabledView showDiscoveryResult:BPHomebrewDiscoveryInvalidShell checking:NO];
    [disabledView showDiscoveryResult:BPHomebrewDiscoveryCheckFailed checking:NO];
    BPDisabledHost *disabledHost = [disabledView valueForKey:@"disabledHost"];
    XCTAssertNotNil(disabledHost);
    disabledHost.onRetry();
    XCTAssertEqual(retryCount, 1);

    // 2. BPLoadingView + BPLoadingHost
    BPLoadingView *loadingView = [[BPLoadingView alloc] initWithFrame:NSMakeRect(0, 0, 500, 360)];
    BPLoadingHost *loadingHost = [loadingView valueForKey:@"loadingHost"];
    XCTAssertNotNil(loadingHost);
    XCTAssertNotNil(loadingHost.viewController.view);

    // 3. BPEmptyStateView + BPEmptyStateHost
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 360)];
    BPEmptyState *emptyState = [BPEmptyState stateForSidebarRow:FormulaeSideBarItemOutdated searching:NO];
    [BPEmptyStateView presentState:emptyState overView:container];
    XCTAssertEqual(container.subviews.count, 1u);
    [BPEmptyStateView presentState:nil overView:container];
    XCTAssertEqual(container.subviews.count, 0u);

    // 4. BPPreferencesWindowController + BPPreferencesHost
    BPPreferencesWindowController *prefsWC = [[BPPreferencesWindowController alloc] init];
    BPPreferencesHost *prefsHost = [prefsWC valueForKey:@"preferencesHost"];
    XCTAssertNotNil(prefsHost);
    prefsHost.onBackgroundCheckChanged(NO);
    XCTAssertFalse([BPPreferences backgroundCheckEnabled]);
    prefsHost.onIntervalChanged(86400.0);
    XCTAssertEqualWithAccuracy([BPPreferences backgroundCheckInterval], 86400.0, 0.1);
    prefsHost.onGreedyChanged(YES);
    XCTAssertTrue([BPPreferences greedyCaskUpgrades]);
    prefsHost.onAutomaticAppUpdateCheckChanged(NO);
    XCTAssertFalse([BPPreferences automaticAppUpdateCheckEnabled]);

    // 5. BPAppUpdateHost
    BPAppUpdateHost *updateHost = [[BPAppUpdateHost alloc] initWithCurrentVersion:@"2.0.0" automaticCheckEnabled:YES];
    XCTAssertNotNil(updateHost);
    XCTAssertNotNil(updateHost.window);
    XCTAssertEqualObjects(updateHost.currentVersionString, @"2.0.0");
    uint64_t gen = [updateHost beginCheckWithCurrentVersion:@"2.0.0"];
    XCTAssertTrue(updateHost.isChecking);
    XCTAssertTrue([updateHost receiveFeedUnavailableForGeneration:gen]);
    XCTAssertFalse(updateHost.isChecking);
    XCTAssertFalse(updateHost.isUpdateAvailable);
}

- (void)testEndToEndAboutWindowBrewfileReviewCommandPaletteAndMenuBarExtra
{
    // 1. SwiftUI Tahoe About Window (DCOAboutWindowController + BPAboutWindowHost)
    DCOAboutWindowController *aboutWC = [[DCOAboutWindowController alloc] init];
    aboutWC.appName = @"Cakebrew";
    aboutWC.appVersion = @"Version 2.0 (Build 200)";
    aboutWC.appCopyright = @"Copyright © Cakebrew Contributors";
    aboutWC.appCredits = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Credits: Bruno Philipe & Contributors", nil)];
    [aboutWC setValue:[[NSAttributedString alloc] initWithString:NSLocalizedString(@"Acknowledgements: Sparkle & DCOAboutWindow", nil)]
               forKey:@"appAcknowledgements"];
    __unused NSWindow *aboutWin = aboutWC.window;
    [aboutWC windowDidLoad];

    XCTAssertNotNil(aboutWC.aboutHost);
    XCTAssertNotNil(aboutWC.creditsTextView);
    XCTAssertEqual(aboutWC.aboutHost.selectedTabIndex, 0);
    XCTAssertTrue([aboutWC.creditsTextView.string containsString:@"Bruno Philipe"]);

    [aboutWC showAcknowledgements:nil];
    XCTAssertEqual(aboutWC.aboutHost.selectedTabIndex, 1);
    XCTAssertTrue([aboutWC.creditsTextView.string containsString:@"Acknowledgements"]);

    [aboutWC.aboutHost selectTabAtIndex:0];
    XCTAssertEqual(aboutWC.aboutHost.selectedTabIndex, 0);
    XCTAssertTrue([aboutWC.creditsTextView.string containsString:@"Credits:"]);

    NSString *copiedVersion = [aboutWC.aboutHost copyVersionInfoToPasteboard];
    XCTAssertEqualObjects(copiedVersion, @"Cakebrew (Version 2.0 (Build 200))");
    XCTAssertEqualObjects([NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString], copiedVersion);

    // 2. SwiftUI Brewfile Review Host (BPBundleWindowController + BPBrewfileReviewHost)
    NSURL *tempDir = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:tempDir withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSURL *brewfileURL = [tempDir URLByAppendingPathComponent:@"Brewfile"];
    NSString *brewfileContents = @"brew \"mockwget\"\ncask \"mockchrome\"\ntap \"homebrew/core\"\n";
    XCTAssertTrue([brewfileContents writeToURL:brewfileURL atomically:YES encoding:NSUTF8StringEncoding error:NULL]);

    NSError *planError = nil;
    BPBrewfilePlan *plan = [BPBrewfilePlan planWithURL:brewfileURL
                                           inventories:@{
                                               @"brew": @[@"mockwget"],
                                               @"cask": @[],
                                               @"tap": @[@"homebrew/core"]
                                           }
                                                 error:&planError];
    XCTAssertNil(planError);
    NSTextView *reviewEntriesView = nil;
    BPBrewfileReviewHost *reviewHost = [BPBundleWindowController reviewHostForPlan:plan
                                                                          fileName:@"Brewfile"
                                                                             error:nil
                                                                   entriesTextView:&reviewEntriesView];
    XCTAssertNotNil(reviewHost);
    XCTAssertNotNil(reviewEntriesView);
    XCTAssertEqualObjects(reviewEntriesView.accessibilityIdentifier, @"brewfile.review.entries");
    XCTAssertEqual(reviewHost.totalEntryCount, 3);
    XCTAssertEqual(reviewHost.installedCount, 2);
    XCTAssertEqual(reviewHost.missingCount, 1);
    XCTAssertTrue(reviewHost.canInstall);
    XCTAssertTrue([reviewEntriesView.string containsString:@"mockwget"]);
    [[NSFileManager defaultManager] removeItemAtURL:tempDir error:NULL];

    // 3. Command Palette (⌘K) + Unified Window Subtitle Synchronization
    NSWindow *mainWindow = nil;
    BPHomebrewViewController *vc = [self makeWiredHomebrewViewControllerInWindow:&mainWindow];
    XCTAssertEqualObjects(mainWindow.subtitle, vc.label_information.stringValue);
    XCTAssertGreaterThan(mainWindow.subtitle.length, 0u);

    [vc showCommandPalette:nil];
    BPCommandPaletteHost *palette = vc.commandPaletteHost;
    XCTAssertNotNil(palette);
    XCTAssertGreaterThanOrEqual(palette.filteredCount, 19);

    palette.query = @"Doctor";
    XCTAssertGreaterThanOrEqual(palette.filteredCount, 1);
    XCTAssertEqualObjects(palette.selectedItemID, @"nav.doctor");
    XCTAssertTrue([palette executeSelectedItem]);
    XCTAssertEqual(vc.sidebarController.sidebar.selectedRow, (NSInteger)FormulaeSideBarItemDoctor);
    XCTAssertEqualObjects(mainWindow.subtitle, vc.label_information.stringValue);

    // Select a package via Command Palette
    [vc showCommandPalette:nil];
    palette.query = @"mockwget";
    XCTAssertGreaterThanOrEqual(palette.filteredCount, 1);
    XCTAssertTrue([palette executeItemWithID:@"pkg:formula:mockwget"]);
    XCTAssertEqual(vc.sidebarController.sidebar.selectedRow, (NSInteger)FormulaeSideBarItemInstalled);
    XCTAssertEqualObjects([vc selectedFormula].name, @"mockwget");

    // 4. Optional Menu Bar Extra in Settings & BPAppDelegate
    BPAppDelegate *appDelegate = [[BPAppDelegate alloc] init];
    XCTAssertNil(appDelegate.statusItem);

    [BPPreferences setShowMenuBarExtra:YES];
    [appDelegate updateMenuBarExtra];
    XCTAssertNotNil(appDelegate.statusItem);
    XCTAssertNotNil(appDelegate.statusItem.menu);
    XCTAssertGreaterThanOrEqual(appDelegate.statusItem.menu.numberOfItems, 5);

    [BPPreferences setShowMenuBarExtra:NO];
    [appDelegate updateMenuBarExtra];
    XCTAssertNil(appDelegate.statusItem);
}

- (void)testEndToEndStatusBarHostPopoverCopyAndUnifiedWindowStyling
{
    // 1. SwiftUI Tahoe Status Bar Host (BPStatusBarHost + BPHomebrewViewController)
    NSWindow *mainWindow = nil;
    BPHomebrewViewController *vc = [self makeWiredHomebrewViewControllerInWindow:&mainWindow];
    XCTAssertNotNil(vc.statusBarHost);
    XCTAssertEqualObjects(vc.statusBarHost.message, vc.label_information.stringValue);
    XCTAssertGreaterThan(vc.statusBarHost.installedCount, 0);
    XCTAssertGreaterThan(vc.statusBarHost.outdatedCount, 0);

    [[NSNotificationCenter defaultCenter] postNotificationName:kDidBeginBackgroundActivityNotification object:nil];
    XCTAssertTrue(vc.statusBarHost.isBusy);
    [[NSNotificationCenter defaultCenter] postNotificationName:kDidEndBackgroundActivityNotification object:nil];
    XCTAssertFalse(vc.statusBarHost.isBusy);

    [vc.statusBarHost triggerUnifiedUpdates];
    XCTAssertEqual(vc.sidebarController.sidebar.selectedRow, (NSInteger)FormulaeSideBarItemUnifiedUpdates);
    XCTAssertEqualObjects(vc.statusBarHost.message, vc.label_information.stringValue);

    [vc.statusBarHost triggerCommandPalette];
    XCTAssertNotNil(vc.commandPaletteHost);
    [vc dismissCommandPalette:nil];

    // 2. Nibless BPFormulaPopoverViewController + BPFormulaInformationHost copyInformationToPasteboard
    BPFormulaPopoverViewController *popoverVC = [[BPFormulaPopoverViewController alloc] init];
    XCTAssertNotNil(popoverVC.view);
    XCTAssertNotNil(popoverVC.formulaPopover);

    BPFormulaInformationHost *infoHost = [[BPFormulaInformationHost alloc] init];
    uint64_t gen = [infoHost beginWithName:@"mockwget" cask:NO infoType:kBPFormulaInfoTypeGeneral];
    [infoHost receiveInformation:@"mockwget: Internet file retriever"
                         website:[NSURL URLWithString:@"https://www.gnu.org/software/wget/"]
                            name:@"mockwget"
                            cask:NO
                        infoType:kBPFormulaInfoTypeGeneral
                      generation:gen];
    NSString *copied = [infoHost copyInformationToPasteboard];
    XCTAssertEqualObjects(copied, @"mockwget: Internet file retriever");
    XCTAssertEqualObjects([NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString], copied);

    // 3. BPMainWindowController unified toolbar style & sidebar thickness bounds + BPStyle Tahoe defaults
    BPMainWindowController *mainWC = [[BPMainWindowController alloc] initWithWindow:mainWindow];
    NSScrollView *sidebarScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
    NSView *contentContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
    mainWC.sidebarView = sidebarScroll;
    mainWC.windowContentView = contentContainer;
    [mainWC setUpViews];
    XCTAssertEqual(mainWindow.toolbarStyle, NSWindowToolbarStyleUnified);
    NSSplitViewItem *sidebarItem = mainWC.splitViewController.splitViewItems.firstObject;
    XCTAssertEqualWithAccuracy(sidebarItem.minimumThickness, 190.0, 0.1);
    XCTAssertEqualWithAccuracy(sidebarItem.maximumThickness, 280.0, 0.1);
    XCTAssertEqual([BPStyle toolbarSize], NSToolbarSizeModeDefault);
    XCTAssertNotNil([BPStyle defaultFixedWidthFont]);
}

- (void)testEndToEndSidebarHostInteractiveInspectorAndOperationAccessoryCards
{
    // 1. BPSideBarController + BPSidebarHost synchronization + programmatic cell fallback
    NSWindow *mainWindow = nil;
    BPHomebrewViewController *vc = [self makeWiredHomebrewViewControllerInWindow:&mainWindow];
    BPSideBarController *sidebarController = vc.sidebarController;
    XCTAssertNotNil(sidebarController.sidebarHost);
    XCTAssertEqual(sidebarController.sidebarHost.sectionCount, 3);
    XCTAssertEqual(sidebarController.sidebarHost.selectableRowCount, 13);
    XCTAssertGreaterThan([sidebarController.sidebarHost badgeCountForRowIndex:FormulaeSideBarItemInstalled], 0);

    [sidebarController.sidebarHost selectRowAtIndex:FormulaeSideBarItemPinned];
    XCTAssertEqual(sidebarController.sidebarHost.selectedRowIndex, (NSInteger)FormulaeSideBarItemPinned);
    XCTAssertEqual(sidebarController.sidebar.selectedRow, (NSInteger)FormulaeSideBarItemPinned);

    // Programmatic cell builder fallback when NSOutlineView has no XIB cell templates
    NSOutlineView *plainOutline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"Main"];
    [plainOutline addTableColumn:col];
    plainOutline.outlineTableColumn = col;
    id groupItem = [sidebarController outlineView:plainOutline child:0 ofItem:nil];
    NSView *headerCell = [sidebarController outlineView:plainOutline viewForTableColumn:col item:groupItem];
    XCTAssertTrue([headerCell isKindOfClass:BPSidebarTableCellView.class]);
    id rowItem = [sidebarController outlineView:plainOutline child:0 ofItem:groupItem];
    BPSidebarTableCellView *mainCell = (BPSidebarTableCellView *)[sidebarController outlineView:plainOutline
                                                                             viewForTableColumn:col
                                                                                           item:rowItem];
    XCTAssertTrue([mainCell isKindOfClass:BPSidebarTableCellView.class]);
    XCTAssertEqualObjects(mainCell.textField.accessibilityIdentifier, @"sidebar.formulae.installed");
    XCTAssertNotNil(mainCell.badgeView);

    // 2. Interactive Package Inspector (BPSelectedFormulaViewController + BPSelectedFormulaHost + BPHomebrewViewController)
    [sidebarController.sidebarHost selectRowAtIndex:FormulaeSideBarItemInstalled];
    BPSelectedFormulaViewController *selectedVC = [vc valueForKey:@"selectedFormulaeViewController"];
    XCTAssertNotNil(selectedVC);
    XCTAssertNotNil(selectedVC.inspectorHost);

    BPFormula *wget = [BPFormula formulaWithName:@"mockwget" version:@"1.21" andLatestVersion:@"1.21"];
    [wget setValue:@"/tmp (10 files, 1MB)" forKey:@"installPath"];
    [wget setValue:@"mockgit, openssl" forKey:@"dependencies"];
    selectedVC.formulae = @[wget];

    NSString *copiedPath = [selectedVC.inspectorHost copyInstallPathToPasteboard];
    XCTAssertEqualObjects(copiedPath, @"/tmp (10 files, 1MB)");
    XCTAssertEqualObjects([NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString], copiedPath);

    [selectedVC.inspectorHost selectRelatedPackageNamed:@"mockgit"];
    XCTAssertEqual(vc.sidebarController.sidebar.selectedRow, (NSInteger)FormulaeSideBarItemInstalled);
    XCTAssertEqualObjects([vc selectedFormula].name, @"mockgit");

    // 3. SwiftUI Operation Accessory Cards (BPTapInputHost & BPCleanupPreviewHost)
    NSTextField *tapField = nil;
    NSAlert *tapAlert = [BPPackageOperationPresenter tapInputAlertWithInputField:&tapField];
    BPTapInputHost *tapHost = [BPPackageOperationPresenter tapInputHostForAlert:tapAlert];
    XCTAssertNotNil(tapHost);
    XCTAssertEqual(tapHost.inputField, tapField);
    XCTAssertFalse(tapHost.isValidFormat);
    tapHost.repositoryName = @"scottdensmore/cakebrew";
    XCTAssertTrue(tapHost.isValidFormat);
    XCTAssertEqualObjects(tapField.stringValue, @"scottdensmore/cakebrew");

    BPCleanupPreview *cleanupPreview = [BPCleanupPreview previewFromOutput:
        @"Would remove: /Users/x/Library/Caches/Homebrew/wget--1.21.3.tar.gz (1.5MB)\n"
        @"==> This operation would free approximately 49.2MB of disk space.\n"];
    NSAlert *cleanupAlert = [BPPackageOperationPresenter cleanupAlertForPreview:cleanupPreview];
    BPCleanupPreviewHost *cleanupHost = [BPPackageOperationPresenter cleanupPreviewHostForAlert:cleanupAlert];
    XCTAssertNotNil(cleanupHost);
    XCTAssertEqual(cleanupHost.itemCount, 1);
    XCTAssertGreaterThan(cleanupHost.reclaimableBytes, 0ull);
    XCTAssertGreaterThan(cleanupHost.formattedByteCount.length, 0u);
}

@end
