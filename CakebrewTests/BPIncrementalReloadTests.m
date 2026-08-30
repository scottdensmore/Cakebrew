//
//  BPIncrementalReloadTests.m
//  CakebrewTests
//
//  The reload was all-or-nothing: ten brew calls fanned out, then every
//  property was set in one main-queue block. The fastest and most-used list —
//  `brew list --versions`, under a second — was hidden behind the slowest call
//  in the batch, a cold cask catalog that can take 80 seconds.
//
//  Publishing each list as it lands is what fixes that, and it introduces the
//  hazard the old design did not have: a superseded reload's lists arriving
//  after a newer one has already published. The generation guard is the whole
//  correctness argument, so it is what these tests pin.
//

#import <XCTest/XCTest.h>
#import "BPHomebrewManager.h"
#import "BPHomebrewInterface.h"
#import "BPSideBarController.h"
#import "BPFormula.h"

@interface BPIncrementalReloadRecorder : NSObject <BPHomebrewManagerDelegate>
@property (strong) NSMutableArray<NSNumber *> *publishedModes;
@property (assign) NSUInteger finishedCount;
@end

@implementation BPIncrementalReloadRecorder

- (instancetype)init
{
	self = [super init];
	if (self) {
		_publishedModes = [NSMutableArray array];
	}
	return self;
}

- (void)homebrewManager:(BPHomebrewManager *)manager didPublishListForMode:(BPListMode)mode
{
	[self.publishedModes addObject:@(mode)];
}

- (void)homebrewManagerFinishedUpdating:(BPHomebrewManager *)manager { self.finishedCount++; }
- (void)homebrewManager:(BPHomebrewManager *)manager didUpdateSearchResults:(NSArray *)results {}
- (void)homebrewManager:(BPHomebrewManager *)manager shouldDisplayNoBrewMessage:(BOOL)yesOrNo {}

@end

#pragma mark -

@interface BPIncrementalReloadTests : XCTestCase
@property (strong) BPHomebrewManager *manager;
@property (strong) BPIncrementalReloadRecorder *recorder;
@end

@implementation BPIncrementalReloadTests

- (void)setUp
{
	[super setUp];
	// BPHomebrewManager is a singleton; reset what these tests touch.
	self.manager = [BPHomebrewManager sharedManager];
	self.recorder = [[BPIncrementalReloadRecorder alloc] init];
	self.manager.delegate = self.recorder;
	self.manager.installedFormulae = @[];
	self.manager.outdatedFormulae = @[];
	self.manager.installedCasks = @[];
}

- (void)tearDown
{
	self.manager.delegate = nil;
	[super tearDown];
}

- (NSArray<BPFormula *> *)oneFormulaNamed:(NSString *)name
{
	return @[ [BPFormula formulaWithName:name andVersion:@"1.0.0"] ];
}

#pragma mark - Publishing a list

- (void)testPublishingAListSetsItsPropertyAndTellsTheDelegate
{
	NSArray *installed = [self oneFormulaNamed:@"wget"];

	[self.manager publishList:installed
					  forMode:kBPListInstalled
				   generation:self.manager.currentReloadGeneration];

	XCTAssertEqualObjects(self.manager.installedFormulae, installed);
	XCTAssertEqualObjects(self.recorder.publishedModes, @[ @(kBPListInstalled) ]);
}

/// Each mode has to land in its own property. Getting this mapping wrong shows
/// casks in the formulae list, which is exactly the kind of thing a switch
/// statement with a missing case does silently.
- (void)testEachModeLandsInItsOwnProperty
{
	NSUInteger generation = self.manager.currentReloadGeneration;

	NSArray *formulae = [self oneFormulaNamed:@"wget"];
	NSArray *casks = [self oneFormulaNamed:@"chrome"];

	[self.manager publishList:formulae forMode:kBPListInstalled generation:generation];
	[self.manager publishList:casks forMode:kBPListInstalledCasks generation:generation];

	XCTAssertEqualObjects(self.manager.installedFormulae, formulae);
	XCTAssertEqualObjects(self.manager.installedCasks, casks);
	XCTAssertNotEqualObjects(self.manager.installedFormulae, self.manager.installedCasks);
}

- (void)testPublishingIsAnnouncedOncePerList
{
	NSUInteger generation = self.manager.currentReloadGeneration;

	[self.manager publishList:@[] forMode:kBPListInstalled generation:generation];
	[self.manager publishList:@[] forMode:kBPListOutdated generation:generation];
	[self.manager publishList:@[] forMode:kBPListInstalledCasks generation:generation];

	XCTAssertEqualObjects(self.recorder.publishedModes,
						  (@[ @(kBPListInstalled), @(kBPListOutdated), @(kBPListInstalledCasks) ]),
						  @"one callback per list, in the order they land");
}

#pragma mark - The generation guard

/// The reason the old design was safe: nothing published until the end, where
/// one generation check covered everything. Publishing incrementally means a
/// superseded reload can still have calls in flight, and its stale lists must
/// not overwrite the newer ones.
- (void)testAStaleGenerationPublishesNothing
{
	NSArray *fresh = [self oneFormulaNamed:@"current"];
	NSUInteger generation = self.manager.currentReloadGeneration;

	[self.manager publishList:fresh forMode:kBPListInstalled generation:generation];
	[self.recorder.publishedModes removeAllObjects];

	[self.manager publishList:[self oneFormulaNamed:@"stale"]
					  forMode:kBPListInstalled
				   generation:generation - 1];

	XCTAssertEqualObjects(self.manager.installedFormulae, fresh, @"a stale list must not overwrite");
	XCTAssertEqual(self.recorder.publishedModes.count, 0u, @"and must not be announced");
}

/// An empty list is a real result — nothing outdated — not a missing one.
- (void)testAnEmptyListStillPublishes
{
	self.manager.outdatedFormulae = [self oneFormulaNamed:@"stale"];

	[self.manager publishList:@[]
					  forMode:kBPListOutdated
				   generation:self.manager.currentReloadGeneration];

	XCTAssertEqual(self.manager.outdatedFormulae.count, 0u);
	XCTAssertEqualObjects(self.recorder.publishedModes, @[ @(kBPListOutdated) ]);
}

/// The callback is optional, so a delegate that does not implement it — or no
/// delegate at all — must not crash the reload.
- (void)testPublishingWithoutADelegateIsHarmless
{
	self.manager.delegate = nil;

	XCTAssertNoThrow([self.manager publishList:@[]
									   forMode:kBPListInstalled
									generation:self.manager.currentReloadGeneration]);
}

#pragma mark - Which sidebar row a list belongs to

// Publishing per list means refreshing one badge per list. The first attempt
// called reloadData on the whole outline, which clears an NSOutlineView's
// selection — so the app silently lost the row the user had reopened on, and
// then persisted Installed over it. Redrawing a single row avoids that, and
// this pins the mode -> row mapping it depends on.

- (void)testEveryReloadedListMapsToItsOwnSidebarRow
{
	BPSideBarController *sidebar = [[BPSideBarController alloc] init];

	NSArray<NSNumber *> *modes = @[ @(kBPListInstalled), @(kBPListOutdated), @(kBPListAll),
									@(kBPListLeaves), @(kBPListPinned), @(kBPListRepositories),
									@(kBPListInstalledCasks), @(kBPListOutdatedCasks), @(kBPListAllCasks) ];

	NSMutableSet *seen = [NSMutableSet set];

	for (NSNumber *mode in modes)
	{
		BPSidebarItem *item = [sidebar itemForListMode:(BPListMode)mode.integerValue];

		XCTAssertNotNil(item, @"mode %@ has no sidebar row", mode);
		XCTAssertFalse([seen containsObject:[NSValue valueWithNonretainedObject:item]],
					   @"mode %@ shares a row with an earlier mode", mode);
		[seen addObject:[NSValue valueWithNonretainedObject:item]];
	}
}

/// Search results are shown in place and have no row of their own; asking for
/// one must yield nil rather than some other list's row.
- (void)testSearchHasNoSidebarRow
{
	BPSideBarController *sidebar = [[BPSideBarController alloc] init];

	XCTAssertNil([sidebar itemForListMode:kBPListSearch]);
}

@end
