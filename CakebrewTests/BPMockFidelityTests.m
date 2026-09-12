//
//  BPMockFidelityTests.m
//  CakebrewTests
//
//  AGENTS.md states the invariant: every interface method gets a mock override
//  so UI tests never shell out to real brew. It was quietly false for most
//  formula-side mutating operations, which inherited the real implementations
//  and would have executed brew for real.
//
//  Nothing tripped it only because every mutating journey pressed Cancel at the
//  confirmation sheet. A maintainer doing the step-3 visual review who clicked
//  Tap in the mock build really tapped a repository.
//
//  So the rule enforces itself here: a mutating selector without its own mock
//  implementation fails, including one added tomorrow.
//

#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "BPHomebrewInterface.h"
#if DEBUG
// The fixture implementation is intentionally absent from Release binaries.
#import "BPMockHomebrewInterface.h"
#import "BPHomebrewManager.h"

// Private seams keep fixture tests independent of process arguments and globals.
@interface BPHomebrewInterface (CatalogFixtureInitialization)
- (instancetype)initUniqueInstance;
@end
@interface BPMockHomebrewInterface (CatalogFixtureTesting)
- (BOOL)mockArgumentEnabled:(NSString *)argument;
- (NSCondition *)makeCatalogCondition;
@end

@interface CBCatalogCondition : NSCondition
@property (atomic) NSUInteger observedArrivalCount;
@property (strong) NSMutableSet<NSThread *> *waitingThreads;
@end
@implementation CBCatalogCondition
- (instancetype)init
{
    self = [super init];
    if (self) {
        _waitingThreads = [NSMutableSet set];
    }
    return self;
}
- (void)wait
{
    // Called under the condition lock: observing this count and then acquiring
    // the lock proves the worker reached its wait, without a scheduling sleep.
    if (![self.waitingThreads containsObject:NSThread.currentThread]) {
        [self.waitingThreads addObject:NSThread.currentThread];
        self.observedArrivalCount = self.waitingThreads.count;
    }
    [super wait];
}
@end

@interface CBHeldCatalogInterface : BPMockHomebrewInterface
@property (strong) CBCatalogCondition *observedCondition;
@property BOOL slowCatalogEnabled;
@property BOOL normalReleaseEnabled;
@property NSUInteger cancellations;
@end
@implementation CBHeldCatalogInterface
- (instancetype)initUniqueInstance
{
    self = [super initUniqueInstance];
    // Also supplies the observation instrument against the pre-fix mock.
    if (self && !self.observedCondition) self.observedCondition = [CBCatalogCondition new];
    return self;
}
- (NSCondition *)makeCatalogCondition
{
    self.observedCondition = [CBCatalogCondition new];
    return self.observedCondition;
}
- (BOOL)mockArgumentEnabled:(NSString *)argument
{
    if ([argument isEqualToString:@"-BPMockHoldCatalogUntilCancelled"]) return !self.normalReleaseEnabled;
    if ([argument isEqualToString:@"-BPMockHoldCatalogUntilReleased"]) return self.normalReleaseEnabled;
    if ([argument isEqualToString:@"-BPMockSlowCatalog"]) return self.slowCatalogEnabled;
    return NO;
}
- (void)cancelAllRunningTasks
{
    self.cancellations++;
    [super cancelAllRunningTasks];
}
@end

// The real mock loop chooses whether to pause; the instrument only observes
// that choice and makes cancellation ordering independent of elapsed time.
@interface BPMockHomebrewInterface (ImportFixtureTesting)
- (NSDate *)brewfileImportDeadline;
- (void)pauseBrewfileImport;
@end

@interface CBHeldImportInterface : BPMockHomebrewInterface
@property (copy) NSSet<NSString *> *arguments;
@property (strong) NSCondition *pauseCondition;
@property (atomic) NSUInteger pauseCount;
@property (atomic) BOOL returned;
@property BOOL pauseReleased; // Protected by pauseCondition.
@end
@implementation CBHeldImportInterface
- (BOOL)mockArgumentEnabled:(NSString *)argument { return [self.arguments containsObject:argument]; }
- (NSDate *)brewfileImportDeadline { return NSDate.distantPast; }
- (void)pauseBrewfileImport
{
    [self.pauseCondition lock];
    self.pauseCount++;
    while (!self.pauseReleased) [self.pauseCondition wait];
    [self.pauseCondition unlock];
}
- (void)releasePause
{
    [self.pauseCondition lock];
    self.pauseReleased = YES;
    [self.pauseCondition broadcast];
    [self.pauseCondition unlock];
}
@end

@interface BPHomebrewManager (CatalogCompletionTesting)
- (instancetype)initUniqueInstance;
- (BPHomebrewInterface *)homebrewInterface;
- (BOOL)loadAllFormulaeCaches;
- (void)storeAllFormulaeCaches;
@end

@interface CBCatalogCompletionManager : BPHomebrewManager
@property (strong) CBHeldCatalogInterface *fixture;
@end
@implementation CBCatalogCompletionManager
+ (id)allocWithZone:(NSZone *)zone { return class_createInstance(self, 0); }
- (BPHomebrewInterface *)homebrewInterface { return self.fixture; }
- (BOOL)loadAllFormulaeCaches { return NO; }
- (void)storeAllFormulaeCaches {}
@end

@interface CBCatalogCompletionObserver : NSObject <BPHomebrewManagerDelegate>
@property NSUInteger finishes;
@property (strong) XCTestExpectation *finished;
@end
@implementation CBCatalogCompletionObserver
- (void)homebrewManager:(BPHomebrewManager *)manager didUpdateSearchResults:(NSArray *)results {}
- (void)homebrewManager:(BPHomebrewManager *)manager shouldDisplayNoBrewMessage:(BOOL)show { XCTAssertFalse(show); }
- (void)homebrewManagerFinishedUpdating:(BPHomebrewManager *)manager
{
    XCTAssertTrue(NSThread.isMainThread);
    self.finishes++;
    [self.finished fulfill];
}
@end

#endif

@interface BPMockFidelityTests : XCTestCase
@end

@implementation BPMockFidelityTests

/// Selectors that run brew in a way that changes the machine's state. Anything
/// added to BPHomebrewInterface that mutates belongs here.
- (NSArray<NSString *> *)mutatingSelectorNames
{
	return @[ @"updateWithReturnBlock:",
              @"previewAutoremoveWithProgress:",
              @"listModeForRemovalRefresh:",
              @"listServicesForRemovalRefresh",
              @"removeUnusedFormulae:progress:output:",
			  @"upgradeFormulae:withReturnBlock:",
              @"upgradeSelectedFormulae:progress:withReturnBlock:",
              @"upgradeSelectionReporting:progress:withReturnBlock:",
              @"listPinnedCasks",
			  @"upgradeCasks:withReturnBlock:",
			  @"installFormula:withOptions:andReturnBlock:",
			  @"installCask:withReturnBlock:",
			  @"uninstallFormula:withReturnBlock:",
			  @"uninstallCask:withReturnBlock:",
			  @"uninstallCask:zap:withReturnBlock:",
			  @"tapRepository:withReturnsBlock:",
			  @"untapRepository:withReturnsBlock:",
			  @"pinFormula:withReturnBlock:",
			  @"unpinFormula:withReturnBlock:",
			  @"runCleanupWithReturnBlock:",
			  @"runDoctorWithReturnBlock:",
			  @"runBrewExportToolWithPath:",
			  @"runBrewImportToolWithPath:withReturnsBlock:",
              @"runBrewImportToolWithPath:progress:withReturnsBlock:",
			  @"startService:withReturnBlock:",
			  @"stopService:withReturnBlock:",
			  @"restartService:withReturnBlock:" ];
}

- (Class)mockClass
{
	Class mock = NSClassFromString(@"BPMockHomebrewInterface");
	XCTAssertNotNil(mock, @"the mock must be compiled into this (Debug) build");
	return mock;
}

- (void)testEveryMutatingSelectorExistsOnTheRealInterface
{
	// Guards the list itself: a renamed selector must not silently stop being
	// checked.
	for (NSString *name in [self mutatingSelectorNames])
	{
		SEL selector = NSSelectorFromString(name);
		XCTAssertTrue([BPHomebrewInterface instancesRespondToSelector:selector],
					  @"%@ no longer exists — update the list", name);
	}
}

- (void)testTheMockOverridesEveryMutatingSelector
{
	Class mock = [self mockClass];
	NSMutableArray<NSString *> *inherited = [NSMutableArray array];

	for (NSString *name in [self mutatingSelectorNames])
	{
		SEL selector = NSSelectorFromString(name);
		// Responding is not enough — it would inherit the real implementation.
		// The mock must supply its own.
		Method mockMethod = class_getInstanceMethod(mock, selector);
		Method realMethod = class_getInstanceMethod([BPHomebrewInterface class], selector);
		if (mockMethod == realMethod)
		{
			[inherited addObject:name];
		}
	}

	XCTAssertEqual(inherited.count, 0u,
				   @"these would shell out to real brew under -BPMockBrew:\n%@",
				   [inherited componentsJoinedByString:@"\n"]);
}

#if DEBUG
- (CBHeldImportInterface *)importFixtureWithArguments:(NSArray<NSString *> *)arguments
{
    CBHeldImportInterface *mock = [[CBHeldImportInterface allocWithZone:NULL] initUniqueInstance];
    mock.arguments = [NSSet setWithArray:arguments];
    mock.pauseCondition = [NSCondition new];
    return mock;
}

- (void)assertHeldImport:(CBHeldImportInterface *)mock nilOutput:(BOOL)nilOutput
{
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
    NSMutableString *output = [NSMutableString string];
    __block BOOL success = YES;
    XCTestExpectation *finished = [[XCTestExpectation alloc] initWithDescription:@"import worker drained"];
    mock.returned = NO;
    mock.pauseCount = 0;
    mock.pauseReleased = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        void (^receive)(NSString *) = nilOutput ? nil : ^(NSString *text) { [output appendString:text]; };
        success = [mock runBrewImportToolWithPath:@"/fixture/Brewfile" progress:progress withReturnsBlock:receive];
        mock.returned = YES;
        [finished fulfill];
    });
    @try {
        XCTNSPredicateExpectation *observed = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithFormat:@"pauseCount > 0 OR returned == YES"] object:mock];
        XCTAssertEqual([XCTWaiter waitForExpectations:@[observed] timeout:2], XCTWaiterResultCompleted);
        XCTAssertEqual(mock.pauseCount, 1u, @"held import must ignore an expired slow deadline and reach its poll");
        XCTAssertFalse(mock.returned, @"held import cannot succeed before its own progress is cancelled");
    } @finally {
        [progress cancel];
        [mock releasePause]; // Durable even when cancellation precedes worker arrival.
        XCTAssertEqual([XCTWaiter waitForExpectations:@[finished] timeout:2], XCTWaiterResultCompleted);
    }
    XCTAssertTrue(progress.cancelled);
    XCTAssertFalse(success);
    if (!nilOutput) XCTAssertEqualObjects(output, @"MOCK_IMPORT_STARTED\nMOCK_IMPORT_CANCELLED\n");
}

- (void)testHeldBrewfileImportIgnoresExpiredDeadlineAndUsesEachOperationsProgress
{
    CBHeldImportInterface *mock = [self importFixtureWithArguments:@[@"-BPMockHoldBrewfileImportUntilCancelled", @"-BPMockSlowBrewfileImport"]];
    [self assertHeldImport:mock nilOutput:NO];
    // A cancelled operation must not release or cancel a subsequent operation.
    [self assertHeldImport:mock nilOutput:NO];
}

- (void)testHeldBrewfileImportAcceptsNilOutput
{
    CBHeldImportInterface *mock = [self importFixtureWithArguments:@[@"-BPMockHoldBrewfileImportUntilCancelled"]];
    [self assertHeldImport:mock nilOutput:YES];
}

- (void)testBrewfileImportHonorsCancellationBeforeStartAndFromStartOutput
{
    for (NSNumber *beforeStart in @[@YES, @NO]) {
        CBHeldImportInterface *mock = [self importFixtureWithArguments:@[@"-BPMockHoldBrewfileImportUntilCancelled"]];
        NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
        NSMutableString *output = [NSMutableString string];
        if (beforeStart.boolValue) [progress cancel];
        BOOL success = [mock runBrewImportToolWithPath:@"/fixture/Brewfile" progress:progress withReturnsBlock:^(NSString *text) {
            [output appendString:text];
            [progress cancel];
        }];
        XCTAssertFalse(success);
        XCTAssertEqual(mock.pauseCount, 0u);
        XCTAssertEqualObjects(output, beforeStart.boolValue ? @"" : @"MOCK_IMPORT_STARTED\nMOCK_IMPORT_CANCELLED\n");
    }
}

- (void)testBrewfileImportPreservesSuccessFailureAndExpiredSlowCompletion
{
    for (NSArray<NSString *> *arguments in @[@[], @[@"-BPMockBrewfileImportFails"], @[@"-BPMockSlowBrewfileImport"]]) {
        CBHeldImportInterface *mock = [self importFixtureWithArguments:arguments];
        NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
        NSMutableString *output = [NSMutableString string];
        BOOL success = [mock runBrewImportToolWithPath:@"/fixture/Brewfile" progress:progress withReturnsBlock:^(NSString *text) { [output appendString:text]; }];
        BOOL failure = [arguments containsObject:@"-BPMockBrewfileImportFails"];
        XCTAssertEqual(success, !failure);
        XCTAssertEqual(mock.pauseCount, 0u);
        XCTAssertFalse(progress.cancelled);
        XCTAssertEqualObjects(output, failure ? @"MOCK_IMPORT_STARTED\nMOCK_IMPORT_FAILED\n" : @"MOCK_IMPORT_STARTED\nMOCK_IMPORT_OK\n");
    }
}

- (void)startCatalog:(BPListMode)mode interface:(CBHeldCatalogInterface *)mock group:(dispatch_group_t)group
{
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *list = [mock listMode:mode];
        XCTAssertGreaterThan(list.count, 0u);
    });
}

- (BOOL)observeWaitingCatalogs:(NSUInteger)count interface:(CBHeldCatalogInterface *)mock
{
    XCTNSPredicateExpectation *arrived = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithFormat:@"observedArrivalCount >= %@", @(count)]
        object:mock.observedCondition];
    XCTWaiterResult result = [XCTWaiter waitForExpectations:@[arrived] timeout:2.0 * count];
    XCTAssertEqual(result, XCTWaiterResultCompleted, @"catalog workers must reach the condition wait");
    return result == XCTWaiterResultCompleted;
}

- (BOOL)waitForCatalogGroup:(dispatch_group_t)group
{
    XCTestExpectation *finished = [[XCTestExpectation alloc] initWithDescription:@"catalog workers finished"];
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{ [finished fulfill]; });
    return [XCTWaiter waitForExpectations:@[finished] timeout:2.0] == XCTWaiterResultCompleted;
}

- (void)cancelAndDrain:(CBHeldCatalogInterface *)mock group:(dispatch_group_t)group
{
    [mock cancelAllRunningTasks];
    XCTAssertTrue([self waitForCatalogGroup:group],
        @"every worker must finish after cancellation, including failure cleanup");
}

- (void)testBothCatalogWorkersStayHeldUntilCancellation
{
    CBHeldCatalogInterface *mock = [[CBHeldCatalogInterface allocWithZone:NULL] initUniqueInstance];
    dispatch_group_t group = dispatch_group_create();
    @try {
        [self startCatalog:kBPListAll interface:mock group:group];
        [self startCatalog:kBPListAllCasks interface:mock group:group];
        // Arrivals can precede observation; the helper must retain both.
        XCTNSPredicateExpectation *alreadyArrived = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:[NSPredicate predicateWithFormat:@"observedArrivalCount == 2"]
            object:mock.observedCondition];
        XCTAssertEqual([XCTWaiter waitForExpectations:@[alreadyArrived] timeout:4.0], XCTWaiterResultCompleted);
        if ([self observeWaitingCatalogs:2 interface:mock]) {
            [mock.observedCondition lock];
            XCTAssertNotEqual(dispatch_group_wait(group, DISPATCH_TIME_NOW), 0,
                @"catalogs cannot finish before Stop Reloading");
            [mock.observedCondition unlock];
        }
    } @finally {
        [self cancelAndDrain:mock group:group];
    }
}

- (void)testCancellationBeforeEitherCatalogArrivesIsRemembered
{
    CBHeldCatalogInterface *mock = [[CBHeldCatalogInterface allocWithZone:NULL] initUniqueInstance];
    dispatch_group_t group = dispatch_group_create();
    @try {
        [mock cancelAllRunningTasks];
        [self startCatalog:kBPListAll interface:mock group:group];
        [self startCatalog:kBPListAllCasks interface:mock group:group];
        XCTAssertTrue([self waitForCatalogGroup:group]);
    } @finally {
        [self cancelAndDrain:mock group:group];
    }
}

- (void)testCancellationReleasesEarlyCatalogAndDoesNotHoldLateCatalog
{
    CBHeldCatalogInterface *mock = [[CBHeldCatalogInterface allocWithZone:NULL] initUniqueInstance];
    dispatch_group_t group = dispatch_group_create();
    @try {
        [self startCatalog:kBPListAll interface:mock group:group];
        [self observeWaitingCatalogs:1 interface:mock];
        [mock cancelAllRunningTasks];
        [self startCatalog:kBPListAllCasks interface:mock group:group];
        XCTAssertTrue([self waitForCatalogGroup:group]);
    } @finally {
        [self cancelAndDrain:mock group:group];
    }
}

- (void)testRepeatedCancellationAndLaterReloadsNeverRearmTheHold
{
    CBHeldCatalogInterface *mock = [[CBHeldCatalogInterface allocWithZone:NULL] initUniqueInstance];
    // The explicit cancellation fixture must take precedence over the timed one.
    mock.slowCatalogEnabled = YES;
    dispatch_group_t group = dispatch_group_create();
    @try {
        [mock cancelAllRunningTasks];
        [mock cancelAllRunningTasks];
        for (NSUInteger reload = 0; reload < 2; reload++) {
            [self startCatalog:kBPListAll interface:mock group:group];
            [self startCatalog:kBPListAllCasks interface:mock group:group];
            XCTAssertTrue([self waitForCatalogGroup:group]);
        }
    } @finally {
        [self cancelAndDrain:mock group:group];
    }
}

- (void)testNonCatalogListsRemainAvailableWhileCatalogIsHeld
{
    CBHeldCatalogInterface *mock = [[CBHeldCatalogInterface allocWithZone:NULL] initUniqueInstance];
    dispatch_group_t catalogs = dispatch_group_create();
    dispatch_group_t otherLists = dispatch_group_create();
    @try {
        [self startCatalog:kBPListAll interface:mock group:catalogs];
        [self observeWaitingCatalogs:1 interface:mock];
        for (NSNumber *mode in @[@(kBPListInstalled), @(kBPListOutdated), @(kBPListLeaves),
            @(kBPListPinned), @(kBPListRepositories), @(kBPListInstalledCasks), @(kBPListOutdatedCasks)]) {
            [self startCatalog:mode.integerValue interface:mock group:otherLists];
        }
        XCTAssertTrue([self waitForCatalogGroup:otherLists]);
    } @finally {
        [self cancelAndDrain:mock group:catalogs];
        [self cancelAndDrain:mock group:otherLists];
    }
}

- (void)testExplicitReleaseFinishesBothCatalogsWithoutCancellation
{
    CBHeldCatalogInterface *mock = [[CBHeldCatalogInterface allocWithZone:NULL] initUniqueInstance];
    mock.normalReleaseEnabled = YES;
    dispatch_group_t group = dispatch_group_create();
    __block NSArray<BPFormula *> *formulae;
    __block NSArray<BPFormula *> *casks;
    @try {
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ formulae = [mock listMode:kBPListAll]; });
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ casks = [mock listMode:kBPListAllCasks]; });
        if (![self observeWaitingCatalogs:2 interface:mock]) return;
        [mock.observedCondition lock];
        XCTAssertNotEqual(dispatch_group_wait(group, DISPATCH_TIME_NOW), 0);
        [mock.observedCondition unlock];
        [mock releaseHeldCatalogs:nil];
        XCTAssertTrue([self waitForCatalogGroup:group]);
        XCTAssertEqualObjects([formulae valueForKey:@"name"], (@[@"mockwget", @"mockgit", @"mockcurl", @"mockhtop"]));
        XCTAssertEqualObjects([casks valueForKey:@"name"], (@[@"mockchrome", @"mockvscode", @"mockfirefox"]));
        XCTAssertTrue(casks.firstObject.cask);
        XCTAssertEqual(mock.cancellations, 0u);
    } @finally {
        [self cancelAndDrain:mock group:group];
    }
}

- (void)testExplicitReleaseBeforeArrivalAndRepeatedReleaseNeverRearmTheHold
{
    CBHeldCatalogInterface *mock = [[CBHeldCatalogInterface allocWithZone:NULL] initUniqueInstance];
    mock.normalReleaseEnabled = YES;
    mock.slowCatalogEnabled = YES;
    dispatch_group_t group = dispatch_group_create();
    @try {
        [mock releaseHeldCatalogs:nil];
        [mock releaseHeldCatalogs:nil];
        for (NSUInteger reload = 0; reload < 2; reload++) {
            [self startCatalog:kBPListAll interface:mock group:group];
            [self startCatalog:kBPListAllCasks interface:mock group:group];
            XCTAssertTrue([self waitForCatalogGroup:group]);
        }
        XCTAssertEqual(mock.cancellations, 0u);
    } @finally {
        [self cancelAndDrain:mock group:group];
    }
}

- (void)testExplicitReleaseFinishesEarlyAndLateCatalogWorkers
{
    CBHeldCatalogInterface *mock = [[CBHeldCatalogInterface allocWithZone:NULL] initUniqueInstance];
    mock.normalReleaseEnabled = YES;
    dispatch_group_t group = dispatch_group_create();
    @try {
        [self startCatalog:kBPListAll interface:mock group:group];
        if (![self observeWaitingCatalogs:1 interface:mock]) return;
        [mock releaseHeldCatalogs:nil];
        [self startCatalog:kBPListAllCasks interface:mock group:group];
        XCTAssertTrue([self waitForCatalogGroup:group]);
        XCTAssertEqual(mock.cancellations, 0u);
    } @finally {
        [self cancelAndDrain:mock group:group];
    }
}

- (void)testExplicitReleasePublishesNormalManagerCompletionWithoutChangingGeneration
{
    CBHeldCatalogInterface *mock = [[CBHeldCatalogInterface allocWithZone:NULL] initUniqueInstance];
    mock.normalReleaseEnabled = YES;
    CBCatalogCompletionManager *manager = [[CBCatalogCompletionManager allocWithZone:NULL] initUniqueInstance];
    manager.fixture = mock;
    CBCatalogCompletionObserver *observer = [CBCatalogCompletionObserver new];
    observer.finished = [[XCTestExpectation alloc] initWithDescription:@"normal manager completion"];
    observer.finished.assertForOverFulfill = YES;
    manager.delegate = observer;
    [manager reloadFromInterfaceRebuildingCache:YES];
    NSUInteger generation = manager.currentReloadGeneration;
    @try {
        if (![self observeWaitingCatalogs:2 interface:mock]) return;
        XCTAssertEqual(observer.finishes, 0u);
        [mock releaseHeldCatalogs:nil];
        XCTAssertEqual([XCTWaiter waitForExpectations:@[observer.finished] timeout:5], XCTWaiterResultCompleted);
        XCTAssertEqual(observer.finishes, 1u);
        XCTAssertEqual(manager.currentReloadGeneration, generation);
        XCTAssertEqual(mock.cancellations, 0u);
        XCTAssertEqualObjects([manager.allFormulae valueForKey:@"name"], (@[@"mockwget", @"mockgit", @"mockcurl", @"mockhtop"]));
        XCTAssertEqualObjects([manager.allCasks valueForKey:@"name"], (@[@"mockchrome", @"mockvscode", @"mockfirefox"]));
        XCTAssertTrue(((BPFormula *)manager.allCasks.firstObject).cask);
    } @finally {
        // Release on every failure path, then drain the real completion callback.
        [mock cancelAllRunningTasks];
        if (observer.finishes == 0) {
            XCTNSPredicateExpectation *drained = [[XCTNSPredicateExpectation alloc]
                initWithPredicate:[NSPredicate predicateWithFormat:@"finishes > 0"] object:observer];
            XCTAssertEqual([XCTWaiter waitForExpectations:@[drained] timeout:5], XCTWaiterResultCompleted);
        }
    }
}

#endif

@end
