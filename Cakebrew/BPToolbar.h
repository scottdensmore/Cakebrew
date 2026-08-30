//
//  BPToolbar.h
//  Cakebrew
//
//  Created by Marek Hrusovsky on 16/08/15.
//	Copyright (c) 2014 Bruno Philipe. All rights reserved.
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

#import <Cocoa/Cocoa.h>

@protocol BPToolbarProtocol <NSObject>

@required
- (void)performSearchWithString:(NSString *)search;
- (void)updateHomebrew:(id)sender;
- (void)upgradeSelectedFormulae:(id)sender;
- (void)showFormulaInfo:(id)sender;
- (void)tapRepository:(id)sender;
- (void)untapRepository:(id)sender;
- (void)cancelReload:(id)sender;
- (void)installFormula:(id)sender;
- (void)uninstallFormula:(id)sender;
@end

@interface BPToolbar : NSToolbar <NSToolbarDelegate>

typedef NS_ENUM(NSUInteger, BPToolbarMode) {
	BPToolbarModeInitial,
	BPToolbarModeDefault,
	BPToolbarModeInstall,
	BPToolbarModeUninstall,
	BPToolbarModeUpdateSingle,
	BPToolbarModeUpdateMany,
	BPToolbarModeTap,
	BPToolbarModeUntap
};

@property (nonatomic, weak) id controller;

- (void)configureForMode:(BPToolbarMode)mode;

/// The identifier of the Cancel item shown while a reload runs.
+ (NSString *)cancelReloadItemIdentifier;

/// Where that item sits in the default list. The toolbar inserts at this index,
/// so it has to agree with the list or a later removal takes the wrong item.
+ (NSUInteger)cancelReloadItemIndex;

/// The default toolbar contents, with or without the Cancel item.
+ (NSArray<NSString *> *)defaultItemIdentifiersShowingCancel:(BOOL)showingCancel;

/// Shows or hides the Cancel item. Idempotent — a reload can be announced more
/// than once, and a second insert would leave a duplicate behind.
- (void)setShowsCancelReload:(BOOL)showsCancelReload;
- (void)lockItems;
- (void)unlockItems;
- (void)makeSearchFieldFirstResponder;
- (NSSearchField*)searchField;

@end
