#import <XCTest/XCTest.h>
#import "BPFormulaPopoverViewController.h"
#import "BPSelectedFormulaViewController.h"

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

@end
