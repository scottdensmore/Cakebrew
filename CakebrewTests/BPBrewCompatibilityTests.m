//
//  BPBrewCompatibilityTests.m
//  CakebrewTests
//
//  Fixture tests pin the parsers against output captured at a point in time.
//  They cannot notice Homebrew changing its output — which is exactly how
//  `brew info` drifted for years until installPath started displaying the
//  literal string "Installed (on request)".
//
//  These tests run the *real* brew on the machine and push its output through
//  the same parsers. They are skipped unless CAKEBREW_BREW_COMPAT=1, so the
//  normal (hermetic) suite is unaffected; the scheduled brew-compat workflow
//  sets it. A failure here means upstream drift, not a bad change in the PR
//  that happens to be open — which is why it is scheduled rather than on the
//  PR path.
//

#import <XCTest/XCTest.h>
#import "BPFormula.h"
#import "BPService.h"
#import "BPHomebrewInterface.h"

// The list parsers are private to BPHomebrewInterface.m (compiled into this
// target); re-declared here exactly as BPHomebrewInterfaceListCallTests does.
@interface BPHomebrewInterfaceListCall : NSObject
- (NSArray<BPFormula *> *)parseData:(NSString *)data;
@end

@interface BPHomebrewInterfaceListCallInstalled : BPHomebrewInterfaceListCall
- (instancetype)init;
@end

@interface BPHomebrewInterfaceListCallUpgradeable : BPHomebrewInterfaceListCall
- (instancetype)init;
@end

@interface BPHomebrewInterfaceListCallInstalledCasks : BPHomebrewInterfaceListCallInstalled
- (instancetype)init;
@end

@interface BPHomebrewInterfaceListCallAllCasks : BPHomebrewInterfaceListCall
- (instancetype)init;
@end

@interface BPFormula (BPBrewCompatibilityTestsPrivate)
- (BOOL)getInformation;
@end

/// Feeds one canned string, so BPFormula parses real `brew info` output.
@interface BPLiteralInfoProvider : NSObject <BPFormulaDataProvider>
@property (copy) NSString *info;
@end

@implementation BPLiteralInfoProvider
- (NSString *)informationForFormulaName:(NSString *)name { return self.info; }
@end

@interface BPCompatFormula : BPFormula
@property (strong) BPLiteralInfoProvider *provider;
@end

@implementation BPCompatFormula
- (id<BPFormulaDataProvider>)dataProvider { return self.provider; }
@end

@interface BPBrewCompatibilityTests : XCTestCase
@end

@implementation BPBrewCompatibilityTests

- (void)setUp
{
	[super setUp];

	if (![[[NSProcessInfo processInfo] environment][@"CAKEBREW_BREW_COMPAT"] isEqualToString:@"1"])
	{
		XCTSkip("set CAKEBREW_BREW_COMPAT=1 to run the parsers against real brew");
	}
}

/// Runs brew through a login shell, the way BPHomebrewInterface does.
- (NSString *)brew:(NSArray<NSString *> *)arguments
{
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/bin/bash";
	task.arguments = [@[@"-l", @"-c", @"brew \"$@\"", @"brew"] arrayByAddingObjectsFromArray:arguments];

	NSPipe *pipe = [NSPipe pipe];
	task.standardOutput = pipe;
	task.standardError = [NSPipe pipe];
	task.standardInput = [NSFileHandle fileHandleWithNullDevice];

	NSMutableData *collected = [NSMutableData data];
	NSFileHandle *handle = pipe.fileHandleForReading;
	handle.readabilityHandler = ^(NSFileHandle *h) { [collected appendData:[h availableData]]; };

	@try { [task launch]; }
	@catch (NSException *exception) { XCTFail(@"could not run brew: %@", exception.reason); return @""; }

	[task waitUntilExit];
	handle.readabilityHandler = nil;
	[collected appendData:[handle readDataToEndOfFile]];

	return [[NSString alloc] initWithData:collected encoding:NSUTF8StringEncoding] ?: @"";
}

#pragma mark - brew info

- (void)testBrewInfoForAnInstalledFormulaStillParses
{
	// wget is installed by the workflow before this runs.
	BPLiteralInfoProvider *provider = [[BPLiteralInfoProvider alloc] init];
	provider.info = [self brew:@[@"info", @"wget"]];
	XCTAssertGreaterThan(provider.info.length, 0u, @"brew info produced nothing");

	BPCompatFormula *formula = [BPCompatFormula formulaWithName:@"wget"];
	formula.provider = provider;
	XCTAssertTrue([formula getInformation], @"brew info output no longer parses");

	XCTAssertGreaterThan(formula.latestVersion.length, 0u, @"version went missing");
	XCTAssertFalse([formula.latestVersion containsString:@"==>"], @"section marker leaked into the version");
	XCTAssertNotNil(formula.website, @"homepage went missing");
	XCTAssertGreaterThan(formula.shortDescription.length, 0u, @"description went missing");

	// The exact drift this suite exists to catch.
	XCTAssertFalse([formula.installPath hasPrefix:@"Installed ("],
				   @"installPath is the marker line again: %@", formula.installPath);
	XCTAssertFalse([formula.installPath hasPrefix:@"Aliases:"],
				   @"installPath picked up the aliases line: %@", formula.installPath);
	XCTAssertFalse([formula.installPath hasPrefix:@"From:"], @"installPath: %@", formula.installPath);
	XCTAssertFalse([formula.installPath hasPrefix:@"License:"], @"installPath: %@", formula.installPath);
	XCTAssertGreaterThan(formula.installPath.length, 0u, @"an installed formula reported no build");
}

- (void)testBrewInfoForAFormulaThatIsNotInstalledStillParses
{
	BPLiteralInfoProvider *provider = [[BPLiteralInfoProvider alloc] init];
	provider.info = [self brew:@[@"info", @"cowsay"]];

	BPCompatFormula *formula = [BPCompatFormula formulaWithName:@"cowsay"];
	formula.provider = provider;
	XCTAssertTrue([formula getInformation]);

	XCTAssertGreaterThan(formula.latestVersion.length, 0u);
	XCTAssertNil(formula.installPath, @"a formula that isn't installed reported a location");
}

#pragma mark - list parsers

- (void)testInstalledListStillParses
{
	NSString *output = [self brew:@[@"list", @"--versions"]];
	XCTAssertGreaterThan(output.length, 0u, @"brew list produced nothing");

	NSArray<BPFormula *> *formulae = [[[BPHomebrewInterfaceListCallInstalled alloc] init] parseData:output];
	XCTAssertGreaterThan(formulae.count, 0u, @"installed list parsed to nothing");
	XCTAssertGreaterThan([formulae.firstObject.name length], 0u, @"parsed a formula with no name");
	XCTAssertGreaterThan([formulae.firstObject.version length], 0u, @"parsed a formula with no version");
}

- (void)testOutdatedListStillParses
{
	// May legitimately be empty; parsing must not blow up either way.
	NSString *output = [self brew:@[@"outdated", @"--verbose"]];
	NSArray<BPFormula *> *formulae = [[[BPHomebrewInterfaceListCallUpgradeable alloc] init] parseData:output];

	for (BPFormula *formula in formulae)
	{
		XCTAssertGreaterThan(formula.name.length, 0u, @"outdated entry with no name");
		XCTAssertGreaterThan(formula.latestVersion.length, 0u, @"outdated entry with no target version");
	}
}

- (void)testInstalledCasksListStillParses
{
	NSString *output = [self brew:@[@"list", @"--cask", @"--versions"]];
	NSArray<BPFormula *> *casks = [[[BPHomebrewInterfaceListCallInstalledCasks alloc] init] parseData:output];

	for (BPFormula *cask in casks)
	{
		XCTAssertGreaterThan(cask.name.length, 0u, @"installed cask with no name");
		XCTAssertTrue(cask.cask, @"a cask parsed by the cask list must be flagged as one");
	}
}

- (void)testAllCasksCatalogStillParses
{
	NSString *output = [self brew:@[@"casks"]];
	XCTAssertGreaterThan(output.length, 0u, @"brew casks produced nothing");

	NSArray<BPFormula *> *casks = [[[BPHomebrewInterfaceListCallAllCasks alloc] init] parseData:output];
	XCTAssertGreaterThan(casks.count, 100u, @"the cask catalog parsed to almost nothing");
	XCTAssertTrue(casks.firstObject.cask);
}

#pragma mark - services

- (void)testServicesJSONStillParses
{
	NSString *json = [self brew:@[@"services", @"list", @"--json"]];
	XCTAssertGreaterThan(json.length, 0u, @"brew services produced nothing");

	// An empty list is fine; malformed JSON or a renamed key is not.
	NSArray<BPService *> *services = [BPService servicesFromJSONString:json];
	XCTAssertNotNil(services, @"brew services list --json no longer parses");

	for (BPService *service in services)
	{
		XCTAssertGreaterThan(service.name.length, 0u, @"service with no name");
	}
}

@end
