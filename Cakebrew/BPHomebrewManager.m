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

NSNotificationName const BPHomebrewManagerDidPublishOutdatedSnapshotNotification = @"BPHomebrewManagerDidPublishOutdatedSnapshotNotification";
NSString *const BPOutdatedSnapshotFormulaeCountKey = @"formulae-count";
NSString *const BPOutdatedSnapshotCaskCountKey = @"cask-count";
NSString *const BPOutdatedSnapshotGenerationKey = @"generation";

/// Bumped whenever the archived shape changes, so a stale layout rebuilds
/// instead of decoding into the wrong fields. Raised to 2 with the
/// shortDescription coding-key fix.
static const NSInteger kBPCacheVersion = 2;

#define kBP_SECONDS_IN_A_DAY 86400

@interface BPHomebrewManager () <BPHomebrewInterfaceDelegate>
{
	NSString *_currentSearchQuery;
	BOOL _reloadInFlight;
	BOOL _reloadRequestedWhileRunning;
	NSUInteger _reloadGeneration;
	BOOL _pendingRebuildCache;
	NSUInteger _outdatedSnapshotGeneration;
	NSNumber *_outdatedSnapshotFormulaeCount;
	NSNumber *_outdatedSnapshotCaskCount;
	BOOL _didPublishOutdatedSnapshot;
	BOOL _discoveryInFlight;
	BPHomebrewDiscoveryResult _discoveryResult;
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

+ (BOOL)shouldStartReloadWhenInFlight:(BOOL)inFlight
{
	return !inFlight;
}

+ (BOOL)shouldPublishReloadGeneration:(NSUInteger)generation current:(NSUInteger)current
{
	return generation == current;
}

- (NSUInteger)currentReloadGeneration
{
	@synchronized (self)
	{
		return _reloadGeneration;
	}
}

- (void)cancelReload
{
	@synchronized (self)
	{
		// Superseding the generation is what makes the dying reload silent —
		// the same guard every publish already checks.
		_reloadGeneration++;
		_reloadRequestedWhileRunning = NO;
		_pendingRebuildCache = NO;
	}

	// A reload fans out ten concurrent brew calls, so -cancelCurrentOperation
	// is not enough: that one covers the single operation task.
	[[BPHomebrewInterface sharedInterface] cancelAllRunningTasks];

	if ([self.delegate respondsToSelector:@selector(homebrewManagerFinishedStepping:)])
	{
		[self.delegate homebrewManagerFinishedStepping:self];
	}
}

- (void)announceStepForMode:(BPListMode)mode generation:(NSUInteger)generation
{
	if (![BPHomebrewManager shouldPublishReloadGeneration:generation current:self.currentReloadGeneration])
	{
		return;
	}

	if (![NSThread isMainThread])
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[self announceStepForMode:mode generation:generation];
		});
		return;
	}

	if ([self.delegate respondsToSelector:@selector(homebrewManager:didBeginStepForMode:)])
	{
		[self.delegate homebrewManager:self didBeginStepForMode:mode];
	}
}

- (void)publishList:(NSArray *)list forMode:(BPListMode)mode generation:(NSUInteger)generation
{
	if (![BPHomebrewManager shouldPublishReloadGeneration:generation current:self.currentReloadGeneration])
	{
		// A superseded reload still has calls in flight. Publishing all at once
		// needed one check at the end; publishing per list needs one per list.
		return;
	}

	if (![NSThread isMainThread])
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[self publishList:list forMode:mode generation:generation];
		});
		return;
	}

	switch (mode)
	{
		case kBPListInstalled:      self.installedFormulae = list;      break;
		case kBPListLeaves:         self.leavesFormulae = list;         break;
		case kBPListOutdated:       self.outdatedFormulae = list;       break;
		case kBPListRepositories:   self.repositoriesFormulae = list;   break;
		case kBPListPinned:         self.pinnedFormulae = list;         break;
		case kBPListInstalledCasks: self.installedCasks = list;         break;
		case kBPListOutdatedCasks:  self.outdatedCasks = list;          break;
		case kBPListAll:            self.allFormulae = list;            break;
		case kBPListAllCasks:       self.allCasks = list;               break;

		case kBPListSearch:
			// Search results have their own delegate callback and never come
			// from a reload.
			return;
	}

	[self publishOutdatedSnapshotForList:list mode:mode generation:generation];

	if ([self.delegate respondsToSelector:@selector(homebrewManager:didPublishListForMode:)])
	{
		[self.delegate homebrewManager:self didPublishListForMode:mode];
	}
}

- (void)publishOutdatedSnapshotForList:(NSArray *)list mode:(BPListMode)mode generation:(NSUInteger)generation
{
	if (mode != kBPListOutdated && mode != kBPListOutdatedCasks) return;
	NSDictionary *snapshot;
	@synchronized (self)
	{
		// Property KVO can reenter and cancel or start another generation.
		if (generation != _reloadGeneration) return;
		if (_outdatedSnapshotGeneration != generation)
		{
			_outdatedSnapshotGeneration = generation;
			_outdatedSnapshotFormulaeCount = nil;
			_outdatedSnapshotCaskCount = nil;
			_didPublishOutdatedSnapshot = NO;
		}
		// nil is a failed/missing result; an empty array is a successful zero.
		if (!list || _didPublishOutdatedSnapshot) return;
		if (mode == kBPListOutdated) _outdatedSnapshotFormulaeCount = @(list.count);
		else _outdatedSnapshotCaskCount = @(list.count);
		if (!_outdatedSnapshotFormulaeCount || !_outdatedSnapshotCaskCount) return;

		snapshot = @{BPOutdatedSnapshotFormulaeCountKey: _outdatedSnapshotFormulaeCount,
			BPOutdatedSnapshotCaskCountKey: _outdatedSnapshotCaskCount,
			BPOutdatedSnapshotGenerationKey: @(generation)};
		// Reserve before calling observers, which may synchronously publish again.
		_didPublishOutdatedSnapshot = YES;
	}
	[NSNotificationCenter.defaultCenter postNotificationName:BPHomebrewManagerDidPublishOutdatedSnapshotNotification
		object:self userInfo:snapshot];
}

- (BPHomebrewInterface *)homebrewInterface
{
	return [BPHomebrewInterface sharedInterface];
}

- (BPHomebrewDiscoveryResult)discoveryResult
{
	@synchronized (self) { return _discoveryResult; }
}

- (BOOL)checkingHomebrew
{
	@synchronized (self) { return _discoveryInFlight; }
}

- (void)retryHomebrewDiscovery
{
	@synchronized (self) {
		if (_reloadInFlight) return;
		[self reloadFromInterfaceRebuildingCache:NO];
	}
}

- (void)reloadFromInterfaceRebuildingCache:(BOOL)shouldRebuildCache
{
	NSUInteger generation;
	BOOL needsDiscovery;

	@synchronized (self)
	{
		// Retry clicks and ordinary refresh requests cannot queue a second
		// pipeline while the installation check is still running.
		if (_discoveryInFlight) return;
		if (![BPHomebrewManager shouldStartReloadWhenInFlight:_reloadInFlight])
		{
			// Coalesce. Four callers can fire a reload and the background timer
			// only checks whether a brew *operation* is running, not whether a
			// reload already is.
			_reloadRequestedWhileRunning = YES;
			_pendingRebuildCache = _pendingRebuildCache || shouldRebuildCache;
			return;
		}

		_reloadInFlight = YES;
		generation = ++_reloadGeneration;
		needsDiscovery = _discoveryResult != BPHomebrewDiscoveryAvailable;
		_discoveryInFlight = needsDiscovery;
	}
	if (needsDiscovery) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if ([self.delegate respondsToSelector:@selector(homebrewManagerDidBeginDiscovery:)])
				[self.delegate homebrewManagerDidBeginDiscovery:self];
		});
	}

	NSUInteger previousCountOfAllFormulae = [self allFormulae].count;

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		BPHomebrewInterface *interface = [self homebrewInterface];
		interface.delegate = self;
		if (needsDiscovery) {
			BPHomebrewDiscoveryResult result = [interface discoverHomebrew];
			BOOL current;
			@synchronized (self) {
				current = generation == self->_reloadGeneration;
			}
			if (result != BPHomebrewDiscoveryAvailable || !current) {
				dispatch_async(dispatch_get_main_queue(), ^{
					@synchronized (self) {
						self->_discoveryInFlight = NO;
						self->_reloadInFlight = NO;
						self->_reloadRequestedWhileRunning = NO;
						self->_pendingRebuildCache = NO;
						if (generation != self->_reloadGeneration) return;
						self->_discoveryResult = result;
					}
					[self.delegate homebrewManager:self shouldDisplayNoBrewMessage:YES];
				});
				return; // No lists, services, cache read or cache write on failure.
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				@synchronized (self) {
					self->_discoveryInFlight = NO;
					if (generation != self->_reloadGeneration) return;
					self->_discoveryResult = result;
				}
				[self.delegate homebrewManager:self shouldDisplayNoBrewMessage:NO];
			});
		}

		// Ten blocking brew calls, each spawning its own login shell and Ruby
		// startup, ran back to back — about 7.8 s warm. Nothing here is
		// CPU-bound and the calls are independent, so they go out together.
		dispatch_queue_t fanOut = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
		dispatch_group_t group = dispatch_group_create();

		__block NSArray *services = nil;
		__block BOOL didFetchCatalogs = NO;

		// Each list publishes as it returns instead of waiting for the batch.
		// The installed list comes back in well under a second; it used to sit
		// behind a cold cask catalog, which can take 80.
		#define BP_FETCH_LIST(MODE) \
			dispatch_group_async(group, fanOut, ^{ \
				[self publishList:[interface listMode:MODE] forMode:MODE generation:generation]; \
			});

		// A reload after an operation used to be completely silent: the loading
		// overlay is built once at setup and torn down on the first finish, so
		// nothing marked the second one onwards.
		[self announceStepForMode:kBPListInstalled generation:generation];

		// The installed list is what the user is waiting to see, so it goes out
		// at a higher QoS than the rest. Eight login shells and eight Ruby
		// startups contending stretched it from ~0.9 s to over three; running
		// it ahead of the others recovers most of that without serialising the
		// batch, which is what pushed the *total* reload a second longer.
		dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			[self publishList:[interface listMode:kBPListInstalled]
					  forMode:kBPListInstalled
				   generation:generation];
		});

		BP_FETCH_LIST(kBPListLeaves)
		BP_FETCH_LIST(kBPListOutdated)
		BP_FETCH_LIST(kBPListRepositories)
		BP_FETCH_LIST(kBPListPinned)
		BP_FETCH_LIST(kBPListInstalledCasks)
		BP_FETCH_LIST(kBPListOutdatedCasks)

		// Services has no list mode and no sidebar badge, so it stays with the
		// final publish.
		dispatch_group_async(group, fanOut, ^{ services = [interface listServices]; });

		dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

		// The full catalogs share a 24h disk cache and refresh together. They
		// are fetched after the cheap lists so a cache hit skips them entirely.
		if (![self loadAllFormulaeCaches] || previousCountOfAllFormulae <= 100 || self.allCasks == nil || shouldRebuildCache) {
			didFetchCatalogs = YES;
			// The one step worth naming: `brew casks` can take 80+ seconds cold,
			// and silence for that long is indistinguishable from a hang.
			[self announceStepForMode:kBPListAllCasks generation:generation];
			BP_FETCH_LIST(kBPListAll)
			BP_FETCH_LIST(kBPListAllCasks)
			dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
		}

		#undef BP_FETCH_LIST

		dispatch_async(dispatch_get_main_queue(), ^{
			BOOL rerun = NO;
			BOOL rerunRebuild = NO;

			@synchronized (self)
			{
				self->_reloadInFlight = NO;
				rerun = self->_reloadRequestedWhileRunning;
				rerunRebuild = self->_pendingRebuildCache;
				self->_reloadRequestedWhileRunning = NO;
				self->_pendingRebuildCache = NO;
			}

			// Only the newest pipeline publishes. Every list has already gone
			// out through -publishList:forMode:generation:, which makes the
			// same check per list; this covers what is left.
			if ([BPHomebrewManager shouldPublishReloadGeneration:generation current:self->_reloadGeneration])
			{
				if (didFetchCatalogs) {
					// Archiving ~16k formulae was happening here, on the main
					// queue, while the first frame was being drawn.
					dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
						[self storeAllFormulaeCaches];
					});
				}

				[self setServices:services];

				[self.delegate homebrewManagerFinishedUpdating:self];

				if ([self.delegate respondsToSelector:@selector(homebrewManagerFinishedStepping:)])
				{
					[self.delegate homebrewManagerFinishedStepping:self];
				}
			}

			if (rerun)
			{
				[self reloadFromInterfaceRebuildingCache:rerunRebuild];
			}
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
