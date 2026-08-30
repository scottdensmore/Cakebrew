//
//	BPLoadingStatus.h
//	Cakebrew – The Homebrew GUI App for OS X
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
#import "BPHomebrewInterface.h"

NS_ASSUME_NONNULL_BEGIN

/**
 *  What the loading overlay says while a reload runs.
 *
 *  The overlay used to be an indeterminate spinner over the word "Loading". A
 *  cold cask catalog takes 80+ seconds, and for all of it the app was
 *  indistinguishable from one that had hung.
 */
@interface BPLoadingStatus : NSObject

/// The Localizable.strings key for the step that fetches `mode`, or nil for a
/// mode that is not part of a reload.
+ (nullable NSString *)localizationKeyForListMode:(BPListMode)mode;

/// The localized status line for that step. Falls back to the generic
/// "Loading…" for a mode with no step of its own.
+ (NSString *)statusForListMode:(BPListMode)mode;

/// Whether this step is slow enough that its status should say so. Only the
/// two full catalogs are: marking a fast step slow would train people to
/// ignore the warning on the one that means it.
+ (BOOL)isSlowListMode:(BPListMode)mode;

@end

NS_ASSUME_NONNULL_END
