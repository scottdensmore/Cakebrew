//
//	BPDockMenu.h
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

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// What the Dock menu offers. The raw values are the menu item tags, so the
/// action handler can dispatch on `[sender tag]`.
typedef NS_ENUM(NSInteger, BPDockMenuItem) {
	BPDockMenuItemCheckForUpdates = 1,
	BPDockMenuItemUpgradeAllOutdated,
	BPDockMenuItemShowOutdated,
};

/**
 *  The actions the Dock menu fires.
 *
 *  Declared as a protocol so the compiler enforces the mapping. A Dock item
 *  wired to a renamed IBAction fails silently at runtime; conformance turns
 *  that into a build warning, which this project treats as an error.
 */
@protocol BPDockMenuActions <NSObject>
- (IBAction)updateHomebrew:(id)sender;
- (IBAction)upgradeAllOutdatedFormulae:(id)sender;
- (IBAction)showOutdatedFormulae:(id)sender;
@end

/// What the Dock menu sends its actions to. Kept separate from the actions
/// themselves so the actions protocol stays exactly "the things a Dock item
/// fires" — which is what the menu is checked against.
@protocol BPDockMenuTarget <BPDockMenuActions>
/// Whether the actions can run at all. All three need Homebrew.
- (BOOL)isHomebrewInstalled;
@end

/**
 *  The menu shown when the Dock icon is right-clicked.
 *
 *  Built here rather than in a xib so the item-to-action mapping is testable:
 *  Dock menus cannot be driven by XCUITest on a headless runner, and a Dock
 *  item wired to a renamed action fails silently.
 */
@interface BPDockMenu : NSObject

/// The action every item sends. The receiver dispatches on the item's tag,
/// which is a BPDockMenuItem.
+ (SEL)menuItemAction;

/// Builds the menu. Pass `enabled:NO` when Homebrew is unavailable — the Dock
/// menu is reachable with the app in the background, where it cannot explain
/// itself, so the items are simply off.
+ (NSMenu *)dockMenuWithTarget:(nullable id)target enabled:(BOOL)enabled;

/// The Localizable.strings key an item's title comes from. Exposed so the key
/// can be checked against the .strings files, which the test bundle does not
/// carry.
+ (nullable NSString *)localizationKeyForItem:(BPDockMenuItem)item;

/// The BPDockMenuActions selector an item stands for, or NULL if the item is
/// not one of ours.
+ (nullable SEL)controllerActionForItem:(BPDockMenuItem)item;

@end

NS_ASSUME_NONNULL_END
