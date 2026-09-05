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
@property (strong) NSMutableArray<NSNumber *> *announcedSteps;
@property (assign) NSUInteger finishedCount;
@property (copy) void (^onPublication)(BPHomebrewManager *, BPListMode);
@end

@implementation BPIncrementalReloadRecorder

- (instancetype)init
{
	self = [super init];
	if (self) {
		_publishedModes = [NSMutableArray array];
		_announcedSteps = [NSMutableArray array];
	}
	return self;
}

- (void)homebrewManager:(BPHomebrewManager *)manager didPublishListForMode:(BPListMode)mode
{
	[self.publishedModes addObject:@(mode)];
	if (self.onPublication) self.onPublication(manager, mode);
}

- (void)homebrewManager:(BPHomebrewManager *)manager didBeginStepForMode:(BPListMode)mode
{
	[self.announcedSteps addObject:@(mode)];
}

- (void)homebrewManagerFinishedUpdating:(BPHomebrewManager *)manager { self.finishedCount++; }
- (void)homebrewManager:(BPHomebrewManager *)manager didUpdateSearchResults:(NSArray *)results {}
- (void)homebrewManager:(BPHomebrewManager *)manager shouldDisplayNoBrewMessage:(BOOL)yesOrNo {}

@end

#pragma mark -

@interface BPIncrementalReloadTests : XCTestCase
@property (strong) BPHomebrewManager *manager;
@property (strong) BPIncrementalReloadRecorder *recorder;
@property (strong) NSMutableArray<NSDictionary *> *outdatedSnapshots;
@property (strong) id snapshotObserver;
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
	self.manager.outdatedCasks = @[];
	[self.manager cancelReload];
	self.outdatedSnapshots = [NSMutableArray array];
	NSMutableArray *snapshots = self.outdatedSnapshots;
	self.snapshotObserver = [NSNotificationCenter.defaultCenter
		addObserverForName:@"BPHomebrewManagerDidPublishOutdatedSnapshotNotification"
		object:self.manager queue:nil usingBlock:^(NSNotification *notification) {
			XCTAssertTrue(NSThread.isMainThread);
			[snapshots addObject:notification.userInfo];
		}];
}

- (void)tearDown
{
	[NSNotificationCenter.defaultCenter removeObserver:self.snapshotObserver];
	self.manager.delegate = nil;
	[super tearDown];
}

- (NSArray<BPFormula *> *)oneFormulaNamed:(NSString *)name
{
	return @[ [BPFormula formulaWithName:name andVersion:@"1.0.0"] ];
}

#pragma mark - Coherent outdated snapshots

- (void)assertSnapshotWaitsForBothListsWithCasksFirst:(BOOL)casksFirst
{
	NSUInteger generation = self.manager.currentReloadGeneration;
	NSArray *formulae = [self oneFormulaNamed:@"formula"];
	NSArray *casks = @[[BPFormula formulaWithName:@"cask-a"], [BPFormula formulaWithName:@"cask-b"]];
	[self.manager publishList:casksFirst ? casks : formulae
		forMode:casksFirst ? kBPListOutdatedCasks : kBPListOutdated generation:generation];
	XCTAssertEqual(self.outdatedSnapshots.count, 0u);
	[self.manager publishList:casksFirst ? formulae : casks
		forMode:casksFirst ? kBPListOutdated : kBPListOutdatedCasks generation:generation];
	XCTAssertEqualObjects(self.outdatedSnapshots,
		(@[@{@"formulae-count": @1, @"cask-count": @2, @"generation": @(generation)}]));
	XCTAssertEqual(self.recorder.finishedCount, 0u, @"the pair must not wait for the slow catalog or final reload callback");
}

- (void)testOutdatedSnapshotWaitsForFormulaeWhenCasksFinishFirst
{
	[self assertSnapshotWaitsForBothListsWithCasksFirst:YES];
}

- (void)testOutdatedSnapshotWaitsForCasksWhenFormulaeFinishFirst
{
	[self assertSnapshotWaitsForBothListsWithCasksFirst:NO];
}

- (void)testEmptyOutdatedListsPublishAValidZeroSnapshot
{
	NSUInteger generation = self.manager.currentReloadGeneration;
	[self.manager publishList:@[] forMode:kBPListOutdated generation:generation];
	[self.manager publishList:@[] forMode:kBPListOutdatedCasks generation:generation];
	XCTAssertEqualObjects(self.outdatedSnapshots,
		(@[@{@"formulae-count": @0, @"cask-count": @0, @"generation": @(generation)}]));
}

- (void)testNilOutdatedListCannotCompleteTheSnapshot
{
	NSUInteger generation = self.manager.currentReloadGeneration;
	[self.manager publishList:nil forMode:kBPListOutdated generation:generation];
	[self.manager publishList:@[] forMode:kBPListOutdatedCasks generation:generation];
	XCTAssertEqual(self.outdatedSnapshots.count, 0u, @"nil is a missing result, not a successful empty list");
}

- (void)testCanceledPartialPairCannotCompleteOrLeakIntoTheNextGeneration
{
	NSUInteger oldGeneration = self.manager.currentReloadGeneration;
	[self.manager publishList:[self oneFormulaNamed:@"old"] forMode:kBPListOutdated generation:oldGeneration];
	[self.manager cancelReload];
	[self.manager publishList:@[] forMode:kBPListOutdatedCasks generation:oldGeneration];
	XCTAssertEqual(self.outdatedSnapshots.count, 0u);
	NSUInteger generation = self.manager.currentReloadGeneration;
	[self.manager publishList:@[] forMode:kBPListOutdatedCasks generation:generation];
	XCTAssertEqual(self.outdatedSnapshots.count, 0u, @"the new generation cannot borrow the old formula count");
	[self.manager publishList:@[] forMode:kBPListOutdated generation:generation];
	XCTAssertEqualObjects(self.outdatedSnapshots,
		(@[@{@"formulae-count": @0, @"cask-count": @0, @"generation": @(generation)}]));
}

- (void)testEveryGenerationRequiresItsOwnOutdatedPair
{
	NSUInteger generation = self.manager.currentReloadGeneration;
	[self.manager publishList:@[] forMode:kBPListOutdated generation:generation];
	[self.manager publishList:@[] forMode:kBPListOutdatedCasks generation:generation];
	[self.manager cancelReload];
	generation = self.manager.currentReloadGeneration;
	[self.manager publishList:[self oneFormulaNamed:@"new"] forMode:kBPListOutdated generation:generation];
	XCTAssertEqual(self.outdatedSnapshots.count, 1u);
	[self.manager publishList:@[] forMode:kBPListOutdatedCasks generation:generation];
	XCTAssertEqual(self.outdatedSnapshots.count, 2u);
	XCTAssertEqualObjects(self.outdatedSnapshots.lastObject,
		(@{@"formulae-count": @1, @"cask-count": @0, @"generation": @(generation)}));
}

- (void)testOutdatedSnapshotIsImmutableAndEmittedBeforeReentrantPublication
{
	NSUInteger generation = self.manager.currentReloadGeneration;
	__block NSUInteger emissions = 0;
	BPHomebrewManager *manager = self.manager;
	id observer = [NSNotificationCenter.defaultCenter
		addObserverForName:@"BPHomebrewManagerDidPublishOutdatedSnapshotNotification"
		object:manager queue:nil usingBlock:^(NSNotification *notification) {
			emissions += 1;
			if (emissions == 1) {
				[manager publishList:@[] forMode:kBPListOutdated generation:generation];
				[manager publishList:@[] forMode:kBPListOutdatedCasks generation:generation];
			}
		}];
	[self.manager publishList:[self oneFormulaNamed:@"formula"] forMode:kBPListOutdated generation:generation];
	[self.manager publishList:[self oneFormulaNamed:@"cask"] forMode:kBPListOutdatedCasks generation:generation];
	[NSNotificationCenter.defaultCenter removeObserver:observer];
	XCTAssertEqual(emissions, 1u, @"mark the snapshot emitted before notifying reentrant observers");
	XCTAssertEqualObjects(self.outdatedSnapshots,
		(@[@{@"formulae-count": @1, @"cask-count": @1, @"generation": @(generation)}]));
}

- (void)testReentrantCancellationDiscardsAnIncompleteOutdatedSnapshot
{
	NSUInteger generation = self.manager.currentReloadGeneration;
	self.recorder.onPublication = ^(BPHomebrewManager *manager, BPListMode mode) {
		if (mode == kBPListOutdated) [manager cancelReload];
	};
	[self.manager publishList:@[] forMode:kBPListOutdated generation:generation];
	[self.manager publishList:@[] forMode:kBPListOutdatedCasks generation:generation];
	XCTAssertEqual(self.outdatedSnapshots.count, 0u);
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

#pragma mark - Announcing a step

// A reload after an operation — a pin, an install, the hourly timer — used to
// be completely silent: the loading overlay is built once at setup and torn
// down on the first published list, so nothing marked any reload after the
// first. Announcing a step is what the footer shows.

- (void)testAnnouncingAStepTellsTheDelegate
{
	[self.manager announceStepForMode:kBPListAllCasks generation:self.manager.currentReloadGeneration];

	XCTAssertEqualObjects(self.recorder.announcedSteps, @[ @(kBPListAllCasks) ]);
}

/// Same hazard as publishing: a superseded reload still has calls in flight,
/// and its steps must not talk over the newer reload's.
- (void)testAStaleGenerationAnnouncesNothing
{
	[self.manager announceStepForMode:kBPListInstalled
						   generation:self.manager.currentReloadGeneration - 1];

	XCTAssertEqual(self.recorder.announcedSteps.count, 0u);
}

- (void)testAnnouncingWithoutADelegateIsHarmless
{
	self.manager.delegate = nil;

	XCTAssertNoThrow([self.manager announceStepForMode:kBPListInstalled
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
