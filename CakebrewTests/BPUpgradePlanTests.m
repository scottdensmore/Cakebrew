#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "BPUpgradePlan.h"
#import "BPHomebrewInterface.h"

@interface BPHomebrewInterface (UpgradeTesting)
- (BOOL)performAsyncBrewCommandWithArguments:(NSArray *)arguments
                   wrapsSynchronousRequest:(BOOL)synchronous
                                  progress:(NSProgress *)progress
                           dataReturnBlock:(void (^)(NSString *))output;
- (void)sendDelegateFormulaeUpdatedCallForCommand:(NSString *)command;
@end

/// Exercises the real selected-upgrade adapter without processes, preferences,
/// the shared interface, or a manager reload.
@interface BPUpgradeInterfaceRecorder : BPHomebrewInterface
@property (strong) NSMutableArray<NSArray<NSString *> *> *commands;
@property (strong) NSProgress *seenProgress;
@property NSUInteger reloads;
@property BOOL failFirst;
@property BOOL cancelFirst;
@end

@implementation BPUpgradeInterfaceRecorder
- (BOOL)performAsyncBrewCommandWithArguments:(NSArray *)arguments
                   wrapsSynchronousRequest:(BOOL)synchronous
                                  progress:(NSProgress *)progress
                           dataReturnBlock:(void (^)(NSString *))output
{
    XCTAssertFalse(synchronous);
    XCTAssertEqual(self.reloads, 0u, @"Reload must wait until every attempted batch exits");
    self.seenProgress = progress;
    [self.commands addObject:arguments];
    if (output) output(@"batch output\n");
    if (self.cancelFirst) [progress cancel];
    return !self.failFirst;
}
- (void)sendDelegateFormulaeUpdatedCallForCommand:(NSString *)command
{
    XCTAssertEqualObjects(command, @"upgrade");
    self.reloads++;
}
@end

@interface BPUpgradePlanTests : XCTestCase
@end

@implementation BPUpgradePlanTests
- (BPFormula *)formula:(NSString *)name cask:(BOOL)cask
{
    BPFormula *formula = [BPFormula formulaWithName:name];
    formula.cask = cask;
    return formula;
}
- (NSArray<BPFormula *> *)mixedSelection
{
    return @[[self formula:@"shared" cask:YES], [self formula:@"shared" cask:NO],
             [self formula:@"tap/repo/other" cask:NO], [self formula:@"browser" cask:YES]];
}
- (NSArray<NSArray<NSString *> *> *)commandsForSelection:(NSArray<BPFormula *> *)selection
{
    NSMutableArray *commands = [NSMutableArray array];
    BPUpgradePlan *plan = [[BPUpgradePlan alloc] initWithSelection:selection];
    [plan executeWithProgress:[NSProgress progressWithTotalUnitCount:1] runner:^BOOL(NSArray *arguments) {
        [commands addObject:arguments];
        return YES;
    }];
    return commands;
}
- (void)testFormulaSelectionUsesExplicitNamespaceAndPreservesNamesAndOrder
{
    XCTAssertEqualObjects(([self commandsForSelection:@[[self formula:@"wget" cask:NO],
                                                      [self formula:@"tap/repo/git" cask:NO]]]),
                          (@[@[@"upgrade", @"--formula", @"wget", @"tap/repo/git"]]));
}
- (void)testCaskSelectionUsesExplicitNamespace
{
    XCTAssertEqualObjects([self commandsForSelection:@[[self formula:@"browser" cask:YES]]],
                          (@[@[@"upgrade", @"--cask", @"browser"]]));
}
- (void)testMixedSelectionKeepsSameNameInBothNamespacesAndRunsSeparateBatches
{
    XCTAssertEqualObjects([self commandsForSelection:[self mixedSelection]],
                          (@[@[@"upgrade", @"--formula", @"shared", @"tap/repo/other"],
                             @[@"upgrade", @"--cask", @"shared", @"browser"]]));
}
- (void)testEmptySelectionDoesNotRunUpgradeAllOrReportWorkSucceeded
{
    BPUpgradePlan *plan = [[BPUpgradePlan alloc] initWithSelection:@[]];
    XCTAssertFalse([plan executeWithProgress:[NSProgress progressWithTotalUnitCount:1] runner:^BOOL(NSArray *arguments) {
        XCTFail(@"An empty selection must never become bare brew upgrade");
        return YES;
    }]);
}
- (void)testInvalidNameRejectsEntireSelectionBeforeAnyBatchCanUpgradeAll
{
    for (NSString *name in @[@"", @" \n\t"]) {
        XCTAssertEqual(([self commandsForSelection:@[[self formula:@"wget" cask:NO],
                                                    [self formula:name cask:YES]]].count), 0u);
    }
}
- (void)testPlanSnapshotsSelectionAndNamespaceBeforeExecution
{
    BPFormula *formula = [self formula:@"wget" cask:NO];
    NSMutableArray *selection = [NSMutableArray arrayWithObject:formula];
    BPUpgradePlan *plan = [[BPUpgradePlan alloc] initWithSelection:selection];
    formula.cask = YES;
    [selection removeAllObjects];
    __block NSUInteger calls = 0;
    XCTAssertTrue([plan executeWithProgress:[NSProgress progressWithTotalUnitCount:1] runner:^BOOL(NSArray *arguments) {
        calls++;
        XCTAssertEqualObjects(arguments, (@[@"upgrade", @"--formula", @"wget"]));
        return YES;
    }]);
    XCTAssertEqual(calls, 1u);
}
- (void)testBothSuccessfulBatchesReportSuccess
{
    BPUpgradePlan *plan = [[BPUpgradePlan alloc] initWithSelection:[self mixedSelection]];
    __block NSUInteger calls = 0;
    XCTAssertTrue([plan executeWithProgress:[NSProgress progressWithTotalUnitCount:1] runner:^BOOL(NSArray *arguments) {
        calls++;
        return YES;
    }]);
    XCTAssertEqual(calls, 2u);
}
- (void)testFirstFailureStopsBeforeLaterBatchAndCannotBecomeSuccess
{
    BPUpgradePlan *plan = [[BPUpgradePlan alloc] initWithSelection:[self mixedSelection]];
    __block NSUInteger calls = 0;
    XCTAssertFalse([plan executeWithProgress:[NSProgress progressWithTotalUnitCount:1] runner:^BOOL(NSArray *arguments) {
        calls++;
        return calls > 1;
    }]);
    XCTAssertEqual(calls, 1u);
}
- (void)testLaterFailureMakesAggregateFail
{
    BPUpgradePlan *plan = [[BPUpgradePlan alloc] initWithSelection:[self mixedSelection]];
    __block NSUInteger calls = 0;
    XCTAssertFalse([plan executeWithProgress:[NSProgress progressWithTotalUnitCount:1] runner:^BOOL(NSArray *arguments) {
        return ++calls == 1;
    }]);
    XCTAssertEqual(calls, 2u);
}
- (void)testCancellationBeforeExecutionRunsNothing
{
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
    [progress cancel];
    BPUpgradePlan *plan = [[BPUpgradePlan alloc] initWithSelection:[self mixedSelection]];
    XCTAssertFalse([plan executeWithProgress:progress runner:^BOOL(NSArray *arguments) {
        XCTFail(@"Cancelled plan must not start a batch");
        return YES;
    }]);
}
- (void)testCancellationBetweenBatchesIsStickyEvenIfCommandReturnsSuccess
{
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
    BPUpgradePlan *plan = [[BPUpgradePlan alloc] initWithSelection:[self mixedSelection]];
    __block NSUInteger calls = 0;
    XCTAssertFalse([plan executeWithProgress:progress runner:^BOOL(NSArray *arguments) {
        calls++;
        [progress cancel];
        return YES;
    }]);
    XCTAssertEqual(calls, 1u);
}
- (void)testCancellationDuringFinalBatchCannotReportSuccess
{
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
    BPUpgradePlan *plan = [[BPUpgradePlan alloc] initWithSelection:[self mixedSelection]];
    __block NSUInteger calls = 0;
    XCTAssertFalse([plan executeWithProgress:progress runner:^BOOL(NSArray *arguments) {
        if (++calls == 2) [progress cancel];
        return YES;
    }]);
    XCTAssertEqual(calls, 2u);
}
- (BPUpgradeInterfaceRecorder *)recorder
{
    BPUpgradeInterfaceRecorder *recorder = class_createInstance([BPUpgradeInterfaceRecorder class], 0);
    recorder.commands = [NSMutableArray array];
    return recorder;
}
- (void)testInterfaceExecutesPlanWithSharedTokenStreamsOutputAndReloadsOnlyAfterBatches
{
    BPUpgradeInterfaceRecorder *recorder = [self recorder];
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
    NSMutableString *output = [NSMutableString string];
    XCTAssertTrue([recorder upgradeSelectedFormulae:[self mixedSelection] progress:progress withReturnBlock:^(NSString *chunk) {
        [output appendString:chunk];
    }]);
    XCTAssertEqualObjects(recorder.commands, [self commandsForSelection:[self mixedSelection]]);
    XCTAssertEqual(recorder.seenProgress, progress);
    XCTAssertEqualObjects(output, @"batch output\nbatch output\n");
    XCTAssertEqual(recorder.reloads, 1u);
}
- (void)testInterfaceDoesNotExecuteOrReloadAnEmptySelection
{
    BPUpgradeInterfaceRecorder *recorder = [self recorder];
    XCTAssertFalse([recorder upgradeSelectedFormulae:@[] progress:[NSProgress progressWithTotalUnitCount:1] withReturnBlock:nil]);
    XCTAssertEqual(recorder.commands.count, 0u);
    XCTAssertEqual(recorder.reloads, 0u);
}
- (void)testInterfaceRefreshesPartialChangesAfterFailure
{
    BPUpgradeInterfaceRecorder *recorder = [self recorder];
    recorder.failFirst = YES;
    XCTAssertFalse([recorder upgradeSelectedFormulae:[self mixedSelection] progress:[NSProgress progressWithTotalUnitCount:1] withReturnBlock:nil]);
    XCTAssertEqual(recorder.commands.count, 1u);
    XCTAssertEqual(recorder.reloads, 1u);
}
- (void)testInterfaceRefreshesPartialChangesAfterCancellationWithoutStartingNextBatch
{
    BPUpgradeInterfaceRecorder *recorder = [self recorder];
    recorder.cancelFirst = YES;
    XCTAssertFalse([recorder upgradeSelectedFormulae:[self mixedSelection] progress:[NSProgress progressWithTotalUnitCount:1] withReturnBlock:nil]);
    XCTAssertEqual(recorder.commands.count, 1u);
    XCTAssertEqual(recorder.reloads, 1u);
}
@end
