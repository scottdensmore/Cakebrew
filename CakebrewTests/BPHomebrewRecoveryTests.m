#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "BPHomebrewInterface.h"
#import "BPHomebrewManager.h"

@interface BPHomebrewInterface (RecoveryTesting)
- (instancetype)initUniqueInstance;
- (NSString *)getValidUserShellPath;
@end

@interface BPHomebrewManager (RecoveryTesting)
- (instancetype)initUniqueInstance;
- (BPHomebrewInterface *)homebrewInterface;
- (BOOL)loadAllFormulaeCaches;
- (void)storeAllFormulaeCaches;
@end

@interface BPRecoveryShellInterface : BPHomebrewInterface
@property (copy) NSString *shell;
@end
@implementation BPRecoveryShellInterface
- (NSString *)getValidUserShellPath { return self.shell; }
@end

@interface BPRecoveryFixtureInterface : BPHomebrewInterface
@property BPHomebrewDiscoveryResult nextResult;
@property NSUInteger discoveryCalls;
@property NSUInteger listCalls;
@property (strong) dispatch_semaphore_t holdDiscovery;
@property (copy) void (^onDiscovery)(void);
@end
@implementation BPRecoveryFixtureInterface
- (BPHomebrewDiscoveryResult)discoverHomebrew
{
	self.discoveryCalls++;
	if (self.onDiscovery) self.onDiscovery();
	if (self.holdDiscovery) dispatch_semaphore_wait(self.holdDiscovery, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
	return self.nextResult;
}
- (NSArray *)listMode:(BPListMode)mode
{
	@synchronized (self) { self.listCalls++; }
	return @[[BPFormula formulaWithName:@"recovered"]];
}
- (NSArray *)listServices
{
	@synchronized (self) { self.listCalls++; }
	return @[];
}
@end

@interface BPRecoveryFixtureManager : BPHomebrewManager
@property (strong) BPRecoveryFixtureInterface *fixture;
@end
@implementation BPRecoveryFixtureManager
+ (id)allocWithZone:(NSZone *)zone { return class_createInstance(self, 0); }
- (BPHomebrewInterface *)homebrewInterface { return self.fixture; }
- (BOOL)loadAllFormulaeCaches { return NO; }
- (void)storeAllFormulaeCaches {}
@end

@interface BPHomebrewRecoveryTests : XCTestCase <BPHomebrewManagerDelegate>
@property (strong) BPRecoveryFixtureManager *manager;
@property (copy) void (^onResult)(BOOL);
@property (copy) void (^onFinish)(void);
@property NSUInteger finishes;
@end

@implementation BPHomebrewRecoveryTests

- (void)setUp
{
	[super setUp];
	self.manager = [[BPRecoveryFixtureManager allocWithZone:NULL] initUniqueInstance];
	self.manager.fixture = [[BPRecoveryFixtureInterface allocWithZone:NULL] initUniqueInstance];
	self.manager.delegate = self;
}

- (void)homebrewManager:(BPHomebrewManager *)manager shouldDisplayNoBrewMessage:(BOOL)missing
{
	XCTAssertTrue(NSThread.isMainThread);
	if (self.onResult) self.onResult(missing);
}
- (void)homebrewManagerFinishedUpdating:(BPHomebrewManager *)manager
{
	self.finishes++;
	if (self.onFinish) self.onFinish();
}
- (void)homebrewManager:(BPHomebrewManager *)manager didUpdateSearchResults:(NSArray *)results {}

- (NSString *)discoveryOutput:(NSString *)path
{
	return [NSString stringWithFormat:@"Login banner\n+++++Cakebrew Discovery+++++\n%@\n+++++Cakebrew Discovery End+++++\n", path];
}

- (void)testNonzeroExitCannotTurnAnErrorMessageIntoAnInstallation
{
	XCTAssertEqual([BPHomebrewInterface discoveryResultForOutput:@"brew not found\n" exitStatus:1], BPHomebrewDiscoveryCheckFailed);
	XCTAssertEqual([BPHomebrewInterface discoveryResultForOutput:[self discoveryOutput:@"/usr/bin/true"] exitStatus:2], BPHomebrewDiscoveryCheckFailed);
}

- (void)testMissingCommandIsDistinctFromAnUnusableCheck
{
	XCTAssertEqual([BPHomebrewInterface discoveryResultForOutput:[self discoveryOutput:@""] exitStatus:1], BPHomebrewDiscoveryMissing);
	XCTAssertEqual([BPHomebrewInterface discoveryResultForOutput:@"" exitStatus:0], BPHomebrewDiscoveryCheckFailed);
}

- (void)testOnlyAnAbsoluteExecutableFileInsideTheMarkersIsAvailable
{
	XCTAssertEqual([BPHomebrewInterface discoveryResultForOutput:[self discoveryOutput:@"/usr/bin/true"] exitStatus:0], BPHomebrewDiscoveryAvailable);
	for (NSString *path in @[@"brew", @"brew not found", @"/usr/bin", @"/etc/shells", @"/no/such/brew", @"/usr/bin/true\n/usr/bin/false"]) {
		XCTAssertEqual([BPHomebrewInterface discoveryResultForOutput:[self discoveryOutput:path] exitStatus:0], BPHomebrewDiscoveryCheckFailed, @"%@", path);
	}
}

- (void)testOfficialInstallationURLIsHTTPS
{
	XCTAssertEqualObjects([BPHomebrewInterface installationURL].absoluteString, @"https://brew.sh");
}

- (void)testMockOverridesTheEntireDiscoveryExecutionBoundary
{
	Class mock = NSClassFromString(@"BPMockHomebrewInterface");
	XCTAssertNotNil(mock);
	XCTAssertNotEqual(class_getInstanceMethod(mock, @selector(discoverHomebrew)),
		class_getInstanceMethod(BPHomebrewInterface.class, @selector(discoverHomebrew)));
}

- (void)testRecoveryViewWiresBothActionsAndWrapsItsMessage
{
	NSString *root = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	NSURL *url = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"Cakebrew/Views/Base.lproj/Disabled.xib"]];
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:NULL];
	XCTAssertNotNil(document);
	for (NSString *selector in @[@"retry:", @"openInstallationInstructions:"]) {
		NSString *query = [NSString stringWithFormat:@"//button/connections/action[@selector='%@' and @target='-2']", selector];
		XCTAssertEqual([document nodesForXPath:query error:NULL].count, 1u);
	}
	XCTAssertEqual([document nodesForXPath:@"//textFieldCell[@id='sdR-dW-MDv' and @wraps='YES']" error:NULL].count, 1u);
}

- (void)testDiscoveryExecutesTheTaskAndUsesItsStatusAndMarkedOutput
{
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
	NSFileManager *files = NSFileManager.defaultManager;
	XCTAssertTrue([files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL]);
	BPRecoveryShellInterface *interface = [[BPRecoveryShellInterface allocWithZone:NULL] initUniqueInstance];
	interface.shell = [directory stringByAppendingPathComponent:@"shell"];
	@try {
		for (NSNumber *status in @[@0, @2]) {
			NSString *script = [NSString stringWithFormat:@"#!/bin/sh\nprintf 'Login banner\\n+++++Cakebrew Discovery+++++\\n/usr/bin/true\\n+++++Cakebrew Discovery End+++++\\n'\nexit %@\n", status];
			XCTAssertTrue([script writeToFile:interface.shell atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
			XCTAssertTrue([files setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:interface.shell error:NULL]);
			XCTAssertEqual([interface discoverHomebrew], status.intValue == 0 ? BPHomebrewDiscoveryAvailable : BPHomebrewDiscoveryCheckFailed);
		}
		interface.shell = nil;
		XCTAssertEqual([interface discoverHomebrew], BPHomebrewDiscoveryInvalidShell);
	} @finally {
		[files removeItemAtPath:directory error:NULL];
	}
}

- (void)testDiscoveryCommandFindsAnExecutableWithoutRunningItAndHandlesMissingPATH
{
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
	NSFileManager *files = NSFileManager.defaultManager;
	XCTAssertTrue([files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL]);
	BPRecoveryShellInterface *interface = [[BPRecoveryShellInterface allocWithZone:NULL] initUniqueInstance];
	interface.shell = [directory stringByAppendingPathComponent:@"shell"];
	NSString *brew = [directory stringByAppendingPathComponent:@"brew"];
	@try {
		// Execute the production command ($3 after -l -c) with a fixture-only
		// PATH. A login banner must not pollute discovery. The fake brew exits
		// 97 if run: discovering it must not execute it.
		NSString *wrapper = [NSString stringWithFormat:@"#!/bin/sh\nprintf 'fixture login banner\\n'\nPATH='%@'; export PATH\nexec /bin/sh -c \"$3\"\n", directory];
		XCTAssertTrue([wrapper writeToFile:interface.shell atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
		XCTAssertTrue([files setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:interface.shell error:NULL]);
		XCTAssertTrue([@"#!/bin/sh\nexit 97\n" writeToFile:brew atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
		XCTAssertTrue([files setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:brew error:NULL]);
		XCTAssertEqual([interface discoverHomebrew], BPHomebrewDiscoveryAvailable);
		XCTAssertTrue([files removeItemAtPath:brew error:NULL]);
		XCTAssertEqual([interface discoverHomebrew], BPHomebrewDiscoveryMissing);
	} @finally {
		[files removeItemAtPath:directory error:NULL];
	}
}

- (void)testFailedDiscoveryHasNoListFanoutAndPersistentRetryChecksAgain
{
	self.manager.fixture.nextResult = BPHomebrewDiscoveryMissing;
	for (NSUInteger attempt = 1; attempt <= 2; attempt++) {
		XCTestExpectation *failed = [self expectationWithDescription:@"discovery failed"];
		self.onResult = ^(BOOL missing) { XCTAssertTrue(missing); [failed fulfill]; };
		[self.manager retryHomebrewDiscovery];
		[self waitForExpectations:@[failed] timeout:3];
		XCTAssertEqual(self.manager.discoveryResult, BPHomebrewDiscoveryMissing);
		XCTAssertFalse(self.manager.checkingHomebrew);
		XCTAssertEqual(self.manager.fixture.discoveryCalls, attempt);
		XCTAssertEqual(self.manager.fixture.listCalls, 0u);
		XCTAssertEqual(self.finishes, 0u);
	}
}

- (void)testRetryIsSingleFlightAndRecoveryRunsExactlyOneNormalPipeline
{
	self.manager.fixture.nextResult = BPHomebrewDiscoveryMissing;
	XCTestExpectation *failed = [self expectationWithDescription:@"initial failure"];
	self.onResult = ^(BOOL missing) { XCTAssertTrue(missing); [failed fulfill]; };
	[self.manager reloadFromInterfaceRebuildingCache:NO];
	[self waitForExpectations:@[failed] timeout:3];

	self.manager.fixture.nextResult = BPHomebrewDiscoveryAvailable;
	self.manager.fixture.holdDiscovery = dispatch_semaphore_create(0);
	XCTestExpectation *checking = [self expectationWithDescription:@"retry begins off-main"];
	self.manager.fixture.onDiscovery = ^{ XCTAssertFalse(NSThread.isMainThread); [checking fulfill]; };
	XCTestExpectation *recovered = [self expectationWithDescription:@"available"];
	self.onResult = ^(BOOL missing) { XCTAssertFalse(missing); [recovered fulfill]; };
	XCTestExpectation *finished = [self expectationWithDescription:@"one pipeline finished"];
	self.onFinish = ^{ [finished fulfill]; };
	[self.manager retryHomebrewDiscovery];
	[self waitForExpectations:@[checking] timeout:3];
	XCTAssertTrue(self.manager.checkingHomebrew);
	[self.manager retryHomebrewDiscovery];
	[self.manager reloadFromInterfaceRebuildingCache:YES];
	XCTAssertEqual(self.manager.fixture.discoveryCalls, 2u);
	dispatch_semaphore_signal(self.manager.fixture.holdDiscovery);
	[self waitForExpectations:@[recovered, finished] timeout:3];
	XCTAssertEqual(self.manager.discoveryResult, BPHomebrewDiscoveryAvailable);
	XCTAssertFalse(self.manager.checkingHomebrew);
	XCTAssertEqual(self.manager.fixture.discoveryCalls, 2u);
	XCTAssertEqual(self.manager.fixture.listCalls, 10u);
	XCTAssertEqual(self.finishes, 1u);
	XCTAssertEqualObjects(self.manager.installedFormulae.firstObject.name, @"recovered");
}

@end
