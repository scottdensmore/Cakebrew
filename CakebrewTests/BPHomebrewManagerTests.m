//
//  BPHomebrewManagerTests.m
//  CakebrewTests
//
//  Tests for BPHomebrewManager's pure status logic: statusForFormula: derives a
//  formula's state from the installed/outdated lists, matching by installedName
//  (so tap-qualified and short names compare equal).
//

#import <XCTest/XCTest.h>
#import "BPHomebrewManager.h"
#import "BPFormula.h"

@interface BPHomebrewManagerTests : XCTestCase
@property (strong) BPHomebrewManager *manager;
@end

@implementation BPHomebrewManagerTests

- (void)setUp
{
	[super setUp];
	// BPHomebrewManager is a singleton (alloc/init are unavailable). Each test
	// sets the lists it needs, and setUp/tearDown reset them so there is no
	// state bleed between tests.
	self.manager = [BPHomebrewManager sharedManager];
	self.manager.installedFormulae = @[];
	self.manager.outdatedFormulae = @[];
}

- (void)tearDown
{
	self.manager.installedFormulae = @[];
	self.manager.outdatedFormulae = @[];
	self.manager = nil;
	[super tearDown];
}

- (void)testStatusIsNotInstalledWhenAbsent
{
	self.manager.installedFormulae = @[[BPFormula formulaWithName:@"git"]];
	XCTAssertEqual([self.manager statusForFormula:[BPFormula formulaWithName:@"wget"]], kBPFormulaNotInstalled);
}

- (void)testStatusIsInstalledWhenPresentAndNotOutdated
{
	self.manager.installedFormulae = @[[BPFormula formulaWithName:@"git"]];
	self.manager.outdatedFormulae = @[];
	XCTAssertEqual([self.manager statusForFormula:[BPFormula formulaWithName:@"git"]], kBPFormulaInstalled);
}

- (void)testStatusIsOutdatedWhenPresentInBoth
{
	self.manager.installedFormulae = @[[BPFormula formulaWithName:@"git"]];
	self.manager.outdatedFormulae = @[[BPFormula formulaWithName:@"git"]];
	XCTAssertEqual([self.manager statusForFormula:[BPFormula formulaWithName:@"git"]], kBPFormulaOutdated);
}

- (void)testStatusMatchesByShortNameAcrossTaps
{
	// Installed under the short name; a tap-qualified query still matches via installedName.
	self.manager.installedFormulae = @[[BPFormula formulaWithName:@"foo"]];
	XCTAssertEqual([self.manager statusForFormula:[BPFormula formulaWithName:@"homebrew/core/foo"]], kBPFormulaInstalled);
}

- (void)testStatusIsNotInstalledWhenOnlyInOutdatedList
{
	// statusForFormula gates on the installed list first, so a formula that is
	// only in the outdated list (but not installed) is reported as not installed.
	self.manager.installedFormulae = @[];
	self.manager.outdatedFormulae = @[[BPFormula formulaWithName:@"git"]];
	XCTAssertEqual([self.manager statusForFormula:[BPFormula formulaWithName:@"git"]], kBPFormulaNotInstalled);
}

@end
