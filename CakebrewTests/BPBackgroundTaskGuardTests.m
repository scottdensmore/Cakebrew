//
//  BPBackgroundTaskGuardTests.m
//  CakebrewTests
//
//  -checkForBackgroundTask returned void, so its `return` only exited the
//  guard itself. Every caller invoked it as a bare statement in the shape of a
//  guard and then carried on regardless: the user saw the "a background task is
//  running" warning, dismissed it, was handed the operation's own confirmation
//  sheet, and confirming started a second brew run that Homebrew's own lock
//  then rejected with a raw error in the log.
//
//  The decision is now a pure predicate on BPAppDelegate — which owns both the
//  flag and the warning — following +shouldNotifyForCount:previousCount: in
//  BPBackgroundUpdater, so it can be tested without a window.
//

#import <XCTest/XCTest.h>
#import "BPAppDelegate.h"
#import "BPBackgroundUpdater.h"
#import <objc/runtime.h>
#import <UserNotifications/UserNotifications.h>

@interface BPAppDelegate (NotificationResponseTests)
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
	   didReceiveNotificationResponse:(UNNotificationResponse *)response
				withCompletionHandler:(void(^)(void))completionHandler;
@end

@interface BPNotificationResponseStub : NSObject
@property (copy) NSDictionary *userInfo;
@end

@implementation BPNotificationResponseStub
- (id)notification { return self; }
- (id)request { return self; }
- (id)content { return self; }
@end

@interface BPNotificationPresentationSpy : NSObject <BPNotificationPresenting>
@property NSUInteger cleanupCount;
@property NSUInteger activationCount;
@property NSUInteger windowCount;
@property BOOL calledOnMainThread;
@end

@implementation BPNotificationPresentationSpy

- (instancetype)init
{
	self = [super init];
	if (self)
	{
		_calledOnMainThread = YES;
	}
	return self;
}

- (void)cleanupNotificationAlerts
{
	self.cleanupCount += 1;
	self.calledOnMainThread = self.calledOnMainThread && NSThread.isMainThread;
}

- (void)activateCakebrewIgnoringOtherApps
{
	self.activationCount += 1;
	self.calledOnMainThread = self.calledOnMainThread && NSThread.isMainThread;
}

- (void)showMainWindow
{
	self.windowCount += 1;
	self.calledOnMainThread = self.calledOnMainThread && NSThread.isMainThread;
}

@end

@interface BPNotificationNavigationTargetSpy : NSObject <BPNotificationNavigation>
@property NSUInteger formulaeNavigationCount;
@property NSUInteger caskNavigationCount;
@property BOOL calledOnMainThread;
@end

@implementation BPNotificationNavigationTargetSpy

- (void)showOutdatedFormulae:(id)sender
{
	self.formulaeNavigationCount += 1;
	self.calledOnMainThread = NSThread.isMainThread;
}

- (void)showOutdatedCasks:(id)sender
{
	self.caskNavigationCount += 1;
	self.calledOnMainThread = NSThread.isMainThread;
}

@end

@interface BPBackgroundTaskGuardTests : XCTestCase
@end

@implementation BPBackgroundTaskGuardTests

- (void)testAnOperationIsBlockedWhileABackgroundTaskRuns
{
	XCTAssertTrue([BPAppDelegate shouldBlockOperationWhileRunningBackgroundTask:YES],
				  @"starting a second brew run is what Homebrew's lock rejects");
}

- (void)testAnOperationProceedsWhenNothingIsRunning
{
	XCTAssertFalse([BPAppDelegate shouldBlockOperationWhileRunningBackgroundTask:NO]);
}

#pragma mark - Notification navigation

- (void)testNotificationPayloadMapsToNavigationWithoutAppKitState
{
	XCTAssertEqual([BPAppDelegate notificationNavigationActionForUserInfo:
		@{ BPOutdatedNotificationTargetKey: BPOutdatedNotificationTargetFormulae }],
		BPNotificationNavigationActionOutdatedFormulae);
	XCTAssertEqual([BPAppDelegate notificationNavigationActionForUserInfo:
		@{ BPOutdatedNotificationTargetKey: BPOutdatedNotificationTargetCasks }],
		BPNotificationNavigationActionOutdatedCasks);
}

- (void)testMixedNotificationPayloadNavigatesToFormulaeUntilACombinedViewExists
{
	XCTAssertEqual([BPAppDelegate notificationNavigationActionForUserInfo:
		@{ BPOutdatedNotificationTargetKey: @"mixed" }],
		BPNotificationNavigationActionOutdatedFormulae);
}

- (void)testMissingMalformedAndFutureNotificationPayloadsMapToNoNavigation
{
	XCTAssertEqual([BPAppDelegate notificationNavigationActionForUserInfo:nil],
		BPNotificationNavigationActionNone);
	XCTAssertEqual([BPAppDelegate notificationNavigationActionForUserInfo:@{}],
		BPNotificationNavigationActionNone);
	XCTAssertEqual([BPAppDelegate notificationNavigationActionForUserInfo:
		@{ BPOutdatedNotificationTargetKey: @42 }],
		BPNotificationNavigationActionNone);
	XCTAssertEqual([BPAppDelegate notificationNavigationActionForUserInfo:
		@{ BPOutdatedNotificationTargetKey: @"future-target" }],
		BPNotificationNavigationActionNone);
}

- (void)assertInvalidNotificationResponseWithUserInfo:(NSDictionary *)userInfo
{
	BPAppDelegate *delegate = [[BPAppDelegate alloc] init];
	BPNotificationPresentationSpy *presentation = [[BPNotificationPresentationSpy alloc] init];
	BPNotificationNavigationTargetSpy *target = [[BPNotificationNavigationTargetSpy alloc] init];
	delegate.notificationPresenter = presentation;
	delegate.notificationNavigationTarget = target;

	__block NSUInteger completionCount = 0;
	BPNotificationResponseStub *response = [[BPNotificationResponseStub alloc] init];
	response.userInfo = userInfo;
	[delegate userNotificationCenter:nil
	   didReceiveNotificationResponse:(UNNotificationResponse *)response
			withCompletionHandler:^{ completionCount += 1; }];

	XCTAssertEqual(presentation.cleanupCount, 1u);
	XCTAssertEqual(presentation.activationCount, 1u);
	XCTAssertEqual(presentation.windowCount, 1u);
	XCTAssertEqual(completionCount, 1u);
	XCTAssertEqual(target.formulaeNavigationCount, 0u);
	XCTAssertEqual(target.caskNavigationCount, 0u);
}

- (void)testMissingNotificationPayloadPresentsWithoutNavigatingAndCompletesOnce
{
	[self assertInvalidNotificationResponseWithUserInfo:nil];
}

- (void)testEmptyNotificationPayloadPresentsWithoutNavigatingAndCompletesOnce
{
	[self assertInvalidNotificationResponseWithUserInfo:@{}];
}

- (void)testMalformedNotificationPayloadPresentsWithoutNavigatingAndCompletesOnce
{
	[self assertInvalidNotificationResponseWithUserInfo:@{ BPOutdatedNotificationTargetKey: @42 }];
}

- (void)testFutureNotificationPayloadPresentsWithoutNavigatingAndCompletesOnce
{
	[self assertInvalidNotificationResponseWithUserInfo:
		@{ BPOutdatedNotificationTargetKey: @"future-target" }];
}

- (void)testValidNotificationResponsesRouteFormulaeAndCasks
{
	BPAppDelegate *delegate = [[BPAppDelegate alloc] init];
	BPNotificationPresentationSpy *presentation = [[BPNotificationPresentationSpy alloc] init];
	BPNotificationNavigationTargetSpy *target = [[BPNotificationNavigationTargetSpy alloc] init];
	delegate.notificationPresenter = presentation;
	delegate.notificationNavigationTarget = target;

	for (NSString *destination in @[ BPOutdatedNotificationTargetFormulae, BPOutdatedNotificationTargetCasks ])
	{
		BPNotificationResponseStub *response = [[BPNotificationResponseStub alloc] init];
		response.userInfo = @{ BPOutdatedNotificationTargetKey: destination };
		[delegate userNotificationCenter:nil
		   didReceiveNotificationResponse:(UNNotificationResponse *)response
				withCompletionHandler:^{}];
	}

	XCTAssertEqual(target.formulaeNavigationCount, 1u);
	XCTAssertEqual(target.caskNavigationCount, 1u);
	XCTAssertEqual(presentation.windowCount, 2u);
}

- (void)testLaunchPendingNotificationActionIsConsumedExactlyOnce
{
	BPAppDelegate *delegate = [[BPAppDelegate alloc] init];
	BPNotificationPresentationSpy *presentation = [[BPNotificationPresentationSpy alloc] init];
	delegate.notificationPresenter = presentation;
	BPNotificationResponseStub *response = [[BPNotificationResponseStub alloc] init];
	response.userInfo = @{ BPOutdatedNotificationTargetKey: BPOutdatedNotificationTargetCasks };
	[delegate userNotificationCenter:nil
	   didReceiveNotificationResponse:(UNNotificationResponse *)response
			withCompletionHandler:^{}];

	BPNotificationNavigationTargetSpy *firstTarget = [[BPNotificationNavigationTargetSpy alloc] init];
	delegate.notificationNavigationTarget = firstTarget;
	XCTAssertEqual(firstTarget.caskNavigationCount, 1u);

	BPNotificationNavigationTargetSpy *laterTarget = [[BPNotificationNavigationTargetSpy alloc] init];
	delegate.notificationNavigationTarget = laterTarget;
	XCTAssertEqual(laterTarget.caskNavigationCount, 0u, @"the pending action must be consumed, not replayed");
	XCTAssertEqual(presentation.windowCount, 1u, @"draining navigation must not present the response twice");
}

- (void)testNotificationResponseMarshalsAllUIPresentationAndNavigationToMainThreadAndCompletesOnce
{
	BPAppDelegate *delegate = [[BPAppDelegate alloc] init];
	BPNotificationPresentationSpy *presentation = [[BPNotificationPresentationSpy alloc] init];
	BPNotificationNavigationTargetSpy *target = [[BPNotificationNavigationTargetSpy alloc] init];
	delegate.notificationPresenter = presentation;
	delegate.notificationNavigationTarget = target;
	BPNotificationResponseStub *response = [[BPNotificationResponseStub alloc] init];
	response.userInfo = @{ BPOutdatedNotificationTargetKey: BPOutdatedNotificationTargetFormulae };
	XCTestExpectation *completed = [self expectationWithDescription:@"notification response completed"];
	__block NSUInteger completionCount = 0;

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		[delegate userNotificationCenter:nil
		   didReceiveNotificationResponse:(UNNotificationResponse *)response
				withCompletionHandler:^{
			completionCount += 1;
			[completed fulfill];
		}];
	});

	[self waitForExpectations:@[ completed ] timeout:2.0];
	XCTAssertEqual(completionCount, 1u);
	XCTAssertTrue(presentation.calledOnMainThread);
	XCTAssertTrue(target.calledOnMainThread);
	XCTAssertEqual(presentation.cleanupCount, 1u);
	XCTAssertEqual(presentation.activationCount, 1u);
	XCTAssertEqual(presentation.windowCount, 1u);
	XCTAssertEqual(target.formulaeNavigationCount, 1u);
}

- (void)testNotificationNavigationContractIncludesBothDestinations
{
	struct objc_method_description formulae = protocol_getMethodDescription(
		@protocol(BPNotificationNavigation), @selector(showOutdatedFormulae:), YES, YES);
	struct objc_method_description casks = protocol_getMethodDescription(
		@protocol(BPNotificationNavigation), @selector(showOutdatedCasks:), YES, YES);

	XCTAssertTrue(formulae.name != NULL);
	XCTAssertTrue(casks.name != NULL);
}

@end
