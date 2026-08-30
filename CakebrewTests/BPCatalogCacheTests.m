//
//  BPCatalogCacheTests.m
//  CakebrewTests
//
//  The 24h catalog cache reported stale data as fresh. -loadAllFormulaeCaches
//  ended with `return self.allFormulae != nil`, so once anything had populated
//  the arrays in memory it answered YES even on the branch that had just
//  deleted the file as expired. A long-running app — which the background
//  updater's periodic reload creates — therefore never refetched its catalog
//  past 24 hours, and since the file was gone, the next launch started cold at
//  80+ seconds.
//
//  These drive the real store/load against a real cache file.
//

#import <XCTest/XCTest.h>
#import "BPHomebrewManager.h"
#import "BPFormula.h"
#import "BPAppDelegate.h"

extern NSString *const kBPCacheLastUpdateKey;

@interface BPHomebrewManager (BPCatalogCacheTests)
- (BOOL)loadAllFormulaeCaches;
- (void)storeAllFormulaeCaches;
- (void)discardCatalogCache;
@end

@interface BPCatalogCacheTests : XCTestCase
@property (strong) BPHomebrewManager *manager;
@end

@implementation BPCatalogCacheTests

- (NSURL *)cacheFile
{
	return [[BPAppDelegate urlForApplicationCachesFolder] URLByAppendingPathComponent:@"allFormulae.cache.bin"];
}

- (void)setUp
{
	[super setUp];
	self.manager = [BPHomebrewManager sharedManager];
	[self.manager discardCatalogCache];
	self.manager.allFormulae = @[];
	self.manager.allCasks = @[];
}

- (void)tearDown
{
	[self.manager discardCatalogCache];
	self.manager.allFormulae = @[];
	self.manager.allCasks = @[];
	self.manager = nil;
	[super tearDown];
}

- (void)testAFreshlyStoredCacheLoadsBack
{
	self.manager.allFormulae = @[ [BPFormula formulaWithName:@"wget"] ];
	self.manager.allCasks = @[ [BPFormula formulaWithName:@"mockchrome"] ];
	[self.manager storeAllFormulaeCaches];

	self.manager.allFormulae = @[];
	self.manager.allCasks = @[];

	XCTAssertTrue([self.manager loadAllFormulaeCaches]);
	XCTAssertEqual(self.manager.allFormulae.count, 1u);
	XCTAssertEqual(self.manager.allCasks.count, 1u);
}

- (void)testNoCacheFileMeansNoCacheEvenWithArraysPopulated
{
	// The exact shape of the bug: memory populated, file gone.
	self.manager.allFormulae = @[ [BPFormula formulaWithName:@"wget"] ];
	[self.manager discardCatalogCache];

	XCTAssertFalse([self.manager loadAllFormulaeCaches],
				   @"a deleted cache is not a valid one, whatever is in memory");
}

- (void)testAnExpiredCacheIsNotReportedAsValid
{
	self.manager.allFormulae = @[ [BPFormula formulaWithName:@"wget"] ];
	[self.manager storeAllFormulaeCaches];

	// Backdate the archive past the 24h window by rewriting its stored date.
	NSData *data = [NSData dataWithContentsOfURL:[self cacheFile]];
	NSSet *classes = [NSSet setWithArray:@[[NSDictionary class], [NSArray class], [NSMutableArray class],
										   [BPFormula class], [NSString class], [NSURL class],
										   [NSNumber class], [NSDate class]]];
	NSMutableDictionary *dict = [[NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:NULL] mutableCopy];
	dict[@"BPCacheStoredDateKey"] = [NSDate dateWithTimeIntervalSinceNow:-(3600 * 25)];
	NSData *stale = [NSKeyedArchiver archivedDataWithRootObject:dict requiringSecureCoding:YES error:NULL];
	[stale writeToURL:[self cacheFile] atomically:YES];

	XCTAssertFalse([self.manager loadAllFormulaeCaches], @"25 hours old is stale");
}

- (void)testAVersionMismatchRebuildsRatherThanDecodingIntoTheWrongFields
{
	self.manager.allFormulae = @[ [BPFormula formulaWithName:@"wget"] ];
	[self.manager storeAllFormulaeCaches];

	NSData *data = [NSData dataWithContentsOfURL:[self cacheFile]];
	NSSet *classes = [NSSet setWithArray:@[[NSDictionary class], [NSArray class], [NSMutableArray class],
										   [BPFormula class], [NSString class], [NSURL class],
										   [NSNumber class], [NSDate class]]];
	NSMutableDictionary *dict = [[NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:NULL] mutableCopy];
	dict[@"BPCacheVersionKey"] = @(999);
	NSData *wrongVersion = [NSKeyedArchiver archivedDataWithRootObject:dict requiringSecureCoding:YES error:NULL];
	[wrongVersion writeToURL:[self cacheFile] atomically:YES];

	XCTAssertFalse([self.manager loadAllFormulaeCaches]);
}

- (void)testATruncatedArchiveIsDiscardedRatherThanCrashing
{
	// The old first write was non-atomic, so a crash mid-write left exactly
	// this to be unarchived on the next launch.
	[[NSData dataWithBytes:"garbage" length:7] writeToURL:[self cacheFile] atomically:YES];

	XCTAssertNoThrow([self.manager loadAllFormulaeCaches]);
	XCTAssertFalse([self.manager loadAllFormulaeCaches]);
}

- (void)testARebuildIsStampedWithTheCurrentTime
{
	// The store used to reuse the existing timestamp, so a forced rebuild wrote
	// fresh data carrying the old date and expired immediately.
	self.manager.allFormulae = @[ [BPFormula formulaWithName:@"wget"] ];
	[self.manager storeAllFormulaeCaches];

	NSInteger firstStamp = [[NSUserDefaults standardUserDefaults] integerForKey:kBPCacheLastUpdateKey];
	XCTAssertGreaterThan(firstStamp, 0);

	// Pretend the previous run was a day ago, then rebuild.
	[[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)([[NSDate date] timeIntervalSince1970] - 3600 * 30)
											   forKey:kBPCacheLastUpdateKey];
	[self.manager storeAllFormulaeCaches];

	NSTimeInterval age = [[NSDate date] timeIntervalSince1970] -
		(NSTimeInterval)[[NSUserDefaults standardUserDefaults] integerForKey:kBPCacheLastUpdateKey];
	XCTAssertLessThan(age, 60.0, @"a rebuild must be stamped now, not with the previous date");

	XCTAssertTrue([self.manager loadAllFormulaeCaches], @"and must therefore still be valid");
}

@end
