//
//	BPDockMenu.m
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

#import "BPDockMenu.h"

@implementation BPDockMenu

+ (SEL)menuItemAction
{
	return NSSelectorFromString(@"performDockMenuAction:");
}

+ (NSMenu *)dockMenuWithTarget:(id)target enabled:(BOOL)enabled
{
	NSMenu *menu = [[NSMenu alloc] init];

	// Enablement is decided here, not by validation: with the app in the
	// background there is no key window to validate against, and AppKit would
	// re-enable everything.
	menu.autoenablesItems = NO;

	NSArray<NSNumber *> *items = @[ @(BPDockMenuItemCheckForUpdates),
									@(BPDockMenuItemUpgradeAllOutdated),
									@(BPDockMenuItemShowOutdated) ];

	for (NSNumber *boxed in items)
	{
		BPDockMenuItem item = (BPDockMenuItem)boxed.integerValue;

		NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[self titleForItem:item]
														  action:[self menuItemAction]
												   keyEquivalent:@""];
		menuItem.tag = item;
		menuItem.target = target;
		menuItem.enabled = enabled;

		[menu addItem:menuItem];
	}

	return menu;
}

+ (NSString *)localizationKeyForItem:(BPDockMenuItem)item
{
	switch (item)
	{
		case BPDockMenuItemCheckForUpdates:    return @"Dock_Check_For_Updates";
		case BPDockMenuItemUpgradeAllOutdated: return @"Dock_Upgrade_All_Outdated";
		case BPDockMenuItemShowOutdated:       return @"Dock_Show_Outdated";
	}

	return nil;
}

+ (NSString *)titleForItem:(BPDockMenuItem)item
{
	NSString *key = [self localizationKeyForItem:item];
	return key ? NSLocalizedString(key, nil) : @"";
}

+ (SEL)controllerActionForItem:(BPDockMenuItem)item
{
	switch (item)
	{
		case BPDockMenuItemCheckForUpdates:
			return @selector(updateHomebrew:);

		case BPDockMenuItemUpgradeAllOutdated:
			return @selector(upgradeAllOutdatedFormulae:);

		case BPDockMenuItemShowOutdated:
			return @selector(showOutdatedFormulae:);
	}

	return NULL;
}

@end
