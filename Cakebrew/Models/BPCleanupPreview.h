//
//	BPCleanupPreview.h
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

NS_ASSUME_NONNULL_BEGIN

/**
 *  What `brew cleanup --dry-run` says it would delete.
 *
 *  Cleanup permanently removes cached downloads and old installed versions, so
 *  the app asks first — and this is what it asks about. The parse is
 *  deliberately conservative: anything it cannot read becomes zero rather than
 *  a guess, because a wrong number in the confirmation sheet is worse than no
 *  number.
 */
@interface BPCleanupPreview : NSObject

/// Parses the output of `brew cleanup --dry-run`. Never returns nil; unreadable
/// or empty output yields an empty preview.
+ (instancetype)previewFromOutput:(nullable NSString *)output;

/// How many things brew would remove.
@property (readonly) NSUInteger itemCount;

/// What brew says would be freed, in bytes. Zero when brew printed no summary
/// line — which happens, and does not mean there is nothing to remove.
@property (readonly) unsigned long long reclaimableBytes;

/// The paths, in the order brew listed them, without the size suffix.
@property (readonly, copy) NSArray<NSString *> *paths;

/// YES when there is nothing to do, so the app can say so instead of running a
/// cleanup that deletes nothing.
@property (readonly, getter=isEmpty) BOOL empty;

@end

NS_ASSUME_NONNULL_END
