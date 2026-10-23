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
#import "BPHomebrewInterface.h"

#ifndef BPHomebrewManagerDidPublishOutdatedSnapshotNotification
#define BPHomebrewManagerDidPublishOutdatedSnapshotNotification @"BPHomebrewManagerDidPublishOutdatedSnapshotNotification"
#endif
#ifndef BPOutdatedSnapshotFormulaeCountKey
#define BPOutdatedSnapshotFormulaeCountKey @"formulae-count"
#endif
#ifndef BPOutdatedSnapshotCaskCountKey
#define BPOutdatedSnapshotCaskCountKey @"cask-count"
#endif
#ifndef BPOutdatedSnapshotGenerationKey
#define BPOutdatedSnapshotGenerationKey @"generation"
#endif
#ifndef BPHomebrewManagerUpdatesSnapshotDidChangeNotification
#define BPHomebrewManagerUpdatesSnapshotDidChangeNotification @"BPHomebrewManagerUpdatesSnapshotDidChangeNotification"
#endif
#ifndef kBPCacheLastUpdateKey
#define kBPCacheLastUpdateKey @"BPCacheLastUpdateKey"
#endif
#ifndef kBPCacheDataKey
#define kBPCacheDataKey @"BPCacheDataKey"
#endif
#ifndef kBPCacheCasksDataKey
#define kBPCacheCasksDataKey @"BPCacheCasksDataKey"
#endif
#ifndef kBPCacheVersionKey
#define kBPCacheVersionKey @"BPCacheVersionKey"
#endif
#ifndef kBPCacheStoredDateKey
#define kBPCacheStoredDateKey @"BPCacheStoredDateKey"
#endif

#ifdef BP_BRIDGING_HEADER_IMPORT
@class BPHomebrewManager;
@protocol BPHomebrewManagerDelegate;
#else
#import "BPFormulaInformation-Swift.h"
#endif
