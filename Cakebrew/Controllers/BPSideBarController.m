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
#import "BPFormulaInformation-Swift.h"

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
	return @{ NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightSemibold],
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
	NSColor *borderColor;
	NSColor *textColor;
	if (self.isEmphasized) {
		backgroundColor = [NSColor.whiteColor colorWithAlphaComponent:0.92];
		borderColor = [NSColor.whiteColor colorWithAlphaComponent:0.98];
		textColor = NSColor.selectedContentBackgroundColor;
	} else {
		backgroundColor = [NSColor.secondaryLabelColor colorWithAlphaComponent:0.14];
		borderColor = [NSColor.secondaryLabelColor colorWithAlphaComponent:0.24];
		textColor = NSColor.secondaryLabelColor;
	}

	CGFloat pillHeight = 16.0;
	NSRect pill = NSInsetRect(NSMakeRect(NSMinX(self.bounds),
										 NSMidY(self.bounds) - pillHeight / 2.0,
										 NSWidth(self.bounds),
										 pillHeight), 0.5, 0.5);
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:pill
														xRadius:pill.size.height / 2.0
														yRadius:pill.size.height / 2.0];
	[backgroundColor setFill];
	[path fill];
	path.lineWidth = 0.75;
	[borderColor setStroke];
	[path stroke];

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
@property (strong, nonatomic, readwrite) BPSidebarHost *sidebarHost;

@property (strong, nonatomic) BPSidebarItem *installedFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *outdatedFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *allFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *leavesFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *pinnedFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *repositoriesFormulaeSidebarItem;
@property (strong, nonatomic) BPSidebarItem *installedCasksSidebarItem;
@property (strong, nonatomic) BPSidebarItem *outdatedCasksSidebarItem;
@property (strong, nonatomic) BPSidebarItem *allCasksSidebarItem;
@property (strong, nonatomic) BPSidebarItem *unifiedUpdatesSidebarItem;

@end

@implementation BPSideBarController

- (instancetype)init
{
	self = [super init];
	if (self) {
		_sidebarHost = [[BPSidebarHost alloc] init];
		__weak typeof(self) weakSelf = self;
		_sidebarHost.onSelectRow = ^(NSInteger rowIndex) {
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (!strongSelf) return;
			if (strongSelf.sidebar && strongSelf.sidebar.selectedRow != rowIndex) {
				[strongSelf.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)rowIndex]
								byExtendingSelection:NO];
			} else if ([strongSelf.delegate respondsToSelector:@selector(sourceListSelectionDidChange)]) {
				[strongSelf.delegate sourceListSelectionDidChange];
			}
		};
		[self buildSidebarTree];
		[self syncSidebarHost];
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
	_installedFormulaeSidebarItem.symbolName = @"checkmark.square";
	_installedFormulaeSidebarItem.icon = [self installedSidebarIconImage];
	_installedFormulaeSidebarItem.accessibilityIdentifier = @"sidebar.formulae.installed";
	[parent addChildItem:_installedFormulaeSidebarItem];

	_outdatedFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Outdated", nil)
													 identifier:@"item"];
	_outdatedFormulaeSidebarItem.symbolName = @"clock.arrow.circlepath";
	_outdatedFormulaeSidebarItem.icon = [self outdatedSidebarIconImage];
	_outdatedFormulaeSidebarItem.accessibilityIdentifier = @"sidebar.formulae.outdated";
	[parent addChildItem:_outdatedFormulaeSidebarItem];

	_allFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_All", nil)
												identifier:@"item"];
	_allFormulaeSidebarItem.symbolName = @"books.vertical";
	_allFormulaeSidebarItem.icon = [self allFormulaeSidebarIconImage];
	_allFormulaeSidebarItem.accessibilityIdentifier = @"sidebar.formulae.all";
	[parent addChildItem:_allFormulaeSidebarItem];

	_leavesFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Leaves", nil)
												   identifier:@"item"];
	_leavesFormulaeSidebarItem.symbolName = @"leaf";
	_leavesFormulaeSidebarItem.icon = [self leavesSidebarIconImage];
	_leavesFormulaeSidebarItem.accessibilityIdentifier = @"sidebar.formulae.leaves";
	[parent addChildItem:_leavesFormulaeSidebarItem];

	_pinnedFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Pinned", nil)
												   identifier:@"item"];
	_pinnedFormulaeSidebarItem.symbolName = @"pin";
	_pinnedFormulaeSidebarItem.icon = [self pinnedSidebarIconImage];
	_pinnedFormulaeSidebarItem.accessibilityIdentifier = @"sidebar.formulae.pinned";
	[parent addChildItem:_pinnedFormulaeSidebarItem];

	_repositoriesFormulaeSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Repos", nil)
														 identifier:@"item"];
	_repositoriesFormulaeSidebarItem.symbolName = @"building.columns";
	_repositoriesFormulaeSidebarItem.icon = [self repositoriesSidebarIconImage];
	_repositoriesFormulaeSidebarItem.accessibilityIdentifier = @"sidebar.formulae.repositories";
	[parent addChildItem:_repositoriesFormulaeSidebarItem];

	parent = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Group_Casks", nil)
							   identifier:@"group"];
	[_rootSidebarCategory addChildItem:parent];

	_installedCasksSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Installed", nil)
											   identifier:@"item"];
	_installedCasksSidebarItem.symbolName = @"macwindow";
	_installedCasksSidebarItem.icon = [self casksSidebarIconImage];
	_installedCasksSidebarItem.accessibilityIdentifier = @"sidebar.casks.installed";
	[parent addChildItem:_installedCasksSidebarItem];

	_outdatedCasksSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Outdated", nil)
											  identifier:@"item"];
	_outdatedCasksSidebarItem.symbolName = @"clock.arrow.circlepath";
	_outdatedCasksSidebarItem.icon = [self outdatedSidebarIconImage];
	_outdatedCasksSidebarItem.accessibilityIdentifier = @"sidebar.casks.outdated";
	[parent addChildItem:_outdatedCasksSidebarItem];

	_allCasksSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_AllCasks", nil)
											 identifier:@"item"];
	_allCasksSidebarItem.symbolName = @"square.stack.3d.up";
	_allCasksSidebarItem.icon = [self allCasksSidebarIconImage];
	_allCasksSidebarItem.accessibilityIdentifier = @"sidebar.casks.all";
	[parent addChildItem:_allCasksSidebarItem];

	parent = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Group_Tools", nil)
							   identifier:@"group"];
	[_rootSidebarCategory addChildItem:parent];

	item = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Doctor", nil)
							 identifier:@"item"];
	[item setBadgeValue:@(-1)];
	item.symbolName = @"stethoscope";
	item.accessibilityIdentifier = @"sidebar.tools.doctor";
	[item setIcon:[self doctorSidebarIconImage]];
	[parent addChildItem:item];

	item = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Update", nil)
							 identifier:@"item"];
	[item setBadgeValue:@(-1)];
	item.symbolName = @"arrow.triangle.2.circlepath.circle";
	item.accessibilityIdentifier = @"sidebar.tools.update";
	[item setIcon:[self updateSidebarIconImage]];
	[parent addChildItem:item];

	item = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Services", nil)
							 identifier:@"item"];
	[item setBadgeValue:@(-1)];
	item.symbolName = @"gearshape.2";
	item.accessibilityIdentifier = @"sidebar.tools.services";
	[item setIcon:[self servicesSidebarIconImage]];
	[parent addChildItem:item];

	_unifiedUpdatesSidebarItem = [BPSidebarItem itemWithTitle:NSLocalizedString(@"Sidebar_Item_Unified_Updates", nil)
												   identifier:@"item"];
	_unifiedUpdatesSidebarItem.symbolName = @"arrow.down.circle";
	_unifiedUpdatesSidebarItem.accessibilityIdentifier = @"sidebar.tools.updates";
	_unifiedUpdatesSidebarItem.icon = [self unifiedUpdatesSidebarIconImage];
	[parent addChildItem:_unifiedUpdatesSidebarItem];
}

- (void)syncSidebarHost
{
	if (!self.sidebarHost) return;
	[self.sidebarHost removeAllSections];
	NSInteger currentRowIndex = 0;
	for (BPSidebarItem *group in self.rootSidebarCategory.children) {
		NSInteger groupRowIndex = currentRowIndex++;
		[self.sidebarHost addSectionWithRowIndex:groupRowIndex title:group.title ?: @""];
		for (BPSidebarItem *row in group.children) {
			NSInteger itemRowIndex = currentRowIndex++;
			NSString *axLabel = [BPSideBarController accessibilityLabelForGroup:group.title
																		  title:row.title
																		  badge:row.badgeValue];
			[self.sidebarHost addRowToSectionAtRowIndex:groupRowIndex
											   rowIndex:itemRowIndex
												  title:row.title ?: @""
											 groupTitle:group.title ?: @""
											 symbolName:row.symbolName ?: @""
											 badgeCount:row.badgeValue ? row.badgeValue.integerValue : -1
								accessibilityIdentifier:row.accessibilityIdentifier ?: @""
									 accessibilityLabel:axLabel ?: @""];
		}
	}
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

- (NSImage *)allCasksSidebarIconImage
{
	return [NSImage imageWithSystemSymbolName:@"square.stack.3d.up"
					 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_AllCasks", nil)];
}

- (NSImage *)unifiedUpdatesSidebarIconImage
{
	return [NSImage imageWithSystemSymbolName:@"arrow.down.circle"
					 accessibilityDescription:NSLocalizedString(@"Sidebar_Item_Unified_Updates", nil)];
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
		case FormulaeSideBarItemUnifiedUpdates: return @"Sidebar_Info_Unified_Updates";

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
	NSInteger rowCount = self.sidebar ? [self.sidebar numberOfRows] : 16;
	FormulaeSideBarItem row = [BPSideBarController restorableRowFrom:[BPPreferences lastSelectedSidebarRow]
															rowCount:rowCount];
	[self.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	[self.sidebar setAccessibilityLabel:NSLocalizedString(@"Sidebar_VoiceOver_Sidebar", nil)];
	self.sidebarHost.selectedRowIndex = (NSInteger)row;
	[self syncSidebarHost];
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
	if ((mode == kBPListOutdated || mode == kBPListOutdatedCasks) && self.unifiedUpdatesSidebarItem)
	{
		[self.sidebar reloadItem:self.unifiedUpdatesSidebarItem];
	}
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
	self.unifiedUpdatesSidebarItem.badgeValue		= @([[[BPHomebrewManager sharedManager] outdatedFormulae] count] +
														[[[BPHomebrewManager sharedManager] outdatedCasks] count]);
	[self syncSidebarHost];
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

- (BPSidebarTableCellView *)makeProgrammaticHeaderCellView
{
	BPSidebarTableCellView *headerView = [[BPSidebarTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 180, 20)];
	headerView.identifier = @"HeaderCell";
	NSTextField *label = [NSTextField labelWithString:@""];
	label.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold];
	label.textColor = NSColor.secondaryLabelColor;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	[headerView addSubview:label];
	headerView.textField = label;
	[NSLayoutConstraint activateConstraints:@[
		[label.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor constant:4.0],
		[label.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor constant:-4.0],
		[label.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],
	]];
	return headerView;
}

- (BPSidebarTableCellView *)makeProgrammaticMainCellView
{
	BPSidebarTableCellView *cellView = [[BPSidebarTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 180, 24)];
	cellView.identifier = @"MainCell";

	NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 16, 16)];
	iconView.translatesAutoresizingMaskIntoConstraints = NO;
	[cellView addSubview:iconView];
	cellView.imageView = iconView;

	NSTextField *label = [NSTextField labelWithString:@""];
	label.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular];
	label.lineBreakMode = NSLineBreakByTruncatingTail;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	[cellView addSubview:label];
	cellView.textField = label;

	BPSidebarBadgeView *badgeView = [[BPSidebarBadgeView alloc] initWithFrame:NSMakeRect(0, 0, 28, 16)];
	badgeView.translatesAutoresizingMaskIntoConstraints = NO;
	[cellView addSubview:badgeView];
	cellView.badgeView = badgeView;

	[NSLayoutConstraint activateConstraints:@[
		[iconView.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor constant:4.0],
		[iconView.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor],
		[iconView.widthAnchor constraintEqualToConstant:16.0],
		[iconView.heightAnchor constraintEqualToConstant:16.0],
		[label.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:6.0],
		[label.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor],
		[badgeView.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:4.0],
		[badgeView.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor constant:-6.0],
		[badgeView.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor],
	]];
	return cellView;
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	BPSidebarItem *sidebarItem = item;

	if ([sidebarItem.identifier isEqualToString:@"group"]) {
		BPSidebarTableCellView *headerView = [outlineView makeViewWithIdentifier:@"HeaderCell" owner:self];
		if (!headerView) {
			headerView = [self makeProgrammaticHeaderCellView];
		}
		headerView.textField.stringValue = sidebarItem.title;
		// Use the semantic secondary label color so group headers match the system
		// source-list style and adapt to light/dark, instead of the hardcoded
		// gray-blue baked into the cell in the XIB.
		headerView.textField.textColor = NSColor.secondaryLabelColor;
		return headerView;
	}

	BPSidebarTableCellView *cellView = [outlineView makeViewWithIdentifier:@"MainCell" owner:self];
	if (!cellView) {
		cellView = [self makeProgrammaticMainCellView];
	}
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
	if (self.sidebar && self.sidebar.selectedRow >= 0) {
		self.sidebarHost.selectedRowIndex = self.sidebar.selectedRow;
	}
	if ([self.delegate respondsToSelector:@selector(sourceListSelectionDidChange)]) {
		[self.delegate sourceListSelectionDidChange];
	}
}

#pragma mark - Actions

- (IBAction)selectSideBarRowWithSenderTag:(id)sender
{
	NSInteger tag = [sender tag];
	self.sidebarHost.selectedRowIndex = tag;
	[self.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)tag] byExtendingSelection:NO];
}

@end
