//
//  BPSideBarController.m
//  Cakebrew
//
//  Created by Marek Hrusovsky on 05/09/14.
//  Copyright (c) 2014 Bruno Philipe. All rights reserved.
//

#import "BPSideBarController.h"
#import "BPPreferences.h"
#import "BPHomebrewManager.h"

@interface BPSidebarItem ()
@property (strong) NSMutableArray<BPSidebarItem *> *mutableChildren;
@property (weak) BPSidebarItem *parentItem;
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
		_badgeValue = @(-1); // Hidden by default until a real count is assigned
	}
	return self;
}

- (NSArray<BPSidebarItem *> *)children
{
	return self.mutableChildren;
}

- (void)addChildItem:(BPSidebarItem *)item
{
	// The group is what tells the two "Installed" rows apart, so a row has to
	// know which one it landed under.
	item.parentItem = self;
	[self.mutableChildren addObject:item];
}

- (BOOL)hasChildren
{
	return self.mutableChildren.count > 0;
}

@end

#pragma mark -

/// "42 items", or just "42" if the format string is unavailable. A missing key
/// returns the key itself, and "Sidebar_VoiceOver_Badge_Count" is worse to hear
/// than a bare number.
static NSString *BPSpokenBadgeCount(NSNumber *badge)
{
	NSString *format = NSLocalizedString(@"Sidebar_VoiceOver_Badge_Count", nil);
	if ([format containsString:@"%@"])
	{
		return [NSString stringWithFormat:format, badge];
	}
	return badge.stringValue;
}

/// ", " between the spoken parts of a row. A missing key returns the key
/// itself, and "Formulae Sidebar_VoiceOver_Separator Installed" is worse to
/// hear than a plain comma — same guard as the badge count above.
static NSString *BPSpokenSeparator(void)
{
	NSString *separator = NSLocalizedString(@"Sidebar_VoiceOver_Separator", nil);
	return [separator isEqualToString:@"Sidebar_VoiceOver_Separator"] ? @", " : separator;
}

@implementation BPSidebarBadgeView

- (void)setBadgeValue:(NSUInteger)badgeValue
{
	if (_badgeValue != badgeValue) {
		_badgeValue = badgeValue;
		[self invalidateIntrinsicContentSize];
		[self setNeedsDisplay:YES];
	}
}

#pragma mark - Accessibility

// The count is drawn with drawAtPoint:withAttributes:, so nothing about it
// reaches the accessibility tree unless it is declared here.
- (BOOL)isAccessibilityElement
{
	return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
	return NSAccessibilityStaticTextRole;
}

- (id)accessibilityValue
{
	return BPSpokenBadgeCount(@(self.badgeValue));
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

@property (strong, nonatomic) BPSidebarItem *installedFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *outdatedFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *allFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *leavesFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *pinnedFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *repositoriesFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *installedCasksSidebarItem;
@property (strong, nonatomic) BPSidebarItem *outdatedCasksSidebarItem;
@property (strong, nonatomic) BPSidebarItem *allCasksSidebarItem;

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

	_installedFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Installed", nil)
													 identifier:@"item"];
	_installedFormulaeSidebarItem.icon = [self installedSidebarIconImage];
	_installedFormulaeSidebarItem.accessibilityIdentifier = @"sidebar.formulae.installed";
	[parent addChildItem:_installedFormulaeSidebarItem];

	_outdatedFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Outdated", nil)
													 identifier:@"item"];
	_outdatedFormulaeSidebarItem.icon = [self outdatedSidebarIconImage];
	_outdatedFormulaeSidebarItem.accessibilityIdentifier = @"sidebar.formulae.outdated";
	[parent addChildItem:_outdatedFormulaeSidebarItem];

	_allFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_All", nil)
												identifier:@"item"];
	_allFormulaeSidebarItem.icon = [self allFormulaeSidebarIconImage];
	_allFormulaeSidebarItem.accessibilityIdentifier = @"sidebar.formulae.all";
	[parent addChildItem:_allFormulaeSidebarItem];

	_leavesFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Leaves", nil)
												   identifier:@"item"];
	_leavesFormulaeSidebarItem.icon = [self leavesSidebarIconImage];
	_leavesFormulaeSidebarItem.accessibilityIdentifier = @"sidebar.formulae.leaves";
	[parent addChildItem:_leavesFormulaeSidebarItem];

	_pinnedFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Pinned", nil)
												   identifier:@"item"];
	_pinnedFormulaeSidebarItem.icon = [self pinnedSidebarIconImage];
	_pinnedFormulaeSidebarItem.accessibilityIdentifier = @"sidebar.formulae.pinned";
	[parent addChildItem:_pinnedFormulaeSidebarItem];

	_repositoriesFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Repos", nil)
														 identifier:@"item"];
	_repositoriesFormulaeSidebarItem.icon = [self repositoriesSidebarIconImage];
	_repositoriesFormulaeSidebarItem.accessibilityIdentifier = @"sidebar.formulae.repositories";
	[parent addChildItem:_repositoriesFormulaeSidebarItem];

	parent = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Group_Casks", nil)
							   identifier:@"group"];
	[_rootSidebarCategory addChildItem:parent];

	_installedCasksSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Installed", nil)
											   identifier:@"item"];
	_installedCasksSidebarItem.icon = [self casksSidebarIconImage];
	_installedCasksSidebarItem.accessibilityIdentifier = @"sidebar.casks.installed";
	[parent addChildItem:_installedCasksSidebarItem];

	_outdatedCasksSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Outdated", nil)
											  identifier:@"item"];
	_outdatedCasksSidebarItem.icon = [self outdatedSidebarIconImage];
	_outdatedCasksSidebarItem.accessibilityIdentifier = @"sidebar.casks.outdated";
	[parent addChildItem:_outdatedCasksSidebarItem];

	_allCasksSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_AllCasks", nil)
											 identifier:@"item"];
	_allCasksSidebarItem.icon = [self allFormulaeSidebarIconImage];
	_allCasksSidebarItem.accessibilityIdentifier = @"sidebar.casks.all";
	[parent addChildItem:_allCasksSidebarItem];

	parent = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Group_Tools", nil)
							   identifier:@"group"];
	[_rootSidebarCategory addChildItem:parent];

	item = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Doctor", nil)
							 identifier:@"item"];
	[item setBadgeValue:@(-1)];
	item.accessibilityIdentifier = @"sidebar.tools.doctor";
	[item setIcon:[self doctorSidebarIconImage]];
	[parent addChildItem:item];

	item = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Update", nil)
							 identifier:@"item"];
	[item setBadgeValue:@(-1)];
	item.accessibilityIdentifier = @"sidebar.tools.update";
	[item setIcon:[self updateSidebarIconImage]];
	[parent addChildItem:item];

	item = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Services", nil)
							 identifier:@"item"];
	[item setBadgeValue:@(-1)];
	item.accessibilityIdentifier = @"sidebar.tools.services";
	[item setIcon:[self servicesSidebarIconImage]];
	[parent addChildItem:item];
}

- (NSImage *)installedSidebarIconImage
{
	return [NSImage imageWithSystemSymbolName:@"checkmark.square"
					 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Installed", nil)];
}

- (NSImage *)outdatedSidebarIconImage
{
	return [NSImage imageWithSystemSymbolName:@"clock.arrow.circlepath"
					 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Outdated", nil)];
}

- (NSImage *)allFormulaeSidebarIconImage
{
	return [NSImage imageWithSystemSymbolName:@"books.vertical"
					 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_All", nil)];
}

- (NSImage *)leavesSidebarIconImage
{
	return [NSImage imageWithSystemSymbolName:@"leaf"
					 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Leaves", nil)];
}

- (NSImage *)pinnedSidebarIconImage
{
	return [NSImage imageWithSystemSymbolName:@"pin"
					 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Pinned", nil)];
}

- (NSImage *)casksSidebarIconImage
{
	return [NSImage imageWithSystemSymbolName:@"macwindow"
					 accessibilityDescription:NSLocalizedString(@"Sidebar_Group_Casks", nil)];
}

- (NSImage *)servicesSidebarIconImage
{
	return [NSImage imageWithSystemSymbolName:@"gearshape.2"
					 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Services", nil)];
}

- (NSImage *)repositoriesSidebarIconImage
{
	return [NSImage imageWithSystemSymbolName:@"building.columns"
					 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Repos", nil)];
}

- (NSImage *)doctorSidebarIconImage
{
	return [NSImage imageWithSystemSymbolName:@"stethoscope"
					 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Doctor", nil)];
}

- (NSImage *)updateSidebarIconImage
{
	return [NSImage imageWithSystemSymbolName:@"arrow.triangle.2.circlepath.circle"
					 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Update", nil)];
}


+ (FormulaeSideBarItem)restorableRowFrom:(NSInteger)storedRow rowCount:(NSInteger)rowCount
{
	if (storedRow < 0 || storedRow >= rowCount)
	{
		return FormulaeSideBarItemInstalled;
	}

	switch ((FormulaeSideBarItem)storedRow)
	{
		case FormulaeSideBarItemFormulaeCategory:
		case FormulaeSideBarItemCasksCategory:
		case FormulaeSideBarItemToolsCategory:
			// Group headers are labels, not destinations.
			return FormulaeSideBarItemInstalled;
		default:
			return (FormulaeSideBarItem)storedRow;
	}
}

+ (NSString *)infoKeyForRow:(NSInteger)row
{
	switch ((FormulaeSideBarItem)row)
	{
		case FormulaeSideBarItemInstalled:      return @"Sidebar_Info_Installed";
		case FormulaeSideBarItemOutdated:       return @"Sidebar_Info_Outdated";
		case FormulaeSideBarItemAll:            return @"Sidebar_Info_All";
		case FormulaeSideBarItemLeaves:         return @"Sidebar_Info_Leaves";
		case FormulaeSideBarItemPinned:         return @"Sidebar_Info_Pinned";
		case FormulaeSideBarItemRepositories:   return @"Sidebar_Info_Repos";
		case FormulaeSideBarItemInstalledCasks: return @"Sidebar_Info_Casks";
		case FormulaeSideBarItemOutdatedCasks:  return @"Sidebar_Info_OutdatedCasks";
		case FormulaeSideBarItemAllCasks:       return @"Sidebar_Info_AllCasks";
		case FormulaeSideBarItemDoctor:         return @"Sidebar_Info_Doctor";
		case FormulaeSideBarItemUpdate:         return @"Sidebar_Info_Update";
		case FormulaeSideBarItemServices:       return @"Sidebar_Info_Services";

		case FormulaeSideBarItemFormulaeCategory:
		case FormulaeSideBarItemCasksCategory:
		case FormulaeSideBarItemToolsCategory:
			return nil;
	}
	return nil;
}

- (void)configureSidebarSettings
{
	self.sidebar.floatsGroupRows = NO;
	[self.sidebar reloadData];
	[self.sidebar expandItem:nil expandChildren:YES];
	// Reopen where the user left off rather than always on Installed.
	FormulaeSideBarItem row = [BPSideBarController restorableRowFrom:[BPPreferences lastSelectedSidebarRow]
															rowCount:[self.sidebar numberOfRows]];
	[self.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	[self.sidebar setAccessibilityLabel:NSLocalizedString(@"Sidebar_VoiceOver_Sidebar", nil)];
}

+ (NSString *)accessibilityLabelForGroup:(NSString *)group
								   title:(NSString *)title
								   badge:(NSNumber *)badge
{
	NSMutableArray<NSString *> *parts = [NSMutableArray array];

	if (group.length > 0)
	{
		[parts addObject:group];
	}

	if (title.length > 0)
	{
		[parts addObject:title];
	}

	// -1 is the sentinel for "this row has no badge" (the Tools rows), not a
	// count. Zero is a real count and worth hearing: nothing outdated is the
	// answer someone is listening for.
	if (badge != nil && badge.integerValue >= 0)
	{
		[parts addObject:BPSpokenBadgeCount(badge)];
	}

	return [parts componentsJoinedByString:BPSpokenSeparator()];
}

- (NSArray<NSString *> *)selectableRowAccessibilityIdentifiers
{
	NSMutableArray<NSString *> *identifiers = [NSMutableArray array];

	for (BPSidebarItem *group in self.rootSidebarCategory.children)
	{
		for (BPSidebarItem *row in group.children)
		{
			if (row.accessibilityIdentifier.length > 0)
			{
				[identifiers addObject:row.accessibilityIdentifier];
			}
		}
	}

	return identifiers;
}

- (BPSidebarItem *)itemForListMode:(BPListMode)mode
{
	switch (mode)
	{
		case kBPListInstalled:      return self.installedFormulaeSidebarItem;
		case kBPListOutdated:       return self.outdatedFormulaeSidebarItem;
		case kBPListAll:            return self.allFormulaeSidebarItem;
		case kBPListLeaves:         return self.leavesFormulaeSidebarItem;
		case kBPListPinned:         return self.pinnedFormulaeSidebarItem;
		case kBPListRepositories:   return self.repositoriesFormulaeSidebarItem;
		case kBPListInstalledCasks: return self.installedCasksSidebarItem;
		case kBPListOutdatedCasks:  return self.outdatedCasksSidebarItem;
		case kBPListAllCasks:       return self.allCasksSidebarItem;

		case kBPListSearch:
			// Search has no sidebar row of its own.
			return nil;
	}

	return nil;
}

- (void)refreshBadgeForListMode:(BPListMode)mode
{
	BPSidebarItem *item = [self itemForListMode:mode];

	if (!item)
	{
		return;
	}

	[self refreshSidebarBadges];
	[self.sidebar reloadItem:item];
}

- (void)refreshSidebarBadges
{
	self.installedFormulaeSidebarItem.badgeValue		= @([[[BPHomebrewManager sharedManager] installedFormulae] count]);
	self.outdatedFormulaeSidebarItem.badgeValue		= @([[[BPHomebrewManager sharedManager] outdatedFormulae] count]);
	self.allFormulaeSidebarItem.badgeValue			= @([[[BPHomebrewManager sharedManager] allFormulae] count]);
	self.leavesFormulaeSidebarItem.badgeValue		= @([[[BPHomebrewManager sharedManager] leavesFormulae] count]);
	self.pinnedFormulaeSidebarItem.badgeValue		= @([[[BPHomebrewManager sharedManager] pinnedFormulae] count]);
	self.repositoriesFormulaeSidebarItem.badgeValue = @([[[BPHomebrewManager sharedManager] repositoriesFormulae] count]);
	self.installedCasksSidebarItem.badgeValue		= @([[[BPHomebrewManager sharedManager] installedCasks] count]);
	self.outdatedCasksSidebarItem.badgeValue		= @([[[BPHomebrewManager sharedManager] outdatedCasks] count]);
	self.allCasksSidebarItem.badgeValue				= @([[[BPHomebrewManager sharedManager] allCasks] count]);
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
		// Use the semantic secondary label color so group headers match the system
		// source-list style and adapt to light/dark, instead of the hardcoded
		// gray-blue baked into the cell in the XIB.
		headerView.textField.textColor = NSColor.secondaryLabelColor;
		return headerView;
	}

	BPSidebarTableCellView *cellView = [outlineView makeViewWithIdentifier:@"MainCell" owner:self];
	cellView.textField.stringValue = sidebarItem.title;

	// Both of these go on the text field, not the cell view: an NSTableCellView
	// is not itself an accessibility element, so anything set there reaches
	// neither VoiceOver nor XCUITest.
	cellView.textField.accessibilityIdentifier = sidebarItem.accessibilityIdentifier;
	cellView.textField.accessibilityLabel =
		[BPSideBarController accessibilityLabelForGroup:sidebarItem.parentItem.title
												  title:sidebarItem.title
												  badge:sidebarItem.badgeValue];

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
