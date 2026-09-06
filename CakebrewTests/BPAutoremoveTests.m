#import <XCTest/XCTest.h>
#import "BPHomebrewInterface.h"
#import "BPAutoremovePreview.h"
#import "BPAutoremoveOperation.h"
#import "BPHomebrewManager.h"
#import "BPService.h"
#import <objc/runtime.h>

@interface BPHomebrewManager (CB150Testing)
- (instancetype)initUniqueInstance;
@end
@interface CB150RefreshInterface : BPHomebrewInterface
@property (strong) NSMutableArray *modes;
@property NSUInteger serviceCalls;
@property BOOL fail;
@property (copy) void (^discoveryEntered)(void);
@property (strong) dispatch_semaphore_t finishDiscovery;
@end
@implementation CB150RefreshInterface
- (BPHomebrewDiscoveryResult)discoverHomebrew
{
	if (self.discoveryEntered) self.discoveryEntered();
	if (self.finishDiscovery) dispatch_semaphore_wait(self.finishDiscovery, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
	return BPHomebrewDiscoveryMissing;
}
- (NSArray *)listMode:(BPListMode)mode { [self.modes addObject:@(mode)]; return self.fail ? nil : @[]; }
- (NSArray *)listServices { self.serviceCalls++; return self.fail ? nil : @[]; }
- (NSArray *)listModeForRemovalRefresh:(BPListMode)mode { return [self listMode:mode]; }
- (NSArray *)listServicesForRemovalRefresh { return [self listServices]; }
@end
@interface CB150Observer : NSObject
@property (copy) void (^observed)(void);
@end
@implementation CB150Observer
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context { self.observed(); }
@end
@interface CB150Manager : BPHomebrewManager
@property (strong) BPHomebrewInterface *fixtureInterface;
@end
@implementation CB150Manager
- (BPHomebrewInterface *)homebrewInterface { return self.fixtureInterface; }
@end

@interface BPHomebrewInterface (CB150Testing)
- (instancetype)initUniqueInstance;
- (NSArray<BPFormula *> *)listModeForRemovalRefresh:(BPListMode)mode;
- (NSArray<BPService *> *)listServicesForRemovalRefresh;
- (NSArray *)formatAutoremoveArguments:(NSArray *)arguments;
- (int)executeAutoremoveArguments:(NSArray *)arguments progress:(NSProgress *)progress output:(void (^)(NSString *))output;
@end
@interface CB150Interface : BPHomebrewInterface
@property (strong) BPAutoremovePreview *preview;
@property NSUInteger previewCalls;
@property NSUInteger removalCalls;
@property (copy) NSArray *removed;
@property BOOL removalSuccess;
@end
@implementation CB150Interface
- (BPAutoremovePreview *)previewAutoremoveWithProgress:(NSProgress *)progress { self.previewCalls++; return self.preview; }
- (BOOL)removeUnusedFormulae:(NSArray *)names progress:(NSProgress *)progress output:(void (^)(NSString *))output
{
	XCTAssertFalse(NSThread.isMainThread); self.removalCalls++; self.removed = names;
	if (output) output(@"fixture stream");
	return self.removalSuccess;
}
@end
@interface CB150CommandInterface : BPHomebrewInterface
@property (copy) NSArray *arguments;
@property (copy) NSString *fixture;
@property int status;
@end
@implementation CB150CommandInterface
- (int)executeAutoremoveArguments:(NSArray *)arguments progress:(NSProgress *)progress output:(void (^)(NSString *))output
{ self.arguments = arguments; if (output) output(self.fixture ?: @""); return self.status; }
@end
@interface CB150TaskInterface : BPHomebrewInterface
@property (copy) NSString *script;
@property (copy) void (^formatting)(void);
@end
@implementation CB150TaskInterface
- (NSArray *)formatAutoremoveArguments:(NSArray *)arguments
{ if (self.formatting) self.formatting(); return @[@"-c", self.script]; }
@end

// Exercise BPTask and the real status-preserving read boundary, not a nil-returning manager fake.
@interface CB150RefreshShellInterface : BPHomebrewInterface
@property (copy) NSDictionary<NSString *, NSString *> *outputs;
@property (copy) NSDictionary<NSString *, NSNumber *> *statuses;
@property (strong) NSMutableArray<NSString *> *commands;
@end
@implementation CB150RefreshShellInterface
- (NSArray *)formatArguments:(NSArray *)arguments sendOutputId:(BOOL)marker
{
	NSString *key = [arguments componentsJoinedByString:@" "];
	[self.commands addObject:key];
	return @[@"-c", @"printf 'login banner\\n+++++Cakebrew+++++\\n'; printf '%s' \"$1\"; exit \"$2\"",
		@"fixture", self.outputs[key] ?: @"", [self.statuses[key] ?: @0 stringValue]];
}
@end


@interface BPAutoremoveTests : XCTestCase
@end
@implementation BPAutoremoveTests

- (CB150RefreshShellInterface *)refreshShellInterface
{
	CB150RefreshShellInterface *interface = [[CB150RefreshShellInterface allocWithZone:NULL] initUniqueInstance];
	interface.brewTransport = kBPBrewTransportDirect;
	[interface setValue:@"/bin/sh" forKey:@"path_shell"];
	interface.commands = [NSMutableArray array];
	return interface;
}

- (void)testAutoremoveRealFailedRefreshPreservesListsAndReportsIncomplete
{
	CB150Manager *manager = [class_createInstance(CB150Manager.class, 0) initUniqueInstance];
	CB150RefreshShellInterface *interface = [self refreshShellInterface];
	manager.fixtureInterface = interface;
	interface.outputs = @{@"leaves": @"freshleaf\n", @"outdated --verbose": @"partial (1) < 2\n"};
	interface.statuses = @{@"list --versions": @7, @"outdated --verbose": @8, @"services list --json": @9};
	NSArray *kept = @[[BPFormula formulaWithName:@"kept"]];
	manager.installedFormulae = kept; manager.leavesFormulae = kept;
	[manager publishList:kept forMode:kBPListOutdated generation:manager.currentReloadGeneration];
	[manager publishList:kept forMode:kBPListOutdatedCasks generation:manager.currentReloadGeneration];
	NSArray *services = [BPService servicesFromJSONString:@"[{\"name\":\"kept-service\"}]"];
	manager.services = services;
	__block NSUInteger snapshots = 0;
	id observer = [NSNotificationCenter.defaultCenter addObserverForName:BPHomebrewManagerDidPublishOutdatedSnapshotNotification object:manager queue:nil usingBlock:^(NSNotification *note) { snapshots++; }];
	XCTestExpectation *done = [self expectationWithDescription:@"failed transport reports incomplete refresh"];
	[manager refreshFormulaStateAfterRemovalWithCompletion:^(BOOL ok) { XCTAssertFalse(ok, @"The sheet must receive NO to show its incomplete-refresh warning"); [done fulfill]; }];
	[self waitForExpectations:@[done] timeout:5];
	[NSNotificationCenter.defaultCenter removeObserver:observer];
	XCTAssertEqualObjects(manager.installedFormulae, kept);
	XCTAssertEqualObjects(manager.outdatedFormulae, kept);
	XCTAssertEqualObjects(manager.services, services);
	XCTAssertEqualObjects(manager.leavesFormulae.firstObject.name, @"freshleaf");
	XCTAssertEqual(snapshots, 0u, @"A failed outdated query cannot publish a new zero or partial count");
	XCTAssertEqualObjects(interface.commands, (@[@"list --versions", @"leaves", @"outdated --verbose", @"services list --json"]));
}

- (void)testAutoremoveRefreshReadsPreserveProcessFailureAndSuccessfulEmptyResults
{
	CB150RefreshShellInterface *interface = [self refreshShellInterface];
	NSArray *keys = @[@"list --versions", @"leaves", @"outdated --verbose"];
	NSArray *modes = @[@(kBPListInstalled), @(kBPListLeaves), @(kBPListOutdated)];
	NSArray *samples = @[@"newformula 1.2\n", @"newleaf\n", @"newformula (1.0) < 2.0\n"];
	for (NSUInteger i = 0; i < keys.count; i++) {
		for (NSString *output in @[@"", samples[i], @"failure text\n"]) {
			interface.outputs = @{keys[i]: output}; interface.statuses = @{keys[i]: @7};
			XCTAssertNil([interface listModeForRemovalRefresh:[modes[i] integerValue]]);
		}
		interface.statuses = @{}; interface.outputs = @{};
		XCTAssertEqualObjects([interface listModeForRemovalRefresh:[modes[i] integerValue]], @[]);
		interface.outputs = @{keys[i]: samples[i]};
		XCTAssertEqual([interface listModeForRemovalRefresh:[modes[i] integerValue]].count, 1u);
	}
	interface.outputs = @{@"services list --json": @"[]"}; interface.statuses = @{@"services list --json": @7};
	XCTAssertNil([interface listServicesForRemovalRefresh]);
	interface.statuses = @{};
	XCTAssertEqualObjects([interface listServicesForRemovalRefresh], @[]);
	NSUInteger requests = interface.commands.count;
	XCTAssertNil([interface listModeForRemovalRefresh:kBPListAllCasks]);
	interface.brewTransport = kBPBrewTransportHelper;
	XCTAssertNil([interface listModeForRemovalRefresh:kBPListInstalled]);
	XCTAssertNil([interface listServicesForRemovalRefresh]);
	XCTAssertEqual(interface.commands.count, requests, @"Unsupported reads cannot dispatch or take helper ownership");
}

- (void)testAutoremoveServicesRejectMalformedSuccessfulReadsWithoutClearingPriorState
{
	NSArray *invalid = @[@"", @"not JSON", @"{}", @"[null]", @"[{}]", @"[{\"name\":3}]", @"[{\"name\":\"\"}]",
		@"[{\"name\":\"redis\",\"pid\":\"bad\"}]", @"[{\"name\":\"redis\",\"user\":4}]", @"[{\"name\":\"redis\",\"status\":{}}]",
		@"[{\"name\":\"valid\"},{}]"];
	for (NSString *output in invalid) {
		CB150Manager *manager = [class_createInstance(CB150Manager.class, 0) initUniqueInstance];
		CB150RefreshShellInterface *interface = [self refreshShellInterface];
		manager.fixtureInterface = interface;
		interface.outputs = @{@"services list --json": output};
		NSArray *kept = [BPService servicesFromJSONString:@"[{\"name\":\"kept\"}]"];
		manager.services = kept;
		XCTestExpectation *done = [self expectationWithDescription:@"malformed services reject refresh"];
		[manager refreshFormulaStateAfterRemovalWithCompletion:^(BOOL ok) { XCTAssertFalse(ok, @"%@", output); [done fulfill]; }];
		[self waitForExpectations:@[done] timeout:5];
		XCTAssertEqualObjects(manager.services, kept, @"%@", output);
	}
}

- (void)testAutoremoveSuccessfulEmptyRefreshClearsListsAndPreservesKnownCaskCount
{
	CB150Manager *manager = [class_createInstance(CB150Manager.class, 0) initUniqueInstance];
	CB150RefreshShellInterface *interface = [self refreshShellInterface]; manager.fixtureInterface = interface;
	interface.outputs = @{@"services list --json": @"[]"};
	NSArray *kept = @[[BPFormula formulaWithName:@"old"]];
	manager.installedFormulae = kept; manager.leavesFormulae = kept; manager.outdatedFormulae = kept;
	manager.services = [BPService servicesFromJSONString:@"[{\"name\":\"old\"}]"];
	[manager publishList:kept forMode:kBPListOutdatedCasks generation:manager.currentReloadGeneration];
	__block NSDictionary *snapshot;
	id observer = [NSNotificationCenter.defaultCenter addObserverForName:BPHomebrewManagerDidPublishOutdatedSnapshotNotification object:manager queue:nil usingBlock:^(NSNotification *note) { snapshot = note.userInfo; }];
	XCTestExpectation *done = [self expectationWithDescription:@"genuine empty lists succeed"];
	[manager refreshFormulaStateAfterRemovalWithCompletion:^(BOOL ok) { XCTAssertTrue(ok); [done fulfill]; }];
	[self waitForExpectations:@[done] timeout:5];
	[NSNotificationCenter.defaultCenter removeObserver:observer];
	XCTAssertEqualObjects(manager.installedFormulae, @[]); XCTAssertEqualObjects(manager.leavesFormulae, @[]);
	XCTAssertEqualObjects(manager.outdatedFormulae, @[]); XCTAssertEqualObjects(manager.services, @[]);
	XCTAssertEqualObjects(snapshot[BPOutdatedSnapshotFormulaeCountKey], @0);
	XCTAssertEqualObjects(snapshot[BPOutdatedSnapshotCaskCountKey], @1);
	interface.outputs = @{@"services list --json": @"[{\"name\":\"redis\",\"status\":\"future\",\"pid\":null,\"user\":null,\"new_field\":{}}]"};
	NSArray<BPService *> *services = [interface listServicesForRemovalRefresh];
	XCTAssertEqual(services.count, 1u); XCTAssertEqual(services.firstObject.status, kBPServiceStatusUnknown);
}

- (void)testAutoremoveInvalidReviewAndHelperNeverReachCommands
{
	for (NSNumber *helper in @[@NO, @YES]) {
		CB150Interface *interface = [[CB150Interface allocWithZone:NULL] initUniqueInstance];
		if (helper.boolValue) interface.brewTransport = kBPBrewTransportHelper;
		BPAutoremovePreview *preview = [BPAutoremovePreview previewWithOutput:helper.boolValue ? @"==> Would autoremove 1 unneeded formula:\nlibfoo\n" : @"unexpected" succeeded:YES];
		BPAutoremoveOperation *operation = [[BPAutoremoveOperation alloc] initWithPreview:preview interface:interface];
		XCTestExpectation *done = [self expectationWithDescription:@"unsafe request rejected"];
		[operation startWithOutput:nil completion:^(BOOL success, BOOL cancelled, BOOL attempted, NSString *message) {
			XCTAssertFalse(success); XCTAssertFalse(cancelled); XCTAssertFalse(attempted); [done fulfill];
		}];
		[self waitForExpectations:@[done] timeout:5];
		XCTAssertEqual(interface.previewCalls, 0u);
		XCTAssertEqual(interface.removalCalls, 0u);
	}
}

- (void)testAutoremoveDeferredRefreshCompletesWhenDiscoveryFails
{
	CB150Manager *manager = [class_createInstance(CB150Manager.class, 0) initUniqueInstance];
	CB150RefreshInterface *interface = [[CB150RefreshInterface allocWithZone:NULL] initUniqueInstance];
	interface.modes = [NSMutableArray array]; manager.fixtureInterface = interface;
	interface.finishDiscovery = dispatch_semaphore_create(0);
	XCTestExpectation *entered = [self expectationWithDescription:@"discovery entered"];
	interface.discoveryEntered = ^{ [entered fulfill]; };
	[manager reloadFromInterfaceRebuildingCache:NO];
	[self waitForExpectations:@[entered] timeout:5];
	XCTestExpectation *done = [self expectationWithDescription:@"deferred refresh reports unavailable"];
	[manager refreshFormulaStateAfterRemovalWithCompletion:^(BOOL ok) { XCTAssertFalse(ok); [done fulfill]; }];
	dispatch_semaphore_signal(interface.finishDiscovery);
	[self waitForExpectations:@[done] timeout:2];
	XCTAssertEqual(interface.modes.count, 0u);
}

- (void)testAutoremoveLateCancellationCannotContradictItsResult
{
	for (NSUInteger i = 0; i < 5; i++) {
		CB150Interface *interface = [[CB150Interface allocWithZone:NULL] initUniqueInstance];
		interface.preview = [BPAutoremovePreview previewWithOutput:@"==> Would autoremove 1 unneeded formula:\nlibfoo\n" succeeded:YES];
		interface.removalSuccess = YES;
		BPAutoremoveOperation *operation = [[BPAutoremoveOperation alloc] initWithPreview:interface.preview interface:interface];
		XCTestExpectation *done = [self expectationWithDescription:@"late cancellation"];
		[operation startWithOutput:^(NSString *chunk) { if ([chunk containsString:@"fixture stream"]) [operation cancel]; }
			completion:^(BOOL success, BOOL cancelled, BOOL attempted, NSString *message) {
				XCTAssertTrue(attempted);
				if (cancelled) { XCTAssertFalse(success); XCTAssertTrue([message containsString:@"cancelled"]); }
				else XCTAssertTrue(success);
				[done fulfill];
			}];
		[self waitForExpectations:@[done] timeout:5];
	}
}

- (void)testAutoremoveFailedRefreshRetainsListsAndNeverInventsZeroCasks
{
	CB150Manager *manager = [class_createInstance(CB150Manager.class, 0) initUniqueInstance];
	CB150RefreshInterface *interface = [[CB150RefreshInterface allocWithZone:NULL] initUniqueInstance];
	interface.modes = [NSMutableArray array]; interface.fail = YES; manager.fixtureInterface = interface;
	NSArray *kept = @[[BPFormula formulaWithName:@"kept"]];
	manager.installedFormulae = kept; manager.leavesFormulae = kept; manager.outdatedFormulae = kept;
	__block NSUInteger notifications = 0;
	id observer = [NSNotificationCenter.defaultCenter addObserverForName:BPHomebrewManagerDidPublishOutdatedSnapshotNotification object:manager queue:nil usingBlock:^(NSNotification *note) { notifications++; }];
	XCTestExpectation *done = [self expectationWithDescription:@"failed refresh completes"];
	[manager refreshFormulaStateAfterRemovalWithCompletion:^(BOOL succeeded) { XCTAssertFalse(succeeded); [done fulfill]; }];
	[self waitForExpectations:@[done] timeout:5];
	XCTAssertEqualObjects(manager.installedFormulae, kept);
	XCTAssertEqualObjects(manager.leavesFormulae, kept);
	XCTAssertEqualObjects(manager.outdatedFormulae, kept);
	XCTAssertNil(manager.outdatedCasks); XCTAssertEqual(notifications, 0u);
	[NSNotificationCenter.defaultCenter removeObserver:observer];
}

- (void)testAutoremoveRefreshCoalescesBehindAnExistingReload
{
	CB150Manager *manager = [class_createInstance(CB150Manager.class, 0) initUniqueInstance];
	CB150RefreshInterface *interface = [[CB150RefreshInterface allocWithZone:NULL] initUniqueInstance];
	interface.modes = [NSMutableArray array]; manager.fixtureInterface = interface;
	[manager setValue:@YES forKey:@"reloadInFlight"];
	XCTestExpectation *first = [self expectationWithDescription:@"first deferred request"];
	XCTestExpectation *second = [self expectationWithDescription:@"second deferred request"];
	[manager refreshFormulaStateAfterRemovalWithCompletion:^(BOOL ok) { XCTAssertTrue(ok); [first fulfill]; }];
	[manager refreshFormulaStateAfterRemovalWithCompletion:^(BOOL ok) { XCTAssertTrue(ok); [second fulfill]; }];
	XCTAssertEqual(interface.modes.count, 0u);
	[manager setValue:@NO forKey:@"reloadInFlight"];
	[manager refreshFormulaStateAfterRemovalWithCompletion:nil];
	[self waitForExpectations:@[first, second] timeout:5];
	XCTAssertEqual(interface.modes.count, 3u);
	XCTAssertEqual(interface.serviceCalls, 1u);
}

- (void)testAutoremoveRefreshRejectsReentrantSupersededPublications
{
	CB150Manager *manager = [class_createInstance(CB150Manager.class, 0) initUniqueInstance];
	CB150RefreshInterface *interface = [[CB150RefreshInterface allocWithZone:NULL] initUniqueInstance];
	interface.modes = [NSMutableArray array]; manager.fixtureInterface = interface;
	NSArray *kept = @[[BPFormula formulaWithName:@"kept"]];
	manager.leavesFormulae = kept;
	CB150Observer *observer = [CB150Observer new];
	observer.observed = ^{ [manager cancelReload]; };
	[manager addObserver:observer forKeyPath:@"installedFormulae" options:0 context:NULL];
	XCTestExpectation *done = [self expectationWithDescription:@"superseded refresh completes"];
	[manager refreshFormulaStateAfterRemovalWithCompletion:^(BOOL ok) { XCTAssertFalse(ok); [done fulfill]; }];
	[self waitForExpectations:@[done] timeout:5];
	[manager removeObserver:observer forKeyPath:@"installedFormulae"];
	XCTAssertEqualObjects(manager.leavesFormulae, kept);
	XCTAssertNil(manager.outdatedFormulae);
	XCTAssertNil(manager.services);
}

- (void)testAutoremoveRefreshPreservesCasksAndPublishesCombinedOutdatedSnapshot
{
	CB150Manager *manager = [class_createInstance(CB150Manager.class, 0) initUniqueInstance];
	CB150RefreshInterface *interface = [[CB150RefreshInterface allocWithZone:NULL] initUniqueInstance];
	interface.modes = [NSMutableArray array]; manager.fixtureInterface = interface;
	NSArray *casks = @[[BPFormula formulaWithName:@"kept-cask"]];
	[manager publishList:casks forMode:kBPListOutdatedCasks generation:manager.currentReloadGeneration];
	NSUInteger generation = manager.currentReloadGeneration;
	__block NSDictionary *snapshot;
	id observer = [NSNotificationCenter.defaultCenter addObserverForName:BPHomebrewManagerDidPublishOutdatedSnapshotNotification object:manager queue:nil usingBlock:^(NSNotification *note) { snapshot = note.userInfo; }];
	XCTestExpectation *done = [self expectationWithDescription:@"targeted refresh"];
	[manager refreshFormulaStateAfterRemovalWithCompletion:^(BOOL succeeded) { XCTAssertTrue(succeeded); [done fulfill]; }];
	[self waitForExpectations:@[done] timeout:5];
	[NSNotificationCenter.defaultCenter removeObserver:observer];
	XCTAssertEqualObjects(interface.modes, (@[@(kBPListInstalled), @(kBPListLeaves), @(kBPListOutdated)]));
	XCTAssertEqual(interface.serviceCalls, 1u);
	XCTAssertEqualObjects(manager.outdatedCasks, casks);
	XCTAssertEqual(manager.currentReloadGeneration, generation + 1);
	XCTAssertEqualObjects(snapshot[BPOutdatedSnapshotFormulaeCountKey], @0);
	XCTAssertEqualObjects(snapshot[BPOutdatedSnapshotCaskCountKey], @1);
}

- (void)testAutoremovePreservesStderrBeforeMarkerAndOwnsCancellation
{
	CB150TaskInterface *interface = [[CB150TaskInterface allocWithZone:NULL] initUniqueInstance];
	[interface setValue:@"/bin/sh" forKey:@"path_shell"];
	interface.script = @"printf 'Warning: fixture warning\\n' >&2; /bin/sleep 0.1; printf '\\n+++++Cakebrew Autoremove+++++\\n'";
	BPAutoremovePreview *preview = [interface previewAutoremoveWithProgress:[NSProgress progressWithTotalUnitCount:1]];
	XCTAssertFalse(preview.valid);
	XCTAssertTrue([preview.rawOutput containsString:@"Warning: fixture warning"]);
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
	interface.script = @"printf 'MUST_NOT_LAUNCH\\n'";
	interface.formatting = ^{ @synchronized (progress) { [progress cancel]; } };
	NSMutableString *output = [NSMutableString string];
	XCTAssertFalse([interface removeUnusedFormulae:@[@"libfoo"] progress:progress output:^(NSString *chunk) { [output appendString:chunk]; }]);
	XCTAssertFalse([output containsString:@"MUST_NOT_LAUNCH"]);
	interface.formatting = nil;
	interface.script = @"printf 'OWNED_RUNNING\\n'; while :; do /bin/sleep 1; done";
	NSProgress *active = [NSProgress progressWithTotalUnitCount:1];
	[output setString:@""];
	XCTAssertFalse([interface removeUnusedFormulae:@[@"libfoo"] progress:active output:^(NSString *chunk) {
		[output appendString:chunk];
		if ([chunk containsString:@"OWNED_RUNNING"]) { @synchronized (active) { [active cancel]; } }
	}]);
	XCTAssertTrue([output containsString:@"OWNED_RUNNING"]);
	XCTAssertTrue(active.cancelled);
}

- (void)testAutoremoveCommandsAreExactAndPreserveFailure
{
	CB150CommandInterface *interface = [[CB150CommandInterface allocWithZone:NULL] initUniqueInstance];
	interface.fixture = @"==> Would autoremove 1 unneeded formula:\nlibfoo\n";
	XCTAssertTrue([interface previewAutoremoveWithProgress:[NSProgress progressWithTotalUnitCount:1]].valid);
	XCTAssertEqualObjects(interface.arguments, (@[@"autoremove", @"--dry-run"]));
	interface.status = 7;
	XCTAssertFalse([interface previewAutoremoveWithProgress:[NSProgress progressWithTotalUnitCount:1]].valid);
	XCTAssertFalse([interface removeUnusedFormulae:@[@"libfoo"] progress:[NSProgress progressWithTotalUnitCount:1] output:nil]);
	XCTAssertEqualObjects(interface.arguments, (@[@"uninstall", @"--formula", @"libfoo"]));
	NSString *command = [interface formatAutoremoveArguments:@[@"uninstall", @"--formula", @"libfoo"]][2];
	XCTAssertTrue([command containsString:@"/usr/bin/env HOMEBREW_NO_AUTOREMOVE=1 HOMEBREW_NO_AUTO_UPDATE=1 brew \"$@\""]);
}

- (void)testAutoremoveRevalidationAndCancellationNeverBroadenReviewedNames
{
	for (NSNumber *scenario in @[@0, @1, @2, @3]) {
		CB150Interface *interface = [[CB150Interface allocWithZone:NULL] initUniqueInstance];
		BPAutoremovePreview *reviewed = [BPAutoremovePreview previewWithOutput:@"==> Would autoremove 1 unneeded formula:\nlibfoo\n" succeeded:YES];
		interface.preview = scenario.intValue == 1 ? [BPAutoremovePreview previewWithOutput:@"" succeeded:YES] : reviewed;
		interface.removalSuccess = scenario.intValue != 3;
		BPAutoremoveOperation *operation = [[BPAutoremoveOperation alloc] initWithPreview:reviewed interface:interface];
		if (scenario.intValue == 2) [operation cancel];
		XCTestExpectation *finished = [self expectationWithDescription:@"autoremove completes once"];
		__block NSUInteger completions = 0;
		[operation startWithOutput:nil completion:^(BOOL success, BOOL cancelled, BOOL attempted, NSString *message) {
			completions++; XCTAssertTrue(NSThread.isMainThread);
			XCTAssertEqual(success, scenario.intValue == 0);
			XCTAssertEqual(cancelled, scenario.intValue == 2);
			XCTAssertEqual(attempted, scenario.intValue == 0 || scenario.intValue == 3);
			if (scenario.intValue == 3) XCTAssertTrue([message containsString:@"partially"]);
			[finished fulfill];
		}];
		[operation startWithOutput:nil completion:nil];
		[self waitForExpectations:@[finished] timeout:5];
		XCTAssertEqual(completions, 1u);
		XCTAssertEqual(interface.removalCalls, scenario.intValue == 0 || scenario.intValue == 3 ? 1u : 0u);
		if (interface.removalCalls) XCTAssertEqualObjects(interface.removed, reviewed.names);
	}
}

- (void)testAutoremovePreviewRequiresExactCountAndSafeUniqueFormulaNames
{
	BPAutoremovePreview *preview = [BPAutoremovePreview previewWithOutput:@"==> Would autoremove 2 unneeded formulae:\nlibfoo\nuser/tap/library@2\n" succeeded:YES];
	XCTAssertTrue(preview.valid);
	XCTAssertEqualObjects(preview.names, (@[@"libfoo", @"user/tap/library@2"]));
	for (NSString *text in @[@"==> Would autoremove 2 unneeded formulae:\nlibfoo\n", @"unexpected", @"Warning: failed\n", @"==> Would autoremove 2 unneeded formulae:\nlibfoo\nlibfoo\n", @"==> Would autoremove 1 unneeded formula:\n--force\n", @"==> Would autoremove 1 unneeded formula:\nfoo;bar\n"]) {
		XCTAssertFalse([BPAutoremovePreview previewWithOutput:text succeeded:YES].valid, @"%@", text);
	}
	XCTAssertTrue([BPAutoremovePreview previewWithOutput:@"" succeeded:YES].valid);
	XCTAssertFalse([BPAutoremovePreview previewWithOutput:@"" succeeded:NO].valid);
}

@end
