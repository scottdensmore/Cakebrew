//
//  BPSideBarController.m
//  Cakebrew
//
//  Created by Marek Hrusovsky on 05/09/14.
//  Copyright (c) 2014 Bruno Philipe. All rights reserved.
//

#import "BPSideBarController.h"
#import "BPHomebrewManager.h"

@interface BPSidebarItem ()
@property (strong) NSMutableArray<BPSidebarItem *> *mutableChildren;
@end

@implementation BPSidebarItem

+ (instancetype)itemWithTitle:(NSString *)title identifier:(NSString *)identifier
{
	BPSidebarItem *item = [[self alloc] init];
	item.title = title;
	item.identifier = identifier;
	return item;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_mutableChildren = [NSMutableArray array];
	}
	return self;
}

- (NSArray<BPSidebarItem *> *)children
{
	return self.mutableChildren;
}

- (void)addChildItem:(BPSidebarItem *)item
{
	[self.mutableChildren addObject:item];
}

- (BOOL)hasChildren
{
	return self.mutableChildren.count > 0;
}

@end

#pragma mark -

@implementation BPSidebarBadgeView

- (void)setBadgeValue:(NSUInteger)badgeValue
{
	if (_badgeValue != badgeValue) {
		_badgeValue = badgeValue;
		[self invalidateIntrinsicContentSize];
		[self setNeedsDisplay:YES];
	}
}

- (void)setEmphasized:(BOOL)emphasized
{
	if (_emphasized != emphasized) {
		_emphasized = emphasized;
		[self setNeedsDisplay:YES];
	}
}

- (NSString *)badgeText
{
	return [NSString stringWithFormat:@"%lu", (unsigned long)self.badgeValue];
}

- (NSDictionary *)textAttributesWithColor:(NSColor *)color
{
	return @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:11.0],
			  NSForegroundColorAttributeName: color };
}

- (NSSize)intrinsicContentSize
{
	NSSize textSize = [[self badgeText] sizeWithAttributes:[self textAttributesWithColor:NSColor.labelColor]];
	return NSMakeSize(ceil(textSize.width) + 14.0, 16.0);
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSColor *backgroundColor;
	NSColor *textColor;
	if (self.isEmphasized) {
		backgroundColor = [NSColor.whiteColor colorWithAlphaComponent:0.9];
		textColor = NSColor.selectedContentBackgroundColor;
	} else {
		backgroundColor = [NSColor.secondaryLabelColor colorWithAlphaComponent:0.18];
		textColor = NSColor.secondaryLabelColor;
	}

	CGFloat pillHeight = 16.0;
	NSRect pill = NSMakeRect(NSMinX(self.bounds),
							 NSMidY(self.bounds) - pillHeight / 2.0,
							 NSWidth(self.bounds),
							 pillHeight);
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:pill
														xRadius:pillHeight / 2.0
														yRadius:pillHeight / 2.0];
	[backgroundColor setFill];
	[path fill];

	NSString *text = [self badgeText];
	NSDictionary *attributes = [self textAttributesWithColor:textColor];
	NSSize textSize = [text sizeWithAttributes:attributes];
	NSPoint origin = NSMakePoint(NSMidX(pill) - textSize.width / 2.0,
								 NSMidY(pill) - textSize.height / 2.0);
	[text drawAtPoint:origin withAttributes:attributes];
}

@end

#pragma mark -

@implementation BPSidebarTableCellView

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
	[super setBackgroundStyle:backgroundStyle];
	self.badgeView.emphasized = (backgroundStyle == NSBackgroundStyleEmphasized);
}

@end

#pragma mark -

@interface BPSideBarController()

@property (strong, nonatomic) BPSidebarItem *rootSidebarCategory;

@property (strong, nonatomic) BPSidebarItem *instaledFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *outdatedFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *allFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *leavesFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *repositoriesFormulaeSidebarItem;

@end

@implementation BPSideBarController

- (instancetype)init
{
	self = [super init];
	if (self) {
		[self buildSidebarTree];
	}
	return self;
}

- (void)buildSidebarTree
{
	BPSidebarItem *item, *parent;
	_rootSidebarCategory = [BPSidebarItem itemWithTitle:@"" identifier:@"root"];

	parent = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Group_Formulae", nil)
							   identifier:@"group"];
	[_rootSidebarCategory addChildItem:parent];

	_instaledFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Installed", nil)
													 identifier:@"item"];
	_instaledFormulaeSidebarItem.icon = [self installedSidebarIconImage];
	[parent addChildItem:_instaledFormulaeSidebarItem];

	_outdatedFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Outdated", nil)
													 identifier:@"item"];
	_outdatedFormulaeSidebarItem.icon = [self outdatedSidebarIconImage];
	[parent addChildItem:_outdatedFormulaeSidebarItem];

	_allFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_All", nil)
												identifier:@"item"];
	_allFormulaeSidebarItem.icon = [self allFormulaeSidebarIconImage];
	[parent addChildItem:_allFormulaeSidebarItem];

	_leavesFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Leaves", nil)
												   identifier:@"item"];
	_leavesFormulaeSidebarItem.icon = [self leavesSidebarIconImage];
	[parent addChildItem:_leavesFormulaeSidebarItem];

	_repositoriesFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Repos", nil)
														 identifier:@"item"];
	_repositoriesFormulaeSidebarItem.icon = [self repositoriesSidebarIconImage];
	[parent addChildItem:_repositoriesFormulaeSidebarItem];

	parent = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Group_Tools", nil)
							   identifier:@"group"];
	[_rootSidebarCategory addChildItem:parent];

	item = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Doctor", nil)
							 identifier:@"item"];
	[item setBadgeValue:@(-1)];
	[item setIcon:[self doctorSidebarIconImage]];
	[parent addChildItem:item];

	item = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Update", nil)
							 identifier:@"item"];
	[item setBadgeValue:@(-1)];
	[item setIcon:[self updateSidebarIconImage]];
	[parent addChildItem:item];
}

- (NSImage *)installedSidebarIconImage
{
	if (@available(macOS 11.0, *)) {
		return [NSImage imageWithSystemSymbolName:@"checkmark.square"
						 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Installed", nil)];
	} else {
		return [NSImage imageNamed:@"installedTemplate"];
	}
}

- (NSImage *)outdatedSidebarIconImage
{
	if (@available(macOS 11.0, *)) {
		return [NSImage imageWithSystemSymbolName:@"clock.arrow.circlepath"
						 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Outdated", nil)];
	} else {
		return [NSImage imageNamed:@"outdatedTemplate"];
	}
}

- (NSImage *)allFormulaeSidebarIconImage
{
	if (@available(macOS 11.0, *)) {
		return [NSImage imageWithSystemSymbolName:@"books.vertical"
						 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_All", nil)];
	} else {
		return [NSImage imageNamed:@"allFormulaeTemplate"];
	}
}

- (NSImage *)leavesSidebarIconImage
{
	if (@available(macOS 11.0, *)) {
		return [NSImage imageWithSystemSymbolName:@"leaf"
						 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Leaves", nil)];
	} else {
		return [NSImage imageNamed:@"pinTemplate"];
	}
}

- (NSImage *)repositoriesSidebarIconImage
{
	if (@available(macOS 11.0, *)) {
		return [NSImage imageWithSystemSymbolName:@"building.columns"
						 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Repos", nil)];
	} else {
		return [NSImage imageNamed:@"cloudTemplate"];
	}
}

- (NSImage *)doctorSidebarIconImage
{
	if (@available(macOS 11.0, *)) {
		return [NSImage imageWithSystemSymbolName:@"stethoscope"
						 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Doctor", nil)];
	} else {
		return [NSImage imageNamed:@"doctorTemplate"];
	}
}

- (NSImage *)updateSidebarIconImage
{
	if (@available(macOS 11.0, *)) {
		return [NSImage imageWithSystemSymbolName:@"arrow.triangle.2.circlepath.circle"
						 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Update", nil)];
	} else {
		return [NSImage imageNamed:@"updateTemplate"];
	}
}


- (void)configureSidebarSettings
{
	self.sidebar.floatsGroupRows = NO;
	[self.sidebar reloadData];
	[self.sidebar expandItem:nil expandChildren:YES];
	[self.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:FormulaeSideBarItemInstalled] byExtendingSelection:NO];
	[self.sidebar setAccessibilityLabel:NSLocalizedString(@"Sidebar_VoiceOver_Tools", nil)];
}

- (void)refreshSidebarBadges
{
	self.instaledFormulaeSidebarItem.badgeValue		= @([[[BPHomebrewManager sharedManager] installedFormulae] count]);
	self.outdatedFormulaeSidebarItem.badgeValue		= @([[[BPHomebrewManager sharedManager] outdatedFormulae] count]);
	self.allFormulaeSidebarItem.badgeValue			= @([[[BPHomebrewManager sharedManager] allFormulae] count]);
	self.leavesFormulaeSidebarItem.badgeValue		= @([[[BPHomebrewManager sharedManager] leavesFormulae] count]);
	self.repositoriesFormulaeSidebarItem.badgeValue = @([[[BPHomebrewManager sharedManager] repositoriesFormulae] count]);
}

#pragma mark - NSOutlineView Data Source

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if (!item) { //Is root
		return [[self.rootSidebarCategory children] count];
	} else {
		return [[(BPSidebarItem *)item children] count];
	}
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	if (!item) {
		return [[self.rootSidebarCategory children] objectAtIndex:index];
	} else {
		return [[(BPSidebarItem *)item children] objectAtIndex:index];
	}
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [(BPSidebarItem *)item hasChildren];
}

#pragma mark - NSOutlineView Delegate

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item
{
	return [[(BPSidebarItem *)item identifier] isEqualToString:@"group"];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	return ![self outlineView:outlineView isGroupItem:item];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(id)item
{
	return NO;
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	BPSidebarItem *sidebarItem = item;

	if ([sidebarItem.identifier isEqualToString:@"group"]) {
		BPSidebarTableCellView *headerView = [outlineView makeViewWithIdentifier:@"HeaderCell" owner:self];
		headerView.textField.stringValue = sidebarItem.title;
		return headerView;
	}

	BPSidebarTableCellView *cellView = [outlineView makeViewWithIdentifier:@"MainCell" owner:self];
	cellView.textField.stringValue = sidebarItem.title;

	if (sidebarItem.badgeValue.integerValue >= 0) {
		cellView.badgeView.badgeValue = (NSUInteger) sidebarItem.badgeValue.integerValue;
		[cellView.badgeView setHidden:NO];
	} else {
		[cellView.badgeView setHidden:YES];
	}

	if (sidebarItem.icon) {
		[cellView.imageView setImage:sidebarItem.icon];
	}

	return cellView;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	if ([self.delegate respondsToSelector:@selector(sourceListSelectionDidChange)]) {
		[self.delegate sourceListSelectionDidChange];
	}
}

#pragma mark - Actions

- (IBAction)selectSideBarRowWithSenderTag:(id)sender
{
	[self.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:[sender tag]] byExtendingSelection:NO];
}

@end
