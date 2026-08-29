//
//  BPFormulaModernInfoTests.m
//  CakebrewTests
//
//  Every brew info fixture in this suite dated from circa 2015 — they still
//  cite the retired github.com/Homebrew/homebrew Library/Formula path — and
//  BPFormula walked the output positionally. Current Homebrew prefixes the
//  header with "==> ", may insert an "Aliases:" line, and replaced the Cellar
//  path with "Installed (on request)" / "Installed (as dependency)" plus an
//  "==> Installed Versions" block.
//
//  The positional walk therefore assigned installPath the literal string
//  "Installed (on request)", which the detail pane displayed verbatim.
//
//  These fixtures are captured from real brew (wget, tree, openssl@3, libffi).
//  The legacy fixtures stay in BPFormulaTests as back-compat cases.
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "BPFormula.h"

@interface BPFormula (BPFormulaModernInfoTestsPrivate)
- (BOOL)getInformation;
@end

@interface BPModernInfoDataProvider : NSObject <BPFormulaDataProvider>
@end

@implementation BPModernInfoDataProvider

- (NSString *)informationForFormulaName:(NSString *)name
{
	static NSDictionary *fixtures = nil;
	if (!fixtures)
	{
		fixtures = @{ @"wget"      : @"brewInfo_modern_installed",
					  @"tree"      : @"brewInfo_modern_notinstalled",
					  @"openssl@3" : @"brewInfo_modern_aliases",
					  @"libffi"    : @"brewInfo_modern_kegonly" };
	}

	NSString *fixture = fixtures[name];
	if (!fixture)
	{
		return nil;
	}

	NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:fixture ofType:@"txt"];
	return [[NSString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

@end

@interface BPModernFormula : BPFormula
@end

@implementation BPModernFormula
- (id<BPFormulaDataProvider>)dataProvider
{
	return [[BPModernInfoDataProvider alloc] init];
}
@end

@interface BPFormulaModernInfoTests : XCTestCase
@end

@implementation BPFormulaModernInfoTests

- (BPFormula *)parsedFormulaNamed:(NSString *)name
{
	BPFormula *formula = [BPModernFormula formulaWithName:name];
	XCTAssertTrue([formula getInformation], @"parsing %@ should succeed", name);
	return formula;
}

#pragma mark - installed formula

- (void)testInstalledFormulaFieldsAreParsed
{
	BPFormula *wget = [self parsedFormulaNamed:@"wget"];

	XCTAssertEqualObjects(wget.latestVersion, @"stable 1.25.0 (bottled), HEAD",
						  @"the \"==> \" header prefix must not leak into the version");
	XCTAssertEqualObjects(wget.shortDescription, @"Internet file retriever");
	XCTAssertEqualObjects(wget.website.absoluteString, @"https://www.gnu.org/software/wget/");
}

- (void)testInstalledFormulaReportsTheInstalledVersionLineNotTheInstalledMarker
{
	// The actual regression: installPath used to be the literal string
	// "Installed (on request)".
	BPFormula *wget = [self parsedFormulaNamed:@"wget"];

	XCTAssertNotEqualObjects(wget.installPath, @"Installed (on request)",
							 @"the \"Installed\" marker line is not an install location");
	XCTAssertEqualObjects(wget.installPath, @"wget 1.25.0 (92 files, 4.7MB) [Linked]",
						  @"modern brew reports the installed build here, not a Cellar path");
}

#pragma mark - formula that is not installed

- (void)testNotInstalledFormulaHasNoInstallPath
{
	BPFormula *tree = [self parsedFormulaNamed:@"tree"];

	XCTAssertNil(tree.installPath, @"a formula that isn't installed has nothing to report");
	XCTAssertEqualObjects(tree.latestVersion, @"stable 2.3.2 (bottled)");
	XCTAssertEqualObjects(tree.shortDescription, @"Display directories as trees (with optional color/HTML output)");
	XCTAssertEqualObjects(tree.website.absoluteString, @"https://oldmanprogrammer.net/source.php?dir=projects/tree");
}

#pragma mark - the Aliases line

- (void)testAliasesLineDoesNotDisplaceTheOtherFields
{
	// "Aliases:" sits between the homepage and the installed marker, so a
	// positional walk reads it as the install location.
	BPFormula *openssl = [self parsedFormulaNamed:@"openssl@3"];

	XCTAssertEqualObjects(openssl.shortDescription, @"Cryptography and SSL/TLS Toolkit");
	XCTAssertEqualObjects(openssl.website.absoluteString, @"https://openssl-library.org");
	XCTAssertEqualObjects(openssl.installPath, @"openssl@3 3.6.3 (7,633 files, 38.1MB) [Linked]");
	XCTAssertFalse([openssl.installPath hasPrefix:@"Aliases"], @"the aliases line is not an install location");
}

#pragma mark - keg-only

- (void)testKegOnlyFormulaParses
{
	// The header carries a trailing "[keg-only]" marker and the formula has a
	// Caveats section after Options.
	BPFormula *libffi = [self parsedFormulaNamed:@"libffi"];

	XCTAssertEqualObjects(libffi.latestVersion, @"stable 3.8.0 (bottled), HEAD [keg-only]");
	XCTAssertEqualObjects(libffi.shortDescription, @"Portable Foreign Function Interface library");
	XCTAssertEqualObjects(libffi.installPath, @"libffi 3.8.0 (18 files, 881.2KB)",
						  @"keg-only builds are unlinked, so there is no [Linked] suffix");
}

#pragma mark - fields never carry section markers

- (void)testNoParsedFieldRetainsASectionHeaderMarker
{
	for (NSString *name in @[ @"wget", @"tree", @"openssl@3", @"libffi" ])
	{
		BPFormula *formula = [self parsedFormulaNamed:name];

		XCTAssertFalse([formula.latestVersion containsString:@"==>"], @"%@ version", name);
		XCTAssertFalse([formula.installPath containsString:@"==>"], @"%@ install path", name);
		XCTAssertFalse([formula.shortDescription containsString:@"==>"], @"%@ description", name);
		XCTAssertFalse([formula.installPath hasPrefix:@"From:"], @"%@ install path", name);
		XCTAssertFalse([formula.installPath hasPrefix:@"License:"], @"%@ install path", name);
	}
}

@end
