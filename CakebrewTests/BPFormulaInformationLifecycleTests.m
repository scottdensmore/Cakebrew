#import <XCTest/XCTest.h>
#import "BPFormulaPopoverViewController.h"
#import "BPSelectedFormulaViewController.h"
#import "BPFormulaInformation-Swift.h"

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
