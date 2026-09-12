#import <XCTest/XCTest.h>
#import "BPSearchCoordinator.h"

@interface BPSearchCoordinatorTests : XCTestCase
@end

@implementation BPSearchCoordinatorTests

- (void)testSchedulingDefersQueryByTheExistingDebounceInterval
{
	__block dispatch_block_t pending;
	__block NSTimeInterval delay = 0;
	__block NSString *performed;
	BPSearchCoordinator *coordinator = [[BPSearchCoordinator alloc]
		initWithSchedule:^(NSTimeInterval interval, dispatch_block_t work) {
			delay = interval;
			pending = work;
		} performSearch:^(NSString *query) { performed = query; } cancelSearch:^{}];
	[coordinator scheduleQuery:@"mockvscode"];
	XCTAssertEqualWithAccuracy(delay, 0.15, 0.0001);
	XCTAssertNil(performed);
	XCTAssertFalse(coordinator.isSearching);
	XCTAssertNotNil(pending);
	pending();
	XCTAssertEqualObjects(performed, @"mockvscode");
}

- (void)testResultsCaptureOnlyTheFirstSidebarRowAndEndCancelsBeforeReturningIt
{
	__block NSUInteger cancellations = 0;
	__block BOOL searchingAtCancellation = YES;
	__block __weak BPSearchCoordinator *weakCoordinator;
	BPSearchCoordinator *coordinator = [[BPSearchCoordinator alloc]
		initWithSchedule:^(NSTimeInterval interval, dispatch_block_t work) {}
		performSearch:^(NSString *query) {} cancelSearch:^{
			cancellations += 1;
			searchingAtCancellation = weakCoordinator.isSearching;
		}];
	weakCoordinator = coordinator;
	XCTAssertFalse(coordinator.isSearching);
	[coordinator didReceiveResultsForSidebarRow:9];
	XCTAssertTrue(coordinator.isSearching);
	[coordinator didReceiveResultsForSidebarRow:2];
	XCTAssertEqual(coordinator.originalSidebarRow, 9);
	XCTAssertEqual([coordinator endSearchReturningSidebarRow], 9);
	XCTAssertEqual(cancellations, 1u);
	XCTAssertFalse(searchingAtCancellation);
	XCTAssertFalse(coordinator.isSearching);
	[coordinator didReceiveResultsForSidebarRow:4];
	XCTAssertEqual(coordinator.originalSidebarRow, 4);
	XCTAssertEqual([coordinator endSearchReturningSidebarRow], 4);
}

- (void)testSidebarRowsRemainRawForTheControllerToValidate
{
	BPSearchCoordinator *coordinator = [[BPSearchCoordinator alloc]
		initWithSchedule:^(NSTimeInterval interval, dispatch_block_t work) {}
		performSearch:^(NSString *query) {} cancelSearch:^{}];
	[coordinator didReceiveResultsForSidebarRow:-1];
	XCTAssertEqual([coordinator endSearchReturningSidebarRow], -1);
	[coordinator didReceiveResultsForSidebarRow:NSIntegerMax];
	XCTAssertEqual([coordinator endSearchReturningSidebarRow], NSIntegerMax);
}

- (void)testNavigationInvalidatesRetainedWorkAndAllowsTheNextQuery
{
	NSMutableArray<dispatch_block_t> *scheduled = [NSMutableArray array];
	NSMutableArray<NSString *> *performed = [NSMutableArray array];
	__block NSUInteger cancellations = 0;
	BPSearchCoordinator *coordinator = [[BPSearchCoordinator alloc]
		initWithSchedule:^(NSTimeInterval interval, dispatch_block_t work) { [scheduled addObject:work]; }
		performSearch:^(NSString *query) { [performed addObject:query]; }
		cancelSearch:^{ cancellations += 1; }];
	[coordinator didReceiveResultsForSidebarRow:9];
	[coordinator scheduleQuery:@"old"];
	NSUInteger generation = coordinator.generation;
	[coordinator cancelForNavigation];
	XCTAssertFalse(coordinator.isSearching);
	XCTAssertEqual(cancellations, 1u);
	XCTAssertEqual(coordinator.generation, generation + 1);
	scheduled[0]();
	XCTAssertEqual(performed.count, 0u);
	[coordinator scheduleQuery:@"new"];
	scheduled[1]();
	XCTAssertEqualObjects(performed, (@[@"new"]));
	[coordinator didReceiveResultsForSidebarRow:3];
	XCTAssertEqual(coordinator.originalSidebarRow, 3);
}

- (void)testClearingSearchInvalidatesRetainedCallbackWithoutResumingSearch
{
	__block dispatch_block_t pending;
	__block NSUInteger performed = 0;
	__block NSUInteger cancellations = 0;
	__block __weak BPSearchCoordinator *weakCoordinator;
	BPSearchCoordinator *coordinator = [[BPSearchCoordinator alloc]
		initWithSchedule:^(NSTimeInterval interval, dispatch_block_t work) { pending = work; }
		performSearch:^(NSString *query) {
			performed += 1;
			[weakCoordinator didReceiveResultsForSidebarRow:9];
		} cancelSearch:^{ cancellations += 1; }];
	weakCoordinator = coordinator;
	[coordinator scheduleQuery:@"mockvscode"];
	[coordinator endSearchReturningSidebarRow];
	XCTAssertEqual(cancellations, 1u);
	XCTAssertFalse(coordinator.isSearching);
	XCTAssertNotNil(pending);
	if (!pending) {
		return;
	}
	pending();
	XCTAssertEqual(performed, 0u, @"clearing must invalidate already queued search work");
	XCTAssertFalse(coordinator.isSearching, @"old results must not reopen the cleared search");
}

- (void)testNewQueryRunsAfterClearingWithoutRevivingOlderQuery
{
	NSMutableArray<dispatch_block_t> *scheduled = [NSMutableArray array];
	NSMutableArray<NSString *> *performed = [NSMutableArray array];
	BPSearchCoordinator *coordinator = [[BPSearchCoordinator alloc]
		initWithSchedule:^(NSTimeInterval interval, dispatch_block_t work) { [scheduled addObject:work]; }
		performSearch:^(NSString *query) { [performed addObject:query]; } cancelSearch:^{}];
	[coordinator scheduleQuery:@"old"];
	[coordinator endSearchReturningSidebarRow];
	[coordinator scheduleQuery:@"new"];
	scheduled[0]();
	XCTAssertEqual(performed.count, 0u, @"a new query must not make cleared work valid again");
	scheduled[1]();
	XCTAssertEqualObjects(performed, (@[@"new"]));
	[coordinator didReceiveResultsForSidebarRow:4];
	XCTAssertTrue(coordinator.isSearching);
	XCTAssertEqual([coordinator endSearchReturningSidebarRow], 4);
}

- (void)testRetainedScheduledWorkDoesNotKeepTheCoordinatorAlive
{
	__block dispatch_block_t pending;
	__block BOOL performed = NO;
	__weak BPSearchCoordinator *weakCoordinator;
	@autoreleasepool {
		BPSearchCoordinator *coordinator = [[BPSearchCoordinator alloc]
			initWithSchedule:^(NSTimeInterval interval, dispatch_block_t work) { pending = work; }
			performSearch:^(NSString *query) { performed = YES; } cancelSearch:^{}];
		weakCoordinator = coordinator;
		[coordinator scheduleQuery:@"mock"];
	}
	XCTAssertNil(weakCoordinator);
	XCTAssertNotNil(pending);
	pending();
	XCTAssertFalse(performed);
}

- (void)testProductionSchedulerCoalescesQueriesAndPerformsOnMainThread
{
	XCTestExpectation *lastQuery = [self expectationWithDescription:@"last debounced query"];
	NSMutableArray<NSString *> *performed = [NSMutableArray array];
	BPSearchCoordinator *coordinator = [[BPSearchCoordinator alloc]
		initWithPerformSearch:^(NSString *query) {
			XCTAssertTrue(NSThread.isMainThread);
			[performed addObject:query];
			[lastQuery fulfill];
		} cancelSearch:^{}];
	[coordinator scheduleQuery:@"m"];
	[coordinator scheduleQuery:@"mock"];
	[coordinator scheduleQuery:@"mockvscode"];
	XCTAssertEqual(performed.count, 0u);
	[self waitForExpectations:@[lastQuery] timeout:2.0];
	XCTAssertEqualObjects(performed, (@[@"mockvscode"]));
}

@end
