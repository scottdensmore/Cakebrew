//
//	BPHomebrewManager.h
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

#import <Foundation/Foundation.h>
#import "BPFormula.h"
#import "BPService.h"

@class BPHomebrewManager;

typedef NS_ENUM(NSInteger, BPFormulaStatus) {
	kBPFormulaNotInstalled,
	kBPFormulaInstalled,
	kBPFormulaOutdated,
};

@protocol BPHomebrewManagerDelegate <NSObject>

- (void)homebrewManagerFinishedUpdating:(BPHomebrewManager*)manager;
- (void)homebrewManager:(BPHomebrewManager *)manager didUpdateSearchResults:(NSArray *)searchResults;
- (void)homebrewManager:(BPHomebrewManager *)manager shouldDisplayNoBrewMessage:(BOOL)yesOrNo;

@end

@interface BPHomebrewManager : NSObject

@property (strong) NSArray<BPFormula*> *installedFormulae;
@property (strong) NSArray<BPFormula*> *outdatedFormulae;
@property (strong) NSArray<BPFormula*> *allFormulae;
@property (strong) NSArray<BPFormula*> *leavesFormulae;
@property (strong) NSArray<BPFormula*> *searchFormulae;
@property (strong) NSArray<BPFormula*> *repositoriesFormulae;
@property (strong) NSArray<BPFormula*> *pinnedFormulae;
@property (strong) NSArray<BPFormula*> *installedCasks;
@property (strong) NSArray<BPFormula*> *outdatedCasks;
@property (strong) NSArray<BPFormula*> *allCasks;
@property (strong) NSArray<BPService*> *services;

@property (weak) id<BPHomebrewManagerDelegate> delegate;

+ (instancetype)sharedManager;
+ (instancetype)alloc __attribute__((unavailable("alloc not available, call sharedManager instead")));
- (instancetype)init __attribute__((unavailable("init not available, call sharedManager instead")));
+ (instancetype)new __attribute__((unavailable("new not available, call sharedManager instead")));

- (void)reloadFromInterfaceRebuildingCache:(BOOL)shouldRebuildCache;

/// Whether a request should start a pipeline. A request arriving while one runs
/// coalesces into a single pending re-run instead.
+ (BOOL)shouldStartReloadWhenInFlight:(BOOL)inFlight;

/// Whether a finished pipeline may publish. Only the newest may: results used
/// to be published by whichever finished last, so a slower older snapshot could
/// clobber a newer one.
+ (BOOL)shouldPublishReloadGeneration:(NSUInteger)generation current:(NSUInteger)current;
- (void)updateSearchWithName:(NSString *)name;

/**
 *  Catalog entries whose name contains `query`, formulae first then casks.
 *
 *  Casks were never searched, so typing a cask token returned nothing even
 *  though the browse lists showed it. Matches keep their `cask` flag, which is
 *  what statusForFormula:, the detail pane and operation dispatch branch on.
 */
+ (NSArray<BPFormula *> *)formulae:(NSArray<BPFormula *> *)formulae
							 casks:(NSArray<BPFormula *> *)casks
					 matchingQuery:(NSString *)query;

/// Whether results computed for `query` are still wanted. Scanning 8.5k names
/// is slow enough that an earlier keystroke can finish after a later one.
+ (BOOL)shouldPublishResultsForQuery:(NSString *)query currentQuery:(NSString *)currentQuery;

- (BPFormulaStatus)statusForFormula:(BPFormula*)formula;
- (BOOL)isFormulaPinned:(BPFormula*)formula;

/// Forgets the current query, so results still in flight are discarded.
- (void)cancelSearch;

- (void)cleanUp;

@end
