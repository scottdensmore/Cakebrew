//
//  BPSideBarController.h
//  Cakebrew
//
//  Created by Marek Hrusovsky on 05/09/14.
//  Copyright (c) 2014 Bruno Philipe. All rights reserved.
//

@import Cocoa;

typedef NS_ENUM(NSUInteger, FormulaeSideBarItem)
{
	FormulaeSideBarItemFormulaeCategory = 0,
	FormulaeSideBarItemInstalled = 1,
	FormulaeSideBarItemOutdated = 2,
	FormulaeSideBarItemAll = 3,
	FormulaeSideBarItemLeaves = 4,
	FormulaeSideBarItemPinned = 5,
	FormulaeSideBarItemRepositories = 6,
	FormulaeSideBarItemCasksCategory = 7,
	FormulaeSideBarItemInstalledCasks = 8,
	FormulaeSideBarItemOutdatedCasks = 9,
	FormulaeSideBarItemAllCasks = 10,
	FormulaeSideBarItemToolsCategory = 11,
	FormulaeSideBarItemDoctor = 12,
	FormulaeSideBarItemUpdate = 13,
	FormulaeSideBarItemServices = 14,
};

@protocol BPSideBarControllerDelegate <NSObject>
- (void)sourceListSelectionDidChange;
@end

@interface BPSidebarItem : NSObject

@property (copy) NSString *title;
@property (copy) NSString *identifier;
@property (strong) NSImage *icon;
@property (strong) NSNumber *badgeValue;
@property (readonly) NSArray<BPSidebarItem *> *children;

+ (instancetype)itemWithTitle:(NSString *)title identifier:(NSString *)identifier;
- (void)addChildItem:(BPSidebarItem *)item;
- (BOOL)hasChildren;

@end

@interface BPSidebarBadgeView : NSView

@property (nonatomic) NSUInteger badgeValue;
@property (nonatomic, getter=isEmphasized) BOOL emphasized;

@end

@interface BPSidebarTableCellView : NSTableCellView

@property (assign) IBOutlet BPSidebarBadgeView *badgeView;

@end

@interface BPSideBarController : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>

/**
 *  The row to select for a stored value, falling back to Installed.
 *
 *  Sidebar rows are outline indices including group headers, so a stored row
 *  can be stranded past the end when items change, and can point at a category
 *  header, which is not a destination — restoring onto one shows nothing.
 */
+ (FormulaeSideBarItem)restorableRowFrom:(NSInteger)storedRow rowCount:(NSInteger)rowCount;

/**
 *  Localization key for the description shown under a sidebar row, or nil for
 *  group headers and unknown rows.
 *
 *  Returning nil rather than omitting a case matters: the caller clears the
 *  label, so an unmapped row shows nothing instead of whatever the previously
 *  selected row left on screen.
 */
+ (NSString *)infoKeyForRow:(NSInteger)row;


@property (assign) IBOutlet NSOutlineView *sidebar;

@property (weak) id <BPSideBarControllerDelegate>delegate;

- (void)refreshSidebarBadges;
- (void)configureSidebarSettings;

- (IBAction)selectSideBarRowWithSenderTag:(id)sender;

@end
