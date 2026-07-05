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
	FormulaeSideBarItemToolsCategory = 7,
	FormulaeSideBarItemDoctor = 8,
	FormulaeSideBarItemUpdate = 9,
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

@property (assign) IBOutlet NSOutlineView *sidebar;

@property (weak) id <BPSideBarControllerDelegate>delegate;

- (void)refreshSidebarBadges;
- (void)configureSidebarSettings;

- (IBAction)selectSideBarRowWithSenderTag:(id)sender;

@end
