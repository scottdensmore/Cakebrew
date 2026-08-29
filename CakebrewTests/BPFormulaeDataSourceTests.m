//
//  BPFormulaeDataSourceTests.m
//  CakebrewTests
//
//  Tests for BPFormulaeDataSource: it mirrors the BPHomebrewManager list for its
//  mode and provides bounds-safe row accessors.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>
#import "BPFormulaeDataSource.h"
#import "BPFormulaeTableView.h"
#import "BPHomebrewManager.h"
#import "BPFormula.h"

@interface BPFormulaeDataSourceTests : XCTestCase
@property (strong) BPHomebrewManager *manager;
// numberOfRowsInTableView: ignores its argument, but the NSTableViewDataSource
// parameter is declared nonnull — pass a throwaway view instead of nil.
@property (strong) NSTableView *tableView;
@end

@implementation BPFormulaeDataSourceTests

- (void)setUp
{
	[super setUp];
	self.manager = [BPHomebrewManager sharedManager];
	self.manager.installedFormulae = @[];
	self.manager.allFormulae = @[];
	self.tableView = [[NSTableView alloc] init];
}

- (void)tearDown
{
	self.manager.installedFormulae = @[];
	self.manager.allFormulae = @[];
	self.manager = nil;
	self.tableView = nil;
	[super tearDown];
}

- (void)testInstalledModeReflectsInstalledList
{
	BPFormula *git = [BPFormula formulaWithName:@"git"];
	BPFormula *wget = [BPFormula formulaWithName:@"wget"];
	self.manager.installedFormulae = @[ git, wget ];

	BPFormulaeDataSource *dataSource = [[BPFormulaeDataSource alloc] initWithMode:kBPListInstalled];

	XCTAssertEqual([dataSource numberOfRowsInTableView:self.tableView], 2);
	XCTAssertEqualObjects([dataSource formulaAtIndex:0], git);
	XCTAssertEqualObjects([dataSource formulaAtIndex:1], wget);
}

- (void)testFormulaAtIndexOutOfBoundsReturnsNil
{
	self.manager.installedFormulae = @[ [BPFormula formulaWithName:@"git"] ];
	BPFormulaeDataSource *dataSource = [[BPFormulaeDataSource alloc] initWithMode:kBPListInstalled];

	XCTAssertNil([dataSource formulaAtIndex:5]);
	XCTAssertNil([dataSource formulaAtIndex:-1]);
}

- (void)testFormulasAtIndexSetReturnsSelectedFormulae
{
	BPFormula *a = [BPFormula formulaWithName:@"a"];
	BPFormula *b = [BPFormula formulaWithName:@"b"];
	BPFormula *c = [BPFormula formulaWithName:@"c"];
	self.manager.allFormulae = @[ a, b, c ];

	BPFormulaeDataSource *dataSource = [[BPFormulaeDataSource alloc] initWithMode:kBPListAll];

	NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
	[indexes addIndex:0];
	[indexes addIndex:2];

	XCTAssertEqualObjects([dataSource formulasAtIndexSet:indexes], (@[ a, c ]));
}

- (void)testFormulasAtIndexSetOutOfRangeReturnsNil
{
	self.manager.installedFormulae = @[ [BPFormula formulaWithName:@"git"] ];
	BPFormulaeDataSource *dataSource = [[BPFormulaeDataSource alloc] initWithMode:kBPListInstalled];

	XCTAssertNil([dataSource formulasAtIndexSet:[NSIndexSet indexSetWithIndex:5]]);
}

- (void)testChangingModeRefreshesBackingArray
{
	self.manager.installedFormulae = @[ [BPFormula formulaWithName:@"git"] ];
	self.manager.allFormulae = @[ [BPFormula formulaWithName:@"a"], [BPFormula formulaWithName:@"b"] ];

	BPFormulaeDataSource *dataSource = [[BPFormulaeDataSource alloc] initWithMode:kBPListInstalled];
	XCTAssertEqual([dataSource numberOfRowsInTableView:self.tableView], 1);

	dataSource.mode = kBPListAll;
	XCTAssertEqual([dataSource numberOfRowsInTableView:self.tableView], 2);
}

#pragma mark - name cell value (pin badge)

- (void)testNameCellValueForUnpinnedFormulaIsPlainName
{
	BPFormula *git = [BPFormula formulaWithName:@"git"];
	id value = [BPFormulaeDataSource nameCellValueForFormula:git pinned:NO];

	XCTAssertTrue([value isKindOfClass:[NSString class]], @"unpinned name is a plain string");
	XCTAssertEqualObjects(value, @"git");
}

- (void)testNameCellValueForPinnedFormulaIsAttributedStartingWithName
{
	BPFormula *git = [BPFormula formulaWithName:@"git"];
	id value = [BPFormulaeDataSource nameCellValueForFormula:git pinned:YES];

	XCTAssertTrue([value isKindOfClass:[NSAttributedString class]], @"pinned name carries a pin badge");
	XCTAssertTrue([[(NSAttributedString *)value string] hasPrefix:@"git"],
				  @"the pinned name cell must still start with the formula name");
}

#pragma mark - finding a row by name (restoring selection after a reload)

- (void)testIndexOfFormulaNamedFindsTheRow
{
	BPHomebrewManager *manager = [BPHomebrewManager sharedManager];
	manager.installedFormulae = @[ [BPFormula formulaWithName:@"wget"],
								   [BPFormula formulaWithName:@"git"],
								   [BPFormula formulaWithName:@"curl"] ];

	BPFormulaeDataSource *dataSource = [[BPFormulaeDataSource alloc] initWithMode:kBPListInstalled];
	[dataSource refreshBackingArray];

	XCTAssertEqual([dataSource indexOfFormulaNamed:@"wget"], 0);
	XCTAssertEqual([dataSource indexOfFormulaNamed:@"git"], 1);
	XCTAssertEqual([dataSource indexOfFormulaNamed:@"curl"], 2);
}

- (void)testIndexOfFormulaNamedReturnsMinusOneWhenAbsent
{
	// After an uninstall the formula is gone from the list; the caller must be
	// able to tell that apart from row 0.
	BPHomebrewManager *manager = [BPHomebrewManager sharedManager];
	manager.installedFormulae = @[ [BPFormula formulaWithName:@"wget"] ];

	BPFormulaeDataSource *dataSource = [[BPFormulaeDataSource alloc] initWithMode:kBPListInstalled];
	[dataSource refreshBackingArray];

	XCTAssertEqual([dataSource indexOfFormulaNamed:@"git"], -1);
	XCTAssertEqual([dataSource indexOfFormulaNamed:@""], -1);
	XCTAssertEqual([dataSource indexOfFormulaNamed:nil], -1);
}


#pragma mark - sorting (clickable column headers)

/// The four columns' sort keys are their identifiers, so a descriptor here is
/// exactly what a header click produces.
- (NSArray<BPFormula *> *)sorted:(NSArray<BPFormula *> *)formulae by:(NSString *)key ascending:(BOOL)ascending
{
	NSSortDescriptor *descriptor = [NSSortDescriptor sortDescriptorWithKey:key ascending:ascending];
	return [BPFormulaeDataSource formulae:formulae sortedBy:@[descriptor]];
}

- (NSArray<NSString *> *)namesOf:(NSArray<BPFormula *> *)formulae
{
	return [formulae valueForKeyPath:@"@unionOfObjects.name"];
}

- (void)testSortingByNameIsCaseInsensitiveAndOrdered
{
	NSArray *formulae = @[ [BPFormula formulaWithName:@"Wget"],
						   [BPFormula formulaWithName:@"ack"],
						   [BPFormula formulaWithName:@"git"] ];

	XCTAssertEqualObjects([self namesOf:[self sorted:formulae by:kColumnIdentifierName ascending:YES]],
						  (@[ @"ack", @"git", @"Wget" ]),
						  @"a case-sensitive sort would put Wget first, which reads as broken");
}

- (void)testSortingByNameDescendingReversesIt
{
	NSArray *formulae = @[ [BPFormula formulaWithName:@"ack"],
						   [BPFormula formulaWithName:@"git"] ];

	XCTAssertEqualObjects([self namesOf:[self sorted:formulae by:kColumnIdentifierName ascending:NO]],
						  (@[ @"git", @"ack" ]));
}

- (void)testSortingByVersionOrdersNumericallyNotLexically
{
	// Lexically "10.0" sorts before "9.0"; version columns must not do that.
	NSArray *formulae = @[ [BPFormula formulaWithName:@"a" andVersion:@"9.0"],
						   [BPFormula formulaWithName:@"b" andVersion:@"10.0"],
						   [BPFormula formulaWithName:@"c" andVersion:@"2.0"] ];

	XCTAssertEqualObjects([self namesOf:[self sorted:formulae by:kColumnIdentifierVersion ascending:YES]],
						  (@[ @"c", @"a", @"b" ]));
}

- (void)testSortingByStatusUsesEnumOrderNotTheLocalizedString
{
	// The displayed status is localized, so sorting the rendered string would
	// give a different order per language. Enum order is stable everywhere:
	// not installed (0) < installed (1) < outdated (2).
	BPHomebrewManager *manager = [BPHomebrewManager sharedManager];
	BPFormula *outdated = [BPFormula formulaWithName:@"outdated" version:@"1.0" andLatestVersion:@"2.0"];
	BPFormula *installed = [BPFormula formulaWithName:@"installed" andVersion:@"1.0"];
	BPFormula *absent = [BPFormula formulaWithName:@"absent"];
	manager.installedFormulae = @[ installed, outdated ];
	manager.outdatedFormulae = @[ outdated ];

	NSArray *sorted = [self sorted:@[ outdated, absent, installed ] by:kColumnIdentifierStatus ascending:YES];

	XCTAssertEqualObjects([self namesOf:sorted], (@[ @"absent", @"installed", @"outdated" ]));
}

- (void)testSortingIsStableForEqualKeys
{
	// Equal versions must keep their relative order, or rows shuffle on every
	// re-sort for no visible reason.
	NSArray *formulae = @[ [BPFormula formulaWithName:@"first" andVersion:@"1.0"],
						   [BPFormula formulaWithName:@"second" andVersion:@"1.0"],
						   [BPFormula formulaWithName:@"third" andVersion:@"1.0"] ];

	XCTAssertEqualObjects([self namesOf:[self sorted:formulae by:kColumnIdentifierVersion ascending:YES]],
						  (@[ @"first", @"second", @"third" ]));
}

- (void)testNoDescriptorsLeavesTheOrderAlone
{
	NSArray *formulae = @[ [BPFormula formulaWithName:@"b"], [BPFormula formulaWithName:@"a"] ];
	XCTAssertEqualObjects([self namesOf:[BPFormulaeDataSource formulae:formulae sortedBy:@[]]],
						  (@[ @"b", @"a" ]));
}

- (void)testAMissingVersionSortsBeforeAPresentOne
{
	// All Formulae rows have no installed version; they must not crash or sort
	// arbitrarily against rows that do.
	NSArray *formulae = @[ [BPFormula formulaWithName:@"has" andVersion:@"1.0"],
						   [BPFormula formulaWithName:@"none"] ];

	XCTAssertEqualObjects([self namesOf:[self sorted:formulae by:kColumnIdentifierVersion ascending:YES]],
						  (@[ @"none", @"has" ]));
}

@end
