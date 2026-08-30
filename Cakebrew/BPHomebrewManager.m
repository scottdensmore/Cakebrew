//
//	BPHomebrewManager.m
//	Cakebrew – The Homebrew GUI App for OS X
//
//	Created by Bruno Philipe on 4/3/14.
//	Copyright (c) 2014 Bruno Philipe. All rights reserved.
//
//	This program is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//
//	This program is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "BPHomebrewManager.h"
#import "BPHomebrewInterface.h"
#import "BPAppDelegate.h"
#import "BPFormulaOption.h"

NSString *const kBPCacheLastUpdateKey = @"BPCacheLastUpdateKey";
NSString *const kBPCacheDataKey	= @"BPCacheDataKey";
NSString *const kBPCacheCasksDataKey = @"BPCacheCasksDataKey";
NSString *const kBPCacheVersionKey = @"BPCacheVersionKey";
NSString *const kBPCacheStoredDateKey = @"BPCacheStoredDateKey";

/// Bumped whenever the archived shape changes, so a stale layout rebuilds
/// instead of decoding into the wrong fields. Raised to 2 with the
/// shortDescription coding-key fix.
static const NSInteger kBPCacheVersion = 2;

#define kBP_SECONDS_IN_A_DAY 86400

@interface BPHomebrewManager () <BPHomebrewInterfaceDelegate>
{
	NSString *_currentSearchQuery;
}
@end

@implementation BPHomebrewManager

+ (BPHomebrewManager *)sharedManager
{
	@synchronized(self)
	{
        static dispatch_once_t once;
        static BPHomebrewManager *instance;
        dispatch_once(&once, ^ { instance = [[super allocWithZone:NULL] initUniqueInstance]; });
        return instance;
	}
}

- (instancetype)initUniqueInstance
{
	self = [super init];
	if (self) {
		
	}
	return self;
}

+ (instancetype)allocWithZone:(NSZone *)zone
{
	return [self sharedManager];
}

- (instancetype)copyWithZone:(NSZone *)zone
{
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadFromInterfaceRebuildingCache:(BOOL)shouldRebuildCache;
{
	NSUInteger previousCountOfAllFormulae = [self allFormulae].count;

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		[[BPHomebrewInterface sharedInterface] setDelegate:self];
		
		NSArray *installedFormulae = [[BPHomebrewInterface sharedInterface] listMode:kBPListInstalled];
		NSArray *leavesFormulae = [[BPHomebrewInterface sharedInterface] listMode:kBPListLeaves];
		NSArray *outdatedFormulae = [[BPHomebrewInterface sharedInterface] listMode:kBPListOutdated];
		NSArray *repositoriesFormulae = [[BPHomebrewInterface sharedInterface] listMode:kBPListRepositories];
		NSArray *pinnedFormulae = [[BPHomebrewInterface sharedInterface] listMode:kBPListPinned];
		NSArray *installedCasks = [[BPHomebrewInterface sharedInterface] listMode:kBPListInstalledCasks];
		NSArray *outdatedCasks = [[BPHomebrewInterface sharedInterface] listMode:kBPListOutdatedCasks];
		NSArray *services = [[BPHomebrewInterface sharedInterface] listServices];
		NSArray *allFormulae = nil;
		NSArray *allCasks = nil;

		// The full catalogs (`brew formulae` / `brew casks`) are slow, so both
		// ride the same 24h disk cache and refresh together. The allCasks nil
		// check refreshes a warm cache written before casks were cached.
		if (![self loadAllFormulaeCaches] || previousCountOfAllFormulae <= 100 || self.allCasks == nil || shouldRebuildCache) {
			allFormulae = [[BPHomebrewInterface sharedInterface] listMode:kBPListAll];
			allCasks = [[BPHomebrewInterface sharedInterface] listMode:kBPListAllCasks];
		}

		dispatch_async(dispatch_get_main_queue(), ^{

			if (allFormulae != nil) {
				[self setAllFormulae:allFormulae];
				[self setAllCasks:allCasks];

				// Archiving ~16k formulae was happening here, on the main
				// queue, while the first frame was being drawn.
				dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
					[self storeAllFormulaeCaches];
				});
			}

			[self setInstalledFormulae:installedFormulae];
			[self setLeavesFormulae:leavesFormulae];
			[self setOutdatedFormulae:outdatedFormulae];
			[self setRepositoriesFormulae:repositoriesFormulae];
			[self setPinnedFormulae:pinnedFormulae];
			[self setInstalledCasks:installedCasks];
			[self setOutdatedCasks:outdatedCasks];
			[self setServices:services];

			[self.delegate homebrewManagerFinishedUpdating:self];
		});
	});
}

+ (NSArray<BPFormula *> *)formulae:(NSArray<BPFormula *> *)formulae
							 casks:(NSArray<BPFormula *> *)casks
					 matchingQuery:(NSString *)query
{
	if (query.length == 0)
	{
		return @[];
	}

	NSMutableArray<BPFormula *> *matches = [NSMutableArray array];
	// Formulae first, then casks, so the two namespaces aren't interleaved.
	for (NSArray<BPFormula *> *namespace in @[ formulae ?: @[], casks ?: @[] ])
	{
		for (BPFormula *entry in namespace)
		{
			if ([entry.name rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound)
			{
				[matches addObject:entry];
			}
		}
	}
	return matches;
}

+ (BOOL)shouldPublishResultsForQuery:(NSString *)query currentQuery:(NSString *)currentQuery
{
	return currentQuery != nil && [query isEqualToString:currentQuery];
}

- (void)updateSearchWithName:(NSString *)name
{
	// Remembered so a slower earlier keystroke cannot overwrite a later one.
	@synchronized (self) { _currentSearchQuery = [name copy]; }

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSArray<BPFormula *> *matches = [BPHomebrewManager formulae:self.allFormulae
															  casks:self.allCasks
													  matchingQuery:name];

		dispatch_async(dispatch_get_main_queue(), ^{
			NSString *current;
			@synchronized (self) { current = self->_currentSearchQuery; }
			if (![BPHomebrewManager shouldPublishResultsForQuery:name currentQuery:current])
			{
				return;
			}

			self->_searchFormulae = matches;
			[self.delegate homebrewManager:self didUpdateSearchResults:matches];
		});
	});
}

- (void)cancelSearch
{
	@synchronized (self) { _currentSearchQuery = nil; }
}

/**
 Returns `YES` if cache exists, was created less than 24 hours ago and was loaded successfully. Otherwise returns `NO`.
 */
- (BOOL)loadAllFormulaeCaches
{
	NSURL *cachesFolder = [BPAppDelegate urlForApplicationCachesFolder];
	NSURL *allFormulaeFile = [cachesFolder URLByAppendingPathComponent:@"allFormulae.cache.bin"];

	if (!allFormulaeFile || ![[NSFileManager defaultManager] fileExistsAtPath:allFormulaeFile.relativePath])
	{
		return NO;
	}

	NSData *data = [NSData dataWithContentsOfURL:allFormulaeFile];
	NSError *error = nil;
	NSSet *classes = [NSSet setWithArray:@[[NSDictionary class], [NSArray class], [NSMutableArray class],
										   [BPFormula class], [NSString class], [NSURL class],
										   [NSNumber class], [NSDate class], [BPFormulaOption class]]];
	NSDictionary *cacheDict = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:&error];

	if (error || !cacheDict)
	{
		NSLog(@"Discarding unreadable catalog cache: %@", error.localizedDescription);
		[self discardCatalogCache];
		return NO;
	}

	// A layout change must rebuild rather than decode into the wrong fields.
	if ([cacheDict[kBPCacheVersionKey] integerValue] != kBPCacheVersion)
	{
		[self discardCatalogCache];
		return NO;
	}

	// The timestamp lives in the archive, so validity and data cannot diverge —
	// they used to be a defaults key and a file that could be deleted apart.
	NSDate *storedDate = cacheDict[kBPCacheStoredDateKey];
	if (![storedDate isKindOfClass:[NSDate class]] ||
		[[NSDate date] timeIntervalSinceDate:storedDate] > kBP_SECONDS_IN_A_DAY)
	{
		[self discardCatalogCache];
		return NO;
	}

	NSArray *formulae = cacheDict[kBPCacheDataKey];
	if (![formulae isKindOfClass:[NSArray class]])
	{
		[self discardCatalogCache];
		return NO;
	}

	self.allFormulae = formulae;
	self.allCasks = cacheDict[kBPCacheCasksDataKey];

	// Whether a *fresh file was read*, not whether memory happens to be
	// populated. Returning the latter meant a long-running app saw its expired
	// cache as valid and never refetched the catalog — while having just
	// deleted the file, so the next launch started cold.
	return YES;
}

- (void)discardCatalogCache
{
	NSURL *cachesFolder = [BPAppDelegate urlForApplicationCachesFolder];
	NSURL *allFormulaeFile = [cachesFolder URLByAppendingPathComponent:@"allFormulae.cache.bin"];
	if (allFormulaeFile)
	{
		[[NSFileManager defaultManager] removeItemAtURL:allFormulaeFile error:nil];
	}
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:kBPCacheLastUpdateKey];
}

- (void)storeAllFormulaeCaches
{
	if (!self.allFormulae)
	{
		return;
	}

	NSURL *cachesFolder = [BPAppDelegate urlForApplicationCachesFolder];
	if (!cachesFolder)
	{
		NSLog(@"Could not store cache file. BPAppDelegate function returned nil!");
		return;
	}

	NSURL *allFormulaeFile = [cachesFolder URLByAppendingPathComponent:@"allFormulae.cache.bin"];

	// Always the current date. Reusing the stored one meant a forced rebuild
	// stamped fresh data with the old date, so it expired immediately.
	NSDictionary *cacheDict = @{ kBPCacheVersionKey: @(kBPCacheVersion),
								 kBPCacheStoredDateKey: [NSDate date],
								 kBPCacheDataKey: self.allFormulae,
								 kBPCacheCasksDataKey: self.allCasks ?: @[] };

	NSError *error = nil;
	NSData *cacheData = [NSKeyedArchiver archivedDataWithRootObject:cacheDict
											 requiringSecureCoding:YES
															 error:&error];
	if (error || !cacheData)
	{
		NSLog(@"Failed encoding data: %@", [error localizedDescription]);
		return;
	}

	// Atomic in both cases. The create path was not, so a crash mid-write left
	// a truncated archive to be unarchived next launch.
	if (![cacheData writeToURL:allFormulaeFile options:NSDataWritingAtomic error:&error])
	{
		NSLog(@"Failed writing cache: %@", error.localizedDescription);
		return;
	}

	[[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)[[NSDate date] timeIntervalSince1970]
											   forKey:kBPCacheLastUpdateKey];
}

- (NSInteger)searchForFormula:(BPFormula*)formula inArray:(NSArray*)array
{
	NSUInteger index = 0;
	
	for (BPFormula* item in array)
	{
		if ([[item installedName] isEqualToString:[formula installedName]])
		{
			return index;
		}
		
		index++;
	}
	
	return -1;
}

- (BPFormulaStatus)statusForFormula:(BPFormula*)formula
{
	// Casks are tracked in their own lists; a cask must never read the
	// formula lists (names can collide across the two namespaces).
	NSArray *installed = formula.cask ? self.installedCasks : self.installedFormulae;
	NSArray *outdated  = formula.cask ? self.outdatedCasks  : self.outdatedFormulae;

	if ([self searchForFormula:formula inArray:installed] >= 0)
	{
		if ([self searchForFormula:formula inArray:outdated] >= 0)
		{
			return kBPFormulaOutdated;
		}
		else
		{
			return kBPFormulaInstalled;
		}
	}
	else
	{
		return kBPFormulaNotInstalled;
	}
}

- (BOOL)isFormulaPinned:(BPFormula*)formula
{
	return [self searchForFormula:formula inArray:self.pinnedFormulae] >= 0;
}

- (void)cleanUp
{
	[[BPHomebrewInterface sharedInterface] cleanup];
}

#pragma - Homebrew Interface Delegate

- (void)homebrewInterfaceDidUpdateFormulaeRebuildingCatalogs:(BOOL)shouldRebuildCatalogs
{
	// Only operations that change what exists pay for the catalog refetch;
	// everything else is picked up by the cheap list calls.
	[self reloadFromInterfaceRebuildingCache:shouldRebuildCatalogs];
}

- (void)homebrewInterfaceShouldDisplayNoBrewMessage:(BOOL)yesOrNo
{
	if (self.delegate) {
		[self.delegate homebrewManager:self shouldDisplayNoBrewMessage:yesOrNo];
	}
}

@end
