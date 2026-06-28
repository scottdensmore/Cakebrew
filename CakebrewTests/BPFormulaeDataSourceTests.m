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

@end
