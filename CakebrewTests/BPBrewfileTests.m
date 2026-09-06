//
//  BPBrewfileTests.m
//  CakebrewTests
//
//  Brewfiles are first class to this app — Tools ▸ Export / Import Brew
//  Installation — but the bundle declared no document types, so one in Finder
//  had no relationship to Cakebrew at all: not openable with it, not droppable
//  on it.
//
//  Deciding what counts as a Brewfile is the part worth testing. Too narrow and
//  the feature does not fire on files people really have; too broad and
//  Cakebrew offers to run `brew bundle` against arbitrary text.
//

#import <XCTest/XCTest.h>
#import "BPBrewfile.h"
#import "BPBrewfilePlan.h"
#import "BPBrewfileImportOperation.h"
#import "BPHomebrewInterface.h"

@interface BPHomebrewInterface (CB151Testing)
- (instancetype)initUniqueInstance;
@end
@interface CB151ImportInterface : BPHomebrewInterface
@property (copy) NSString *snapshotPath;
@property (copy) void (^entered)(void);
@property (strong) dispatch_semaphore_t releaseCommand;
@property NSUInteger calls;
@end
@implementation CB151ImportInterface
- (BOOL)runBrewImportToolWithPath:(NSString *)path progress:(NSProgress *)progress withReturnsBlock:(void (^)(NSString *))block
{
 self.calls++; self.snapshotPath = path;
 XCTAssertFalse(NSThread.isMainThread);
 XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path]);
 if (block) block(@"fixture output");
 if (self.entered) self.entered();
 if (self.releaseCommand) dispatch_semaphore_wait(self.releaseCommand, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
 return !progress.cancelled;
}
@end

@interface CB151DirectInterface : BPHomebrewInterface
@property (copy) void (^duringFormatting)(void);
@property (copy) NSArray *receivedArguments;
@end
@implementation CB151DirectInterface
- (NSArray *)formatArguments:(NSArray *)arguments sendOutputId:(BOOL)outputID
{
 self.receivedArguments = arguments;
 if (self.duringFormatting) self.duringFormatting();
 return @[@"-c", @"printf 'ACTUAL_FIXTURE_LAUNCH\\n'"];
}
@end

@interface BPBrewfileTests : XCTestCase
@end

@implementation BPBrewfileTests

- (void)testDirectImportCancellationBetweenRequestAndTaskCreationIsNotLost
{
 CB151DirectInterface *interface = [[CB151DirectInterface allocWithZone:NULL] initUniqueInstance];
 [interface setValue:@"/bin/sh" forKey:@"path_shell"];
 NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
 interface.duringFormatting = ^{ [progress cancel]; };
 NSMutableString *output = [NSMutableString string];
 XCTAssertFalse([interface runBrewImportToolWithPath:@"/fixture/Brewfile" progress:progress withReturnsBlock:^(NSString *chunk) { [output appendString:chunk]; }]);
 XCTAssertEqualObjects(interface.receivedArguments, (@[@"bundle", @"--file=/fixture/Brewfile"]));
 XCTAssertFalse([[output componentsSeparatedByString:@"\n"] containsObject:@"ACTUAL_FIXTURE_LAUNCH"]);
 interface.duringFormatting = nil;
 [output setString:@""];
 XCTAssertTrue([interface runBrewImportToolWithPath:@"/fixture/NextBrewfile" progress:[NSProgress progressWithTotalUnitCount:1] withReturnsBlock:^(NSString *chunk) { [output appendString:chunk]; }]);
 XCTAssertTrue([[output componentsSeparatedByString:@"\n"] containsObject:@"ACTUAL_FIXTURE_LAUNCH"]);
}

- (void)testReviewGroupsDirectEntriesAndReportsInstalledMissingAndUncheckedTotals
{
 BPBrewfilePlan *plan = [BPBrewfilePlan planWithString:@"brew 'git'\ncask 'firefox'\ntap 'owner/tap'\nmas 'App', id: 123\nvscode 'pub.ext'" inventories:@{@"brew": @[@"git"], @"cask": @[]}];
 XCTAssertTrue([plan.reviewText containsString:@"Formulae"]);
 XCTAssertTrue([plan.reviewText containsString:@"Casks"]);
 XCTAssertTrue([plan.reviewText containsString:@"Mac App Store"]);
 XCTAssertTrue([plan.reviewText containsString:@"1 installed"]);
 XCTAssertTrue([plan.reviewText containsString:@"1 missing"]);
 XCTAssertTrue([plan.reviewText containsString:@"3 not checked"]);
 XCTAssertTrue([plan.reviewText containsString:@"App (id: 123)"]);
}

- (void)testHelperTransportIsRejectedWithoutDispatchingAnImport
{
 CB151ImportInterface *interface = [[CB151ImportInterface allocWithZone:NULL] initUniqueInstance];
 interface.brewTransport = kBPBrewTransportHelper;
 BPBrewfileImportOperation *operation = [[BPBrewfileImportOperation alloc] initWithPlan:[BPBrewfilePlan planWithString:@"brew 'git'" inventories:@{}] interface:interface];
 XCTestExpectation *finished = [self expectationWithDescription:@"unsupported transport"];
 [operation startWithOutput:nil completion:^(BOOL success, BOOL cancelled, NSError *error) {
  XCTAssertFalse(success); XCTAssertNotNil(error); XCTAssertEqual(interface.calls, 0u); [finished fulfill];
 }];
 [self waitForExpectations:@[finished] timeout:5];
}

- (void)testReadingOriginalFileProducesASafePlanAndNeverRunsItsRuby
{
 NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
 [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:NULL];
 NSURL *file = [directory URLByAppendingPathComponent:@"Brewfile"];
 [@"brew 'git'" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];
 BPBrewfilePlan *plan = [BPBrewfilePlan planWithURL:file inventories:@{} error:NULL];
 [@"system('unsafe')" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];
 NSURL *snapshot = [plan createSnapshotWithError:NULL];
 XCTAssertNotEqualObjects(snapshot, file);
 XCTAssertEqualObjects([NSString stringWithContentsOfURL:snapshot encoding:NSUTF8StringEncoding error:NULL], @"brew 'git'\n");
 XCTAssertFalse([BPBrewfilePlan planWithURL:file inventories:@{} error:NULL].canInstall);
 XCTAssertNil([BPBrewfilePlan planWithURL:directory inventories:@{} error:NULL]);
 [BPBrewfilePlan removeSnapshot:snapshot];
 [[NSFileManager defaultManager] removeItemAtURL:directory error:NULL];
}

- (void)testImportRunsOffMainDeliversOnMainAndRetainsSnapshotUntilCancelledCommandExits
{
 CB151ImportInterface *interface = [[CB151ImportInterface allocWithZone:NULL] initUniqueInstance];
 interface.releaseCommand = dispatch_semaphore_create(0);
 BPBrewfileImportOperation *operation = [[BPBrewfileImportOperation alloc] initWithPlan:[BPBrewfilePlan planWithString:@"brew 'git'" inventories:@{}] interface:interface];
 XCTestExpectation *entered = [self expectationWithDescription:@"entered"], *output = [self expectationWithDescription:@"output"], *finished = [self expectationWithDescription:@"finished"];
 interface.entered = ^{ [entered fulfill]; };
 [operation startWithOutput:^(NSString *chunk) { XCTAssertTrue(NSThread.isMainThread); XCTAssertEqualObjects(chunk, @"fixture output"); [output fulfill]; }
 completion:^(BOOL success, BOOL cancelled, NSError *error) {
  XCTAssertTrue(NSThread.isMainThread); XCTAssertFalse(success); XCTAssertTrue(cancelled); XCTAssertFalse(operation.running);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:interface.snapshotPath]); [finished fulfill];
 }];
 [self waitForExpectations:@[entered, output] timeout:5];
 [operation cancel];
 XCTAssertTrue(operation.running);
 XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:interface.snapshotPath]);
 [operation startWithOutput:nil completion:nil];
 dispatch_semaphore_signal(interface.releaseCommand);
 [self waitForExpectations:@[finished] timeout:5];
 XCTAssertEqual(interface.calls, 1u);
}

- (void)testCancelledOrUnsupportedImportNeverStartsACommand
{
 for (NSNumber *cancel in @[@YES, @NO]) {
  CB151ImportInterface *interface = [[CB151ImportInterface allocWithZone:NULL] initUniqueInstance];
  BPBrewfilePlan *plan = [BPBrewfilePlan planWithString:cancel.boolValue ? @"brew 'git'" : @"system('unsafe')" inventories:@{}];
  BPBrewfileImportOperation *operation = [[BPBrewfileImportOperation alloc] initWithPlan:plan interface:interface];
  if (cancel.boolValue) [operation cancel];
  XCTestExpectation *finished = [self expectationWithDescription:@"not started"];
  [operation startWithOutput:nil completion:^(BOOL success, BOOL cancelled, NSError *error) { XCTAssertFalse(success); [finished fulfill]; }];
  [self waitForExpectations:@[finished] timeout:5];
  XCTAssertEqual(interface.calls, 0u);
 }
}

- (void)testLiteralPlanPreservesTypesCommentsAndCRLFWithoutExecutingRuby
{
 BPBrewfilePlan *plan = [BPBrewfilePlan planWithString:@"# exported\r\ntap 'homebrew/cask'\r\nbrew \"git\" # comment\r\ncask 'firefox'\r\nmas \"Example App\", id: 123\r\nvscode 'publisher.extension'\r\n" inventories:@{@"brew": @[@"git"], @"cask": @[], @"tap": @[@"homebrew/cask"]}];
 XCTAssertTrue(plan.canInstall);
 XCTAssertEqual(plan.entries.count, 5u);
 XCTAssertEqualObjects([plan.entries valueForKey:@"kind"], (@[@"tap", @"brew", @"cask", @"mas", @"vscode"]));
 XCTAssertEqualObjects([plan.entries valueForKey:@"status"], (@[@"Installed", @"Installed", @"Missing", @"Not checked", @"Not checked"]));
 XCTAssertTrue([plan.canonicalContents containsString:@"mas 'Example App', id: 123\n"]);
}

- (void)testAnyUnsupportedLineBlocksTheWholePlanWithLineDiagnostic
{
 for (NSString *line in @[@"system('touch /tmp/unsafe')", @"brew ENV['PACKAGE']", @"brew \"#{system('x')}\"", @"brew 'git', restart_service: true", @"brew 'git'; system('x')", @"brew '../git'", @"brew '-help'", @"mas 'App', id: 0", @"cask 'app' do", @"brew 'git\\n'", @"brew 'git'\u2028system('x')"]) {
  BPBrewfilePlan *plan = [BPBrewfilePlan planWithString:[@"brew 'git'\n" stringByAppendingString:line] inventories:@{}];
  XCTAssertFalse(plan.canInstall, @"%@", line);
  XCTAssertEqual(plan.diagnostics.count, 1u, @"%@", line);
  XCTAssertTrue([plan.diagnostics.firstObject containsString:@"2"], @"%@", line);
  XCTAssertNil(plan.canonicalContents);
  XCTAssertNil([plan createSnapshotWithError:NULL]);
 }
}

- (void)testInventoryNamespacesAndUnknownQualifiedIdentityRemainHonest
{
 BPBrewfilePlan *plan = [BPBrewfilePlan planWithString:@"brew 'same'\ncask 'same'\nbrew 'owner/tap/same'\ntap 'owner/tap'" inventories:@{@"brew": @[@"same"]}];
 XCTAssertEqualObjects([plan.entries valueForKey:@"status"], (@[@"Installed", @"Not checked", @"Not checked", @"Not checked"]));
 XCTAssertFalse([BPBrewfilePlan planWithString:@"# empty" inventories:@{}].canInstall);
}

- (void)testSnapshotIsCanonicalPrivateAndIndependentOfMutableInput
{
 NSMutableString *source = [@"brew \"git\" # ignored" mutableCopy];
 BPBrewfilePlan *plan = [BPBrewfilePlan planWithString:source inventories:@{}];
 [source setString:@"system('unsafe')"];
 NSError *error;
 NSURL *snapshot = [plan createSnapshotWithError:&error];
 XCTAssertNotNil(snapshot); XCTAssertNil(error);
 XCTAssertEqualObjects([NSString stringWithContentsOfURL:snapshot encoding:NSUTF8StringEncoding error:NULL], @"brew 'git'\n");
 NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:snapshot.URLByDeletingLastPathComponent.path error:NULL];
 XCTAssertEqual([attributes[NSFilePosixPermissions] integerValue], 0700);
 [BPBrewfilePlan removeSnapshot:snapshot];
 XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:snapshot.path]);
}

- (BOOL)accepts:(NSString *)name
{
	return [BPBrewfile isBrewfileURL:[NSURL fileURLWithPath:[@"/tmp" stringByAppendingPathComponent:name]]];
}

#pragma mark - What counts

- (void)testDefaultFilenameKeepsTheCanonicalHomebrewName
{
	XCTAssertEqualObjects([BPBrewfile defaultFilename], @"Brewfile");
	XCTAssertTrue([self accepts:[BPBrewfile defaultFilename]]);
}

- (void)testTheCanonicalNameIsAccepted
{
	XCTAssertTrue([self accepts:@"Brewfile"]);
}

/// The filesystem is case-insensitive by default, so a file the user thinks is
/// a Brewfile can be spelled either way.
- (void)testTheNameIsMatchedCaseInsensitively
{
	XCTAssertTrue([self accepts:@"brewfile"]);
	XCTAssertTrue([self accepts:@"BREWFILE"]);
}

/// `brew bundle --file=` takes any path, and people really do keep
/// work.Brewfile next to personal.Brewfile.
- (void)testAQualifiedBrewfileIsAccepted
{
	XCTAssertTrue([self accepts:@"work.Brewfile"]);
	XCTAssertTrue([self accepts:@"personal.brewfile"]);
}

#pragma mark - What does not

/// The lock file sits right next to the Brewfile and is JSON, not a bundle
/// description. Feeding it to `brew bundle` is not something to offer.
- (void)testTheLockFileIsRejected
{
	XCTAssertFalse([self accepts:@"Brewfile.lock.json"]);
}

- (void)testAnUnrelatedNameIsRejected
{
	XCTAssertFalse([self accepts:@"README"]);
	XCTAssertFalse([self accepts:@"Brewfile.txt"]);
	XCTAssertFalse([self accepts:@"Podfile"]);
	XCTAssertFalse([self accepts:@"my-brewfile-notes.md"]);
}

- (void)testNonFileAndMissingURLsAreRejected
{
	XCTAssertFalse([BPBrewfile isBrewfileURL:nil]);
	XCTAssertFalse([BPBrewfile isBrewfileURL:[NSURL URLWithString:@"https://example.com/Brewfile"]]);
}

#pragma mark - Filtering a drop

/// A drop or an open can carry several files. Import takes one Brewfile, so
/// the non-Brewfiles are dropped rather than the whole gesture refused.
- (void)testFilteringKeepsOnlyBrewfilesInOrder
{
	NSArray<NSURL *> *urls = @[ [NSURL fileURLWithPath:@"/tmp/README"],
								[NSURL fileURLWithPath:@"/tmp/work.Brewfile"],
								[NSURL fileURLWithPath:@"/tmp/Brewfile.lock.json"],
								[NSURL fileURLWithPath:@"/tmp/Brewfile"] ];

	NSArray<NSURL *> *filtered = [BPBrewfile brewfileURLsFrom:urls];

	XCTAssertEqual(filtered.count, 2u);
	XCTAssertEqualObjects(filtered.firstObject.lastPathComponent, @"work.Brewfile");
	XCTAssertEqualObjects(filtered.lastObject.lastPathComponent, @"Brewfile");
}

- (void)testFilteringNothingYieldsNothingRatherThanNil
{
	XCTAssertEqualObjects([BPBrewfile brewfileURLsFrom:@[]], @[]);
	XCTAssertEqualObjects([BPBrewfile brewfileURLsFrom:nil], @[]);
}

@end
