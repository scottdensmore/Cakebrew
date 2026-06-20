//
//  BPFormulaeDataSourceTests.m
//  CakebrewTests
//
//  Tests for BPFormulaeDataSource: it mirrors the BPHomebrewManager list for its
//  mode and provides bounds-safe row accessors.
//

#import <XCTest/XCTest.h>
#import "BPFormulaeDataSource.h"
#import "BPHomebrewManager.h"
#import "BPFormula.h"

@interface BPFormulaeDataSourceTests : XCTestCase
@property (strong) BPHomebrewManager *manager;
@end

@implementation BPFormulaeDataSourceTests

- (void)setUp
{
	[super setUp];
	self.manager = [BPHomebrewManager sharedManager];
	self.manager.installedFormulae = @[];
	self.manager.allFormulae = @[];
}

- (void)tearDown
{
	self.manager.installedFormulae = @[];
	self.manager.allFormulae = @[];
	self.manager = nil;
	[super tearDown];
}

- (void)testInstalledModeReflectsInstalledList
{
	BPFormula *git = [BPFormula formulaWithName:@"git"];
	BPFormula *wget = [BPFormula formulaWithName:@"wget"];
	self.manager.installedFormulae = @[ git, wget ];

	BPFormulaeDataSource *dataSource = [[BPFormulaeDataSource alloc] initWithMode:kBPListInstalled];

	XCTAssertEqual([dataSource numberOfRowsInTableView:nil], 2);
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
	XCTAssertEqual([dataSource numberOfRowsInTableView:nil], 1);

	dataSource.mode = kBPListAll;
	XCTAssertEqual([dataSource numberOfRowsInTableView:nil], 2);
}

@end
