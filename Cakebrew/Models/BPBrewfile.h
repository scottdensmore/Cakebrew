//
//	BPBrewfile.h
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
 *  What the app is willing to treat as a Brewfile.
 *
 *  Judged by name, because that is all a drop or an "Open With" gives before
 *  the file is read, and because Brewfiles have no extension and no distinct
 *  file type. Kept deliberately narrow: importing runs `brew bundle`, which
 *  installs whatever the file lists.
 */
@interface BPBrewfile : NSObject

/// YES for a file URL named `Brewfile` or `<something>.Brewfile`, either case.
/// Does not touch the filesystem, so a caller that needs the file to exist
/// checks that separately.
+ (BOOL)isBrewfileURL:(nullable NSURL *)url;

/// The Brewfiles among `urls`, in order. An open or a drop can carry several
/// files; the rest are ignored rather than the whole gesture refused. Never nil.
+ (NSArray<NSURL *> *)brewfileURLsFrom:(nullable NSArray<NSURL *> *)urls;

@end

NS_ASSUME_NONNULL_END
