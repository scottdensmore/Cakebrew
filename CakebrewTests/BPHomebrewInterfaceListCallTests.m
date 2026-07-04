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

@end
