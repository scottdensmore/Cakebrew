#import <XCTest/XCTest.h>
#import "BPFormulaPopoverViewController.h"

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
@property (copy) NSString *information;
@property uint64_t generation;
@property BOOL open;
@end
@implementation BPInformationTestHost
- (uint64_t)beginWithName:(NSString *)name cask:(BOOL)cask
{
    self.name = name;
    self.information = nil;
    self.open = YES;
    return ++_generation;
}
- (void)receiveInformation:(NSString *)information website:(NSURL *)website name:(NSString *)name
                     cask:(BOOL)cask generation:(uint64_t)generation
{
    if (self.open && generation == self.generation) self.information = information;
}
- (void)close
{
    self.open = NO;
    self.name = nil;
    self.information = nil;
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

@end
