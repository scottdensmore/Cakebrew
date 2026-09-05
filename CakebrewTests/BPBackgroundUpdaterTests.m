//
//  BPBackgroundUpdaterTests.m
//  CakebrewTests
//
//  Tests for the background updater's pure decision logic: what the dock
//  badge shows and when a notification is warranted.
//

#import <XCTest/XCTest.h>
#import "BPBackgroundUpdater.h"
#import "BPHomebrewManager.h"
#import <UserNotifications/UserNotifications.h>

@interface BPBackgroundUpdater (NotificationDeliveryTests)
- (instancetype)initWithNotificationCenter:(id)notificationCenter;
- (void)deliverOutdatedNotificationWithFormulaeCount:(NSUInteger)formulaeCount caskCount:(NSUInteger)caskCount;
@end

// Keep real observation and delivery decisions, replacing only periodic polling
// and the native Dock presentation so these tests touch neither brew nor AppKit.
@interface BPObservingBackgroundUpdater : BPBackgroundUpdater
@property (copy) NSString *badgeLabel;
@end

@implementation BPObservingBackgroundUpdater
- (void)scheduleTimer {}
- (void)applyDockBadgeLabel:(NSString *)label { self.badgeLabel = label; }
@end

@interface BPNotificationCenterDeliverySpy : NSObject
@property (strong) UNNotificationRequest *request;
@property NSUInteger deliveryCount;
@property NSUInteger authorizationCount;
@property BOOL holdAuthorization;
@property (copy) void (^pendingAuthorization)(BOOL, NSError *);
@end

@implementation BPNotificationCenterDeliverySpy

- (void)requestAuthorizationWithOptions:(UNAuthorizationOptions)options
					 completionHandler:(void (^)(BOOL, NSError *))completionHandler
{
	self.authorizationCount += 1;
	if (self.holdAuthorization) self.pendingAuthorization = completionHandler;
	else completionHandler(YES, nil);
}

- (void)addNotificationRequest:(UNNotificationRequest *)request
		 withCompletionHandler:(void (^)(NSError *error))completionHandler
{
	self.request = request;
	self.deliveryCount += 1;
}

@end

@interface BPBackgroundUpdaterTests : XCTestCase
@property (strong) id savedBaseline;
@property (strong) NSArray *savedOutdatedFormulae;
@property (strong) NSArray *savedOutdatedCasks;
@property (strong) id<BPHomebrewManagerDelegate> savedDelegate;
@property (strong) BPObservingBackgroundUpdater *observingUpdater;
@end

@implementation BPBackgroundUpdaterTests

- (void)setUp
{
	[super setUp];
	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	self.savedBaseline = [defaults objectForKey:@"BPLastNotifiedOutdatedCount"];
	BPHomebrewManager *manager = BPHomebrewManager.sharedManager;
	self.savedOutdatedFormulae = manager.outdatedFormulae;
	self.savedOutdatedCasks = manager.outdatedCasks;
	self.savedDelegate = manager.delegate;
}

- (void)tearDown
{
	[self drainNotificationWork];
	self.observingUpdater = nil;
	BPHomebrewManager *manager = BPHomebrewManager.sharedManager;
	manager.outdatedFormulae = self.savedOutdatedFormulae;
	manager.outdatedCasks = self.savedOutdatedCasks;
	manager.delegate = self.savedDelegate;
	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	if (self.savedBaseline) [defaults setObject:self.savedBaseline forKey:@"BPLastNotifiedOutdatedCount"];
	else [defaults removeObjectForKey:@"BPLastNotifiedOutdatedCount"];
	[super tearDown];
}

- (void)drainNotificationWork
{
	XCTestExpectation *drained = [self expectationWithDescription:@"scheduled notification work drained"];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
		[drained fulfill];
	});
	[self waitForExpectations:@[drained] timeout:2.0];
}

- (BPNotificationCenterDeliverySpy *)startObservingReloadsWithBaseline:(NSNumber *)baseline
{
	BPHomebrewManager *manager = BPHomebrewManager.sharedManager;
	manager.delegate = nil;
	[manager cancelReload];
	manager.outdatedFormulae = @[[BPFormula formulaWithName:@"old-formula"]];
	manager.outdatedCasks = @[];
	if (baseline) [BPBackgroundUpdater setPersistedOutdatedCount:baseline.unsignedIntegerValue];
	else [BPBackgroundUpdater clearPersistedOutdatedCount];
	BPNotificationCenterDeliverySpy *center = [[BPNotificationCenterDeliverySpy alloc] init];
	self.observingUpdater = [[BPObservingBackgroundUpdater alloc] initWithNotificationCenter:center];
	[self.observingUpdater start];
	return center;
}

- (void)assertCoherentNotificationWhenCasksFinishFirst:(BOOL)casksFirst
{
	BPNotificationCenterDeliverySpy *center = [self startObservingReloadsWithBaseline:@1];
	BPHomebrewManager *manager = BPHomebrewManager.sharedManager;
	NSUInteger generation = manager.currentReloadGeneration;
	NSArray *casks = @[[BPFormula formulaWithName:@"new-cask"], [BPFormula formulaWithName:@"other-cask"]];
	[manager publishList:casksFirst ? casks : @[]
		forMode:casksFirst ? kBPListOutdatedCasks : kBPListOutdated generation:generation];
	[self drainNotificationWork];
	XCTAssertEqual([BPBackgroundUpdater persistedOutdatedCount], 1u, @"one list must not poison the coherent baseline");
	XCTAssertEqual(center.authorizationCount, 0u, @"an incomplete pair must not request a notification");
	XCTAssertEqual(center.deliveryCount, 0u);
	XCTAssertEqualObjects(self.observingUpdater.badgeLabel, casksFirst ? @"3" : nil,
		@"the Dock badge should still reflect incremental list publications");

	[manager publishList:casksFirst ? @[] : casks
		forMode:casksFirst ? kBPListOutdated : kBPListOutdatedCasks generation:generation];
	[self drainNotificationWork];
	XCTAssertEqual([BPBackgroundUpdater persistedOutdatedCount], 2u);
	XCTAssertEqualObjects(self.observingUpdater.badgeLabel, @"2");
	XCTAssertEqual(center.deliveryCount, 1u);
	XCTAssertEqualObjects(center.request.content.userInfo,
		(@{BPOutdatedNotificationTargetKey: BPOutdatedNotificationTargetCasks}),
		@"the delivered request must not include a stale formula-only destination");
}

- (void)testCasksFinishingFirstWaitsForCoherentOutdatedNotification
{
	[self assertCoherentNotificationWhenCasksFinishFirst:YES];
}

- (void)testFormulaeFinishingFirstWaitsForCoherentOutdatedNotification
{
	[self assertCoherentNotificationWhenCasksFinishFirst:NO];
}

- (void)testInitialCompletePairSeedsBaselineWithoutNotifying
{
	BPNotificationCenterDeliverySpy *center = [self startObservingReloadsWithBaseline:nil];
	BPHomebrewManager *manager = BPHomebrewManager.sharedManager;
	NSUInteger generation = manager.currentReloadGeneration;
	[manager publishList:@[[BPFormula formulaWithName:@"new-cask"]] forMode:kBPListOutdatedCasks generation:generation];
	[self drainNotificationWork];
	XCTAssertFalse([BPBackgroundUpdater hasPersistedOutdatedCount]);
	[manager publishList:@[] forMode:kBPListOutdated generation:generation];
	[self drainNotificationWork];
	XCTAssertEqual([BPBackgroundUpdater persistedOutdatedCount], 1u);
	XCTAssertTrue([BPBackgroundUpdater hasPersistedOutdatedCount]);
	XCTAssertEqual(center.authorizationCount, 0u);
}

- (void)testFailedAndCanceledPairsDoNotChangeTheBaselineOrNotify
{
	BPNotificationCenterDeliverySpy *center = [self startObservingReloadsWithBaseline:@1];
	BPHomebrewManager *manager = BPHomebrewManager.sharedManager;
	NSUInteger generation = manager.currentReloadGeneration;
	[manager publishList:@[] forMode:kBPListOutdated generation:generation];
	[manager publishList:nil forMode:kBPListOutdatedCasks generation:generation];
	[self drainNotificationWork];
	XCTAssertEqual([BPBackgroundUpdater persistedOutdatedCount], 1u);
	[manager cancelReload];
	[manager publishList:@[[BPFormula formulaWithName:@"stale"]] forMode:kBPListOutdatedCasks generation:generation];
	[manager publishList:@[] forMode:kBPListOutdatedCasks generation:manager.currentReloadGeneration];
	[self drainNotificationWork];
	XCTAssertEqual([BPBackgroundUpdater persistedOutdatedCount], 1u);
	XCTAssertEqual(center.authorizationCount, 0u);
	XCTAssertEqual(center.deliveryCount, 0u);
}

- (void)testDuplicateListPublicationDoesNotRenotifyTheSameGeneration
{
	BPNotificationCenterDeliverySpy *center = [self startObservingReloadsWithBaseline:@0];
	BPHomebrewManager *manager = BPHomebrewManager.sharedManager;
	NSUInteger generation = manager.currentReloadGeneration;
	[manager publishList:@[[BPFormula formulaWithName:@"first"]]
		forMode:kBPListOutdated generation:generation];
	[manager publishList:@[] forMode:kBPListOutdatedCasks generation:generation];
	[self drainNotificationWork];
	XCTAssertEqual(center.deliveryCount, 1u);
	[manager publishList:@[[BPFormula formulaWithName:@"duplicate"]] forMode:kBPListOutdatedCasks generation:generation];
	[self drainNotificationWork];
	XCTAssertEqual(center.deliveryCount, 1u);
	XCTAssertEqual([BPBackgroundUpdater persistedOutdatedCount], 1u);
}

- (void)testDeferredAuthorizationDeliversCapturedCountsAfterANewerSnapshot
{
	BPNotificationCenterDeliverySpy *center = [self startObservingReloadsWithBaseline:@0];
	center.holdAuthorization = YES;
	BPHomebrewManager *manager = BPHomebrewManager.sharedManager;
	NSUInteger generation = manager.currentReloadGeneration;
	[manager publishList:@[] forMode:kBPListOutdated generation:generation];
	[manager publishList:@[[BPFormula formulaWithName:@"cask-a"], [BPFormula formulaWithName:@"cask-b"]]
		forMode:kBPListOutdatedCasks generation:generation];
	[self drainNotificationWork];
	XCTAssertEqual(center.authorizationCount, 1u);
	XCTAssertNotNil(center.pendingAuthorization);
	[manager cancelReload];
	generation = manager.currentReloadGeneration;
	[manager publishList:@[[BPFormula formulaWithName:@"later-formula"]] forMode:kBPListOutdated generation:generation];
	[manager publishList:@[] forMode:kBPListOutdatedCasks generation:generation];
	[self drainNotificationWork];
	XCTAssertEqual([BPBackgroundUpdater persistedOutdatedCount], 1u);
	XCTAssertEqual(center.authorizationCount, 1u);
	void (^authorization)(BOOL, NSError *) = center.pendingAuthorization;
	center.pendingAuthorization = nil;
	if (authorization) authorization(YES, nil);
	[self drainNotificationWork];
	XCTAssertEqual(center.deliveryCount, 1u);
	XCTAssertEqualObjects(center.request.content.userInfo,
		(@{BPOutdatedNotificationTargetKey: BPOutdatedNotificationTargetCasks}));
}

- (void)testForeignOrSupersededSnapshotsDoNotChangeTheBaseline
{
	BPNotificationCenterDeliverySpy *center = [self startObservingReloadsWithBaseline:@1];
	BPHomebrewManager *manager = BPHomebrewManager.sharedManager;
	NSDictionary *snapshot = @{@"formulae-count": @3, @"cask-count": @2, @"generation": @(manager.currentReloadGeneration)};
	[NSNotificationCenter.defaultCenter postNotificationName:@"BPHomebrewManagerDidPublishOutdatedSnapshotNotification"
		object:[[NSObject alloc] init] userInfo:snapshot];
	[manager cancelReload];
	[NSNotificationCenter.defaultCenter postNotificationName:@"BPHomebrewManagerDidPublishOutdatedSnapshotNotification"
		object:manager userInfo:snapshot];
	[self drainNotificationWork];
	XCTAssertEqual([BPBackgroundUpdater persistedOutdatedCount], 1u);
	XCTAssertEqual(center.authorizationCount, 0u);
}

#pragma mark - badge label

- (void)testBadgeLabelIsNilWhenNothingOutdated
{
	XCTAssertNil([BPBackgroundUpdater badgeLabelForOutdatedCount:0],
				 @"no badge when everything is up to date");
}

- (void)testBadgeLabelShowsTheCount
{
	XCTAssertEqualObjects([BPBackgroundUpdater badgeLabelForOutdatedCount:1], @"1");
	XCTAssertEqualObjects([BPBackgroundUpdater badgeLabelForOutdatedCount:42], @"42");
}

#pragma mark - notification decision

- (void)testProductionNotificationDeliveryAttachesSemanticPayloadToRequestContent
{
	BPNotificationCenterDeliverySpy *center = [[BPNotificationCenterDeliverySpy alloc] init];
	BPBackgroundUpdater *updater = [[BPBackgroundUpdater alloc] initWithNotificationCenter:center];

	[updater deliverOutdatedNotificationWithFormulaeCount:0 caskCount:3];

	XCTAssertEqual(center.deliveryCount, 1u);
	XCTAssertEqualObjects(center.request.content.userInfo,
		@{ BPOutdatedNotificationTargetKey: BPOutdatedNotificationTargetCasks });
}

- (void)testProductionMixedNotificationDeliveryPreservesBothPackageKinds
{
	BPNotificationCenterDeliverySpy *center = [[BPNotificationCenterDeliverySpy alloc] init];
	BPBackgroundUpdater *updater = [[BPBackgroundUpdater alloc] initWithNotificationCenter:center];

	[updater deliverOutdatedNotificationWithFormulaeCount:2 caskCount:3];

	XCTAssertEqual(center.deliveryCount, 1u);
	XCTAssertEqualObjects(center.request.content.userInfo,
		@{ BPOutdatedNotificationTargetKey: @"mixed" });
}

- (void)testFormulaeNotificationPayloadIsSemanticAndStable
{
	NSDictionary *payload = [BPBackgroundUpdater notificationUserInfoForOutdatedFormulaeCount:2
															 caskCount:0];

	XCTAssertEqualObjects(payload, @{ BPOutdatedNotificationTargetKey: BPOutdatedNotificationTargetFormulae });
}

- (void)testCaskOnlyNotificationPayloadTargetsCasks
{
	NSDictionary *payload = [BPBackgroundUpdater notificationUserInfoForOutdatedFormulaeCount:0
															 caskCount:3];

	XCTAssertEqualObjects(payload, @{ BPOutdatedNotificationTargetKey: BPOutdatedNotificationTargetCasks });
}

- (void)testMixedNotificationPayloadIsDistinctFromFormulaeOnly
{
	NSDictionary *payload = [BPBackgroundUpdater notificationUserInfoForOutdatedFormulaeCount:2
															 caskCount:3];

	XCTAssertEqualObjects(payload, @{ BPOutdatedNotificationTargetKey: @"mixed" });
	XCTAssertEqualObjects(BPOutdatedNotificationTargetMixed, @"mixed");
	XCTAssertNotEqualObjects(payload, [BPBackgroundUpdater notificationUserInfoForOutdatedFormulaeCount:2
																					caskCount:0]);
}

- (void)testEmptyOutdatedSetHasNoNotificationPayload
{
	XCTAssertNil([BPBackgroundUpdater notificationUserInfoForOutdatedFormulaeCount:0 caskCount:0]);
}

- (void)testNotifiesWhenOutdatedCountRises
{
	XCTAssertTrue([BPBackgroundUpdater shouldNotifyForCount:3 previousCount:0]);
	XCTAssertTrue([BPBackgroundUpdater shouldNotifyForCount:5 previousCount:3]);
}

- (void)testDoesNotNotifyWhenNothingIsOutdated
{
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:0 previousCount:0]);
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:0 previousCount:4],
				   @"upgrading everything should not notify");
}

- (void)testDoesNotNotifyWhenCountIsUnchangedOrFalls
{
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:3 previousCount:3],
				   @"repeat checks with the same result stay quiet");
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:2 previousCount:3],
				   @"partially upgrading should not notify");
}


#pragma mark - the first observation is a baseline, not news

- (void)testTheFirstObservationSeedsTheBaselineAndDoesNotNotify
{
	// lastKnownOutdatedCount started at 0 in memory, and observers registered
	// before the first reload — so the first callback compared the real count
	// against 0 and banner-ed on every launch for news the user already had.
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:7 previousCount:0 hasBaseline:NO],
				   @"the first observation of a launch is what is already on disk, not an increase");
}

- (void)testAnIncreaseAfterTheBaselineNotifies
{
	XCTAssertTrue([BPBackgroundUpdater shouldNotifyForCount:8 previousCount:7 hasBaseline:YES]);
}

- (void)testNoIncreaseAfterTheBaselineDoesNotNotify
{
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:7 previousCount:7 hasBaseline:YES]);
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:3 previousCount:7 hasBaseline:YES]);
}

- (void)testAZeroCountNeverNotifiesEvenSeeded
{
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:0 previousCount:0 hasBaseline:YES]);
}

- (void)testTheBaselineSurvivesRelaunch
{
	// Persisted, so quitting and reopening with the same outdated set is not
	// treated as news either.
	[BPBackgroundUpdater setPersistedOutdatedCount:5];
	XCTAssertEqual([BPBackgroundUpdater persistedOutdatedCount], 5u);
	XCTAssertTrue([BPBackgroundUpdater hasPersistedOutdatedCount]);

	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:5
											   previousCount:[BPBackgroundUpdater persistedOutdatedCount]
												 hasBaseline:[BPBackgroundUpdater hasPersistedOutdatedCount]]);
}

- (void)testClearingTheBaselineRestoresTheUnseededState
{
	[BPBackgroundUpdater setPersistedOutdatedCount:5];
	[BPBackgroundUpdater clearPersistedOutdatedCount];
	XCTAssertFalse([BPBackgroundUpdater hasPersistedOutdatedCount]);
}

@end
