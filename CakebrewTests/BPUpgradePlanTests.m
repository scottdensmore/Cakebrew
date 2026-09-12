#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "BPUpgradePlan.h"
#import "BPUpdatesSnapshot.h"
#import "BPHomebrewManager.h"
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

@interface BPUpdatesReadRecorder : BPHomebrewInterface
@property BOOL readSucceeded;
@property (copy) NSString *readOutput;
@property (copy) NSArray *readArguments;
@end
@implementation BPUpdatesReadRecorder
- (BOOL)performCleanReadOnlyBrewCommandWithArguments:(NSArray *)arguments output:(NSString *__autoreleasing *)output
{
    self.readArguments = arguments;
    *output = self.readOutput;
    return self.readSucceeded;
}
- (NSString *)performSyncBrewCommandWithArguments:(NSArray *)arguments
{
    XCTFail(@"Update and pin inventories must preserve process success");
    return self.readOutput;
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
- (void)testSnapshotExcludesPinsOnlyInMatchingNamespaceAndFreezesModelScalars
{
    BPFormula *formula = [BPFormula formulaWithName:@"tap/repo/shared" version:@"1" andLatestVersion:@"2"];
    BPFormula *cask = [self formula:@"shared" cask:YES];
    BPUpdatesSnapshot *snapshot = [[BPUpdatesSnapshot alloc] initWithGeneration:7
        formulae:@[formula] casks:@[cask] pinnedFormulae:@[[self formula:@"shared" cask:NO]] pinnedCasks:@[]];
    formula.cask = YES;
    cask.cask = NO;
    XCTAssertEqual(snapshot.generation, 7u);
    XCTAssertEqualObjects(snapshot.eligibleFormulae, @[]);
    XCTAssertEqualObjects(snapshot.eligibleCasks, @[@"shared"]);
    XCTAssertEqualObjects(snapshot.excludedFormulae, @[@"tap/repo/shared"]);
    XCTAssertEqualObjects(snapshot.excludedCasks, @[]);
    XCTAssertEqualObjects(snapshot.formulae.firstObject.version, @"1");
    XCTAssertEqualObjects(snapshot.formulae.firstObject.latestVersion, @"2");
}
- (void)testSnapshotTreatsUnavailablePinsDifferentlyFromSuccessfulEmptyAndRejectsEmptyPlan
{
    XCTAssertNil([[BPUpdatesSnapshot alloc] initWithGeneration:1 formulae:@[] casks:@[] pinnedFormulae:@[] pinnedCasks:nil]);
    BPUpdatesSnapshot *empty = [[BPUpdatesSnapshot alloc] initWithGeneration:1 formulae:@[] casks:@[] pinnedFormulae:@[] pinnedCasks:@[]];
    XCTAssertNotNil(empty);
    XCTAssertFalse(empty.hasEligibleUpdates);
    BPUpdatesSnapshot *pinned = [[BPUpdatesSnapshot alloc] initWithGeneration:1 formulae:@[[self formula:@"wget" cask:NO]] casks:@[] pinnedFormulae:@[[self formula:@"wget" cask:NO]] pinnedCasks:@[]];
    XCTAssertFalse(pinned.hasEligibleUpdates);
}
- (void)testManagerWaitsForFourSameGenerationInputsAndFreezesOnArrival
{
    BPHomebrewManager *manager = class_createInstance(BPHomebrewManager.class, 0);
    BPFormula *formula = [self formula:@"wget" cask:NO];
    [manager publishList:@[formula] forMode:kBPListOutdated generation:0];
    formula.cask = YES;
    [manager publishList:@[] forMode:kBPListOutdatedCasks generation:0];
    [manager publishList:@[] forMode:kBPListPinned generation:0];
    XCTAssertNil(manager.updatesSnapshot);
    [manager publishPinnedCasks:@[] generation:0];
    XCTAssertEqualObjects(manager.updatesSnapshot.eligibleFormulae, @[@"wget"]);
    [manager publishList:nil forMode:kBPListAllCasks generation:0];
    XCTAssertNotNil(manager.updatesSnapshot, @"Catalog failure does not invalidate four successful update inputs");
    [manager setValue:@1 forKey:@"reloadGeneration"];
    XCTAssertNil(manager.updatesSnapshot);
    [manager publishPinnedCasks:@[] generation:0];
    [manager publishList:@[] forMode:kBPListOutdatedCasks generation:1];
    XCTAssertNil(manager.updatesSnapshot);
}
- (void)testBatchResultsPreservePartialSuccessAndUnattemptedWork
{
    BPUpgradePlan *plan = [[BPUpgradePlan alloc] initWithSelection:[self mixedSelection]];
    __block NSUInteger calls = 0;
    BPUpgradeResult *result = [plan executeReportingWithProgress:[NSProgress progressWithTotalUnitCount:1] runner:^BOOL(NSArray *args) { return ++calls == 1; }];
    XCTAssertFalse(result.succeeded);
    XCTAssertEqual(result.batches[0].status, BPUpgradeBatchSucceeded);
    XCTAssertEqual(result.batches[1].status, BPUpgradeBatchFailed);
    result = [plan executeReportingWithProgress:[NSProgress progressWithTotalUnitCount:1] runner:^BOOL(NSArray *args) { return NO; }];
    XCTAssertEqual(result.batches[0].status, BPUpgradeBatchFailed);
    XCTAssertEqual(result.batches[1].status, BPUpgradeBatchUnattempted);
}
- (void)testBatchCancellationIsDistinctFromFailureAndDoesNotLaunchLaterWork
{
    BPUpgradePlan *plan = [[BPUpgradePlan alloc] initWithSelection:[self mixedSelection]];
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
    BPUpgradeResult *result = [plan executeReportingWithProgress:progress runner:^BOOL(NSArray *args) { [progress cancel]; return YES; }];
    XCTAssertTrue(result.cancelled);
    XCTAssertEqual(result.batches[0].status, BPUpgradeBatchCancelled);
    XCTAssertEqual(result.batches[1].status, BPUpgradeBatchUnattempted);
    result = [plan executeReportingWithProgress:progress runner:^BOOL(NSArray *args) { XCTFail(@"Cancelled before dispatch"); return YES; }];
    XCTAssertEqual(result.batches[0].status, BPUpgradeBatchUnattempted);
    XCTAssertFalse(result.attempted);
}
- (void)testConfirmedSelectionRejectsSupersededAndReplacedSnapshots
{
    BPHomebrewManager *manager = class_createInstance(BPHomebrewManager.class, 0);
    [manager publishList:@[[self formula:@"wget" cask:NO]] forMode:kBPListOutdated generation:0];
    [manager publishList:@[] forMode:kBPListOutdatedCasks generation:0];
    [manager publishList:@[] forMode:kBPListPinned generation:0];
    [manager publishPinnedCasks:@[] generation:0];
    BPUpdatesSnapshot *reviewed = manager.updatesSnapshot;
    XCTAssertEqualObjects([[manager selectionForConfirmedUpdatesSnapshot:reviewed] valueForKey:@"name"], @[@"wget"]);
    [manager publishList:@[] forMode:kBPListOutdated generation:0];
    XCTAssertNil([manager selectionForConfirmedUpdatesSnapshot:reviewed]);
    [manager setValue:@1 forKey:@"reloadGeneration"];
    XCTAssertNil([manager selectionForConfirmedUpdatesSnapshot:manager.updatesSnapshot]);
}
- (void)testSuccessfulCaskPinInventoryDoesNotExcludeSameNamedFormula
{
    BPUpdatesSnapshot *snapshot = [[BPUpdatesSnapshot alloc] initWithGeneration:1
        formulae:@[[self formula:@"shared" cask:NO]] casks:@[[self formula:@"tap/cask/shared" cask:YES]]
        pinnedFormulae:@[] pinnedCasks:@[[self formula:@"shared" cask:YES]]];
    XCTAssertEqualObjects(snapshot.eligibleFormulae, @[@"shared"]);
    XCTAssertEqualObjects(snapshot.excludedCasks, @[@"tap/cask/shared"]);
}
- (void)testUpdateAndPinInventoryQueriesPreserveFailureEvenWithPlausibleOutput
{
    BPUpdatesReadRecorder *reader = class_createInstance(BPUpdatesReadRecorder.class, 0);
    for (NSNumber *mode in @[@(kBPListOutdated), @(kBPListOutdatedCasks), @(kBPListPinned)]) {
        reader.readSucceeded = NO; reader.readOutput = @"wget\n";
        XCTAssertNil([reader listMode:mode.integerValue]);
        reader.readSucceeded = YES; reader.readOutput = @"";
        XCTAssertEqualObjects([reader listMode:mode.integerValue], @[]);
        XCTAssertTrue([reader.readArguments containsObject:mode.integerValue == kBPListOutdatedCasks ? @"--cask" : @"--formula"]);
    }
    reader.readSucceeded = NO; reader.readOutput = @"browser\n";
    XCTAssertNil([reader listPinnedCasks]);
    reader.readSucceeded = YES; reader.readOutput = @"";
    XCTAssertEqualObjects([reader listPinnedCasks], @[]);
    XCTAssertEqualObjects(reader.readArguments, (@[@"list", @"--cask", @"--pinned"]));
}
@end
