//
//  BPPreferences.h
//  Cakebrew
//
//	This program is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//
//	This program is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with this program.	If not, see <http://www.gnu.org/licenses/>.
//

#import <Foundation/Foundation.h>

extern NSString *const kBPBackgroundCheckEnabledKey;
extern NSString *const kBPBackgroundCheckIntervalKey;
extern NSString *const kBPGreedyCaskUpgradesKey;

/**
 *  User settings, backed by NSUserDefaults. Call +registerDefaults once at
 *  launch so the accessors observe sane fallbacks before the user has
 *  touched anything.
 */
@interface BPPreferences : NSObject

+ (void)registerDefaults;

/** Periodically check for outdated packages in the background (default YES). */
+ (BOOL)backgroundCheckEnabled;
+ (void)setBackgroundCheckEnabled:(BOOL)enabled;

/** Background check interval in seconds (default 21600 = 6 hours). */
+ (NSTimeInterval)backgroundCheckInterval;
+ (void)setBackgroundCheckInterval:(NSTimeInterval)interval;

/** Include auto-updating casks when listing outdated casks (default NO). */
/// The sidebar row the user last had selected, so the app reopens where they
/// left it. Stored raw; validate with +[BPSideBarController restorableRowFrom:rowCount:]
/// before selecting, since rows are outline indices that can shift.
+ (NSInteger)lastSelectedSidebarRow;
+ (void)setLastSelectedSidebarRow:(NSInteger)row;

/// The column identifier the list is sorted by, or nil for the natural order
/// brew returned. Paired with +sortAscending.
+ (NSString *)sortColumnIdentifier;
+ (void)setSortColumnIdentifier:(NSString *)identifier;
+ (BOOL)sortAscending;
+ (void)setSortAscending:(BOOL)ascending;

/// Whether the cask uninstall sheet's "also remove preferences and support
/// files" box is ticked. Off by default — zap deletes more than the app.
+ (BOOL)zapCasksOnUninstall;
+ (void)setZapCasksOnUninstall:(BOOL)zap;

+ (BOOL)greedyCaskUpgrades;
+ (void)setGreedyCaskUpgrades:(BOOL)greedy;

@end
