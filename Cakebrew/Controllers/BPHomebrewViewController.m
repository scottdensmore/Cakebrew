//
//	HomebrewController.m
//	Cakebrew – The Homebrew GUI App for OS X
//
//	Created by Vincent Saluzzo on 06/12/11.
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

#import "BPHomebrewViewController.h"
#import "BPFormula.h"
#import "BPHomebrewManager.h"
#import "BPHomebrewInterface.h"
#import "BPCleanupPreview.h"
#import "BPBrewfile.h"
#import "BPFormulaOptionsWindowController.h"
#import "BPInstallationWindowController.h"
#import "BPUpdateViewController.h"
#import "BPDoctorViewController.h"
#import "BPServicesViewController.h"
#import "BPFormulaeDataSource.h"
#import "BPSelectedFormulaViewController.h"
#import "BPToolbar.h"
#import "BPAppDelegate.h"
#import "BPStyle.h"
#import "BPPreferences.h"
#import "BPLoadingView.h"
#import "BPDisabledView.h"
#import "BPBundleWindowController.h"
#import "BPTask.h"
#import "BPMainWindowController.h"
#import "NSLayoutConstraint+Shims.h"
#import "BPTimedDispatch.h"
#import "BPEmptyState.h"
#import "BPEmptyStateView.h"

typedef NS_ENUM(NSUInteger, BPContentTab) {
	kBPContentTabFormulae,
	kBPContentTabDoctor,
	kBPContentTabUpdate,
	kBPContentTabServices
};

@interface BPHomebrewViewController () <NSTableViewDelegate,
BPSideBarControllerDelegate,
BPSelectedFormulaViewControllerDelegate,
BPHomebrewManagerDelegate,
BPToolbarProtocol,
NSMenuDelegate,
NSOpenSavePanelDelegate>

@property (weak) BPAppDelegate *appDelegate;

@property NSInteger lastSelectedSidebarIndex;
@property BOOL hasAppliedDefaultDividerPosition;
@property (strong) BPTimedDispatch *searchDispatch;
/// The row the user was on when the search began, so clearing the field puts
/// them back rather than dumping them on All Formulae.
@property NSInteger sidebarRowBeforeSearch;

/// A cleanup dry run is in flight. It takes long enough to invite a second
/// click, and two dry runs would stack two confirmation sheets.
@property BOOL cleanupPreviewInFlight;

@property (getter=isSearching)			BOOL searching;
@property (getter=isHomebrewInstalled)	BOOL homebrewInstalled;


@property (strong, nonatomic) BPFormulaeDataSource				*formulaeDataSource;
@property (strong, nonatomic) BPFormulaOptionsWindowController	*formulaOptionsWindowController;
@property (strong, nonatomic) NSWindowController				*operationWindowController;
@property (strong, nonatomic) BPUpdateViewController			*updateViewController;
@property (strong, nonatomic) BPDoctorViewController			*doctorViewController;
@property (strong, nonatomic) BPServicesViewController			*servicesViewController;
@property (strong, nonatomic) BPFormulaPopoverViewController	*formulaPopoverViewController;
@property (strong, nonatomic) BPSelectedFormulaViewController	*selectedFormulaeViewController;
@property (strong, nonatomic) BPToolbar							*toolbar;
@property (strong, nonatomic) BPDisabledView					*disabledView;
@property (strong, nonatomic) BPLoadingView						*loadingView;

@property (weak) IBOutlet NSSplitView				*formulaeSplitView;
@property (weak) IBOutlet NSView					*selectedFormulaView;
@property (weak) IBOutlet NSProgressIndicator		*backgroundActivityIndicator;
@property (weak) IBOutlet BPMainWindowController	*mainWindowController;


@end

@implementation BPHomebrewViewController
{
	BPHomebrewManager *_homebrewManager;
}

- (BPFormulaPopoverViewController *)formulaPopoverViewController
{
	if (!_formulaPopoverViewController) {
		_formulaPopoverViewController = [[BPFormulaPopoverViewController alloc] init];
		//this will force initialize controller with its view
		__unused NSView *view = _formulaPopoverViewController.view;
	}
	return _formulaPopoverViewController;
}

- (id)init
{
	self = [super init];
	if (self) {
		[self commonInit];
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self) {
		[self commonInit];
	}
	return self;
}

- (void)commonInit
{
	_homebrewManager = [BPHomebrewManager sharedManager];
	[_homebrewManager setDelegate:self];
	
	self.selectedFormulaeViewController = [[BPSelectedFormulaViewController alloc] init];
	[self.selectedFormulaeViewController setDelegate:self];
	
	self.homebrewInstalled = YES;

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveBackgroundActivityNotification:) name:kDidBeginBackgroundActivityNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveBackgroundActivityNotification:) name:kDidEndBackgroundActivityNotification object:nil];
}

- (void)didReceiveBackgroundActivityNotification:(NSNotification*)notification
{
	if ([[notification name] isEqualToString:kDidBeginBackgroundActivityNotification])
	{
		[[self backgroundActivityIndicator] performSelectorOnMainThread:@selector(startAnimation:)
															 withObject:self waitUntilDone:YES];
	}
	else if ([[notification name] isEqualToString:kDidEndBackgroundActivityNotification])
	{
		[[self backgroundActivityIndicator] performSelectorOnMainThread:@selector(stopAnimation:)
															 withObject:self waitUntilDone:YES];
	}
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	[self.mainWindowController setUpViews];
	[self.mainWindowController setContentViewHidden:YES];

	self.formulaeDataSource = [[BPFormulaeDataSource alloc] initWithMode:kBPListAll];
	self.formulaeTableView.dataSource = self.formulaeDataSource;

	// Restore the sort the user last chose, so the header indicator and the row
	// order agree with each other on launch.
	NSString *sortColumn = [BPPreferences sortColumnIdentifier];
	if (sortColumn.length > 0)
	{
		NSSortDescriptor *restored = [NSSortDescriptor sortDescriptorWithKey:sortColumn
																   ascending:[BPPreferences sortAscending]];
		self.formulaeTableView.sortDescriptors = @[restored];
		self.formulaeDataSource.sortDescriptors = @[restored];
	}
	self.formulaeTableView.delegate = self;
	[self.formulaeTableView setAccessibilityLabel:NSLocalizedString(@"Formulae", nil)];
	
	// Autosave the divider so a dragged position survives relaunch. The window
	// itself already autosaves its frame (MainMenu.xib), but nothing persisted
	// inside it.
	self.formulaeSplitView.autosaveName = @"BPFormulaeSplitView";

	//link formulae tableview
	NSView *formulaeView = self.formulaeSplitView;
	if ([[self.tabView tabViewItems] count] > kBPContentTabFormulae) {
		NSTabViewItem *formulaeTab = [self.tabView tabViewItemAtIndex:kBPContentTabFormulae];
		[formulaeTab setView:formulaeView];
	}
	
	//Creating view for update tab
	self.updateViewController = [[BPUpdateViewController alloc] initWithNibName:nil bundle:nil];
	NSView *updateView = [self.updateViewController view];
	if ([[self.tabView tabViewItems] count] > kBPContentTabUpdate) {
		NSTabViewItem *updateTab = [self.tabView tabViewItemAtIndex:kBPContentTabUpdate];
		[updateTab setView:updateView];
	}
	
	//Creating view for doctor tab
	self.doctorViewController = [[BPDoctorViewController alloc] initWithNibName:nil bundle:nil];
	NSView *doctorView = [self.doctorViewController view];
	if ([[self.tabView tabViewItems] count] > kBPContentTabDoctor) {
		NSTabViewItem *doctorTab = [self.tabView tabViewItemAtIndex:kBPContentTabDoctor];
		[doctorTab setView:doctorView];
	}

	//Creating view for services tab
	self.servicesViewController = [[BPServicesViewController alloc] initWithNibName:nil bundle:nil];
	NSView *servicesView = [self.servicesViewController view];
	if ([[self.tabView tabViewItems] count] > kBPContentTabServices) {
		NSTabViewItem *servicesTab = [self.tabView tabViewItemAtIndex:kBPContentTabServices];
		[servicesTab setView:servicesView];
	}
	
	
	NSView *selectedFormulaView = [self.selectedFormulaeViewController view];
	[self.selectedFormulaView addSubview:selectedFormulaView];
	selectedFormulaView.translatesAutoresizingMaskIntoConstraints = NO;
	
	[self.selectedFormulaView addConstraints:[NSLayoutConstraint
											  constraintsWithVisualFormat:@"V:|-0-[view]-0-|"
											  options:0
											  metrics:nil
											  views:@{@"view": selectedFormulaView}]];
	
	[self.selectedFormulaView addConstraints:[NSLayoutConstraint
											  constraintsWithVisualFormat:@"H:|-0-[view]-0-|"
											  options:0
											  metrics:nil
											  views:@{@"view": selectedFormulaView}]];
	
	[self.sidebarController setDelegate:self];
	[self.sidebarController refreshSidebarBadges];
	[self.sidebarController configureSidebarSettings];

	[self addToolbar];
	[self addLoadingView];
	
	_appDelegate = BPAppDelegateRef;
	_appDelegate.dockActionTarget = self;
	// Set last: assigning this hands over any Brewfile that arrived before
	// there was a window to import it into.
	_appDelegate.brewfileImportTarget = self;
}

- (void)addToolbar
{
	self.toolbar = [[BPToolbar alloc] initWithIdentifier:@"MainToolbar"];
	self.toolbar.delegate = self.toolbar;
	self.toolbar.controller = self;
	[[[self view] window] setToolbar:self.toolbar];
	[self.toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
	[self.toolbar lockItems];
}

- (void)addDisabledView
{
	BPDisabledView *disabledView = [[BPDisabledView alloc] initWithFrame:NSZeroRect];
	disabledView.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:disabledView];

	NSView *referenceView = self.mainWindowController.windowContentView;

	[NSLayoutConstraint activate:@[
		[NSLayoutConstraint constraintWithItem:referenceView attribute:NSLayoutAttributeLeading
									 relatedBy:NSLayoutRelationEqual toItem:disabledView
									 attribute:NSLayoutAttributeLeading multiplier:1 constant:0],
		[NSLayoutConstraint constraintWithItem:referenceView attribute:NSLayoutAttributeTrailing
									 relatedBy:NSLayoutRelationEqual toItem:disabledView
									 attribute:NSLayoutAttributeTrailing multiplier:1 constant:0],
		[NSLayoutConstraint constraintWithItem:referenceView attribute:NSLayoutAttributeTop
									 relatedBy:NSLayoutRelationEqual toItem:disabledView
									 attribute:NSLayoutAttributeTop multiplier:1 constant:0],
		[NSLayoutConstraint constraintWithItem:referenceView attribute:NSLayoutAttributeBottom
									 relatedBy:NSLayoutRelationEqual toItem:disabledView
									 attribute:NSLayoutAttributeBottom multiplier:1 constant:0],
	]];

	[self setDisabledView:disabledView];
}

- (void)addLoadingView
{
	BPLoadingView *loadingView = [[BPLoadingView alloc] initWithFrame:NSZeroRect];
	loadingView.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:loadingView];

	NSView *referenceView = self.mainWindowController.windowContentView;

	[NSLayoutConstraint activate:@[
		[NSLayoutConstraint constraintWithItem:referenceView attribute:NSLayoutAttributeLeading
									 relatedBy:NSLayoutRelationEqual toItem:loadingView
									 attribute:NSLayoutAttributeLeading multiplier:1 constant:0],
		[NSLayoutConstraint constraintWithItem:referenceView attribute:NSLayoutAttributeTrailing
									 relatedBy:NSLayoutRelationEqual toItem:loadingView
									 attribute:NSLayoutAttributeTrailing multiplier:1 constant:0],
		[NSLayoutConstraint constraintWithItem:referenceView attribute:NSLayoutAttributeTop
									 relatedBy:NSLayoutRelationEqual toItem:loadingView
									 attribute:NSLayoutAttributeTop multiplier:1 constant:0],
		[NSLayoutConstraint constraintWithItem:referenceView attribute:NSLayoutAttributeBottom
									 relatedBy:NSLayoutRelationEqual toItem:loadingView
									 attribute:NSLayoutAttributeBottom multiplier:1 constant:0],
	]];

	[self setLoadingView:loadingView];
}

- (void)dealloc
{
	[_homebrewManager setDelegate:nil];

	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// Applies the default detail-pane height the first time the split view has a
/// size, then leaves the divider alone — the user's drag is theirs to keep, and
/// autosaveName restores it on the next launch.
- (void)applyDefaultDividerPositionIfNeeded
{
	if (self.hasAppliedDefaultDividerPosition)
	{
		return;
	}

	CGFloat height = [self.formulaeSplitView bounds].size.height;
	if (height <= 0)
	{
		return;
	}

	self.hasAppliedDefaultDividerPosition = YES;

	// A restored autosave already positioned the divider; don't override it.
	if (self.formulaeSplitView.autosaveName.length > 0 &&
		[[NSUserDefaults standardUserDefaults] objectForKey:
		 [NSString stringWithFormat:@"NSSplitView Subview Frames %@", self.formulaeSplitView.autosaveName]])
	{
		return;
	}

	static const CGFloat kDefaultDetailPaneHeight = 120.f;
	[self.formulaeSplitView setPosition:height - kDefaultDetailPaneHeight ofDividerAtIndex:0];
}

- (void)viewDidLayout
{
	[super viewDidLayout];
	[self applyDefaultDividerPositionIfNeeded];
}

- (void)updateInterfaceItems
{
	NSInteger selectedSidebarRow	= [self.sidebarController.sidebar selectedRow];
	NSInteger selectedIndex			= [self.formulaeTableView selectedRow];
	NSIndexSet *selectedRows		= [self.formulaeTableView selectedRowIndexes];
	NSArray *selectedFormulae		= [self.formulaeDataSource formulasAtIndexSet:selectedRows];

	// The divider used to be forced to 120 pt here, which runs on every
	// selection change — so dragging it and then clicking any row snapped it
	// straight back. It is positioned once at first layout instead, and
	// autosaved thereafter.
	BOOL showFormulaInfo = YES;
	
	if (selectedSidebarRow == FormulaeSideBarItemRepositories) // Repositories (Taps) sidebaritem
	{
		showFormulaInfo = false;

		[self.toolbar configureForMode:BPToolbarModeTap];


		if (selectedIndex != -1) {
			[self.toolbar configureForMode:BPToolbarModeUntap];
		} else {
			[self.toolbar configureForMode:BPToolbarModeTap];
		}
	}
	else if (selectedSidebarRow == FormulaeSideBarItemInstalledCasks
			 || selectedSidebarRow == FormulaeSideBarItemOutdatedCasks
			 || selectedSidebarRow == FormulaeSideBarItemAllCasks) // Casks
	{
		// The detail pane and the operation pipeline both dispatch on the
		// formula's cask flag (`brew info --cask`, `brew <op> --cask`).

		if (selectedIndex == -1) {
			[self.toolbar configureForMode:BPToolbarModeDefault];
		} else if (selectedSidebarRow == FormulaeSideBarItemOutdatedCasks) {
			[self.toolbar configureForMode:([selectedRows count] > 1 ?
											BPToolbarModeUpdateMany : BPToolbarModeUpdateSingle)];
		} else if (selectedSidebarRow == FormulaeSideBarItemAllCasks) {
			// statusForFormula: is cask-aware, so this mirrors All Formulae.
			BPFormula *cask = [self.formulaeDataSource formulaAtIndex:selectedIndex];
			if ([[BPHomebrewManager sharedManager] statusForFormula:cask] == kBPFormulaNotInstalled) {
				[self.toolbar configureForMode:BPToolbarModeInstall];
			} else {
				[self.toolbar configureForMode:BPToolbarModeUninstall];
			}
		} else {
			[self.toolbar configureForMode:BPToolbarModeUninstall];
		}
	}
	else if (selectedIndex == -1 || selectedSidebarRow > FormulaeSideBarItemToolsCategory)
	{
		[self.toolbar configureForMode:BPToolbarModeDefault];
	}
	else if ([[self.formulaeTableView selectedRowIndexes] count] > 1)
	{
		[self.toolbar configureForMode:BPToolbarModeUpdateMany];
	}
	else
	{
		BPFormula *formula = [self .formulaeDataSource formulaAtIndex:selectedIndex];

		switch ([[BPHomebrewManager sharedManager] statusForFormula:formula]) {
			case kBPFormulaInstalled:
				[self.toolbar configureForMode:BPToolbarModeUninstall];
				break;
				
			case kBPFormulaOutdated:
				if (selectedSidebarRow == FormulaeSideBarItemOutdated) {
					[self.toolbar configureForMode:BPToolbarModeUpdateSingle];
				} else {
					[self.toolbar configureForMode:BPToolbarModeUninstall];
				}
				break;
				
			case kBPFormulaNotInstalled:
				[self.toolbar configureForMode:BPToolbarModeInstall];
				break;
		}
	}

	if (showFormulaInfo)
	{
		[self.selectedFormulaView setHidden:NO];
		[self.selectedFormulaeViewController setFormulae:selectedFormulae];
	}
	else
	{
		[self.selectedFormulaView setHidden:YES];
	}
}

- (void)configureTableForListing:(BPListMode)mode
{
	[self.formulaeTableView deselectAll:nil];
	[self.formulaeDataSource setMode:mode];
	[self.formulaeTableView setMode:mode];
	[self.formulaeTableView reloadData];
	[self updateInterfaceItems];
	[self refreshEmptyState];
}

/// Shows the right empty state over the table, or removes it. Without this a
/// list with no rows was column headers over blank space, with no way to tell
/// "nothing matched" from "still loading".
- (void)refreshEmptyState
{
	NSInteger rows = [self.formulaeDataSource numberOfRowsInTableView:self.formulaeTableView];
	BOOL loading = (self.loadingView != nil);

	BPEmptyState *state = nil;
	if ([BPEmptyState shouldShowForRowCount:rows loading:loading])
	{
		state = [BPEmptyState stateForSidebarRow:[self.sidebarController.sidebar selectedRow]
									   searching:[self isSearching]];
	}

	[BPEmptyStateView presentState:state overView:self.scrollView_formulae];
}


#pragma mark – Footer Information Label

- (void)updateInfoLabelWithSidebarSelection
{
	FormulaeSideBarItem selectedSidebarRow = [self.sidebarController.sidebar selectedRow];
	NSString *message = nil;
	
	if (self.isSearching)
	{
		message = NSLocalizedString(@"Sidebar_Info_SearchResults", nil);
	}
	else
	{
		// One mapping, so a row can't be silently absent — an unmapped row
		// yields nil and the label is cleared rather than keeping the previously
		// selected row's description.
		NSString *key = [BPSideBarController infoKeyForRow:selectedSidebarRow];
		message = key ? NSLocalizedString(key, nil) : nil;
	}

	[self updateInfoLabelWithText:message];
}

- (void)updateInfoLabelWithText:(NSString*)message
{
	// Clear on nil. Silently keeping the old text is what made an unmapped row
	// (Pinned) show the previously selected row's description.
	[self.label_information setStringValue:message ?: @""];
}

#pragma mark - Homebrew Manager Delegate

/// One list of a reload has landed. Fired per list rather than once at the end,
/// so the app is usable while the cask catalog is still fetching.
- (void)homebrewManager:(BPHomebrewManager *)manager didPublishListForMode:(BPListMode)mode
{
	if (!self.isHomebrewInstalled || [self isSearching])
	{
		return;
	}

	// Just this row. A whole-outline reloadData clears the selection, and this
	// runs once per list — which is how the app lost the row the user had
	// reopened on.
	[self.sidebarController refreshBadgeForListMode:mode];

	if (mode == kBPListOutdated)
	{
		[self setEnableUpgradeFormulasMenu:(manager.outdatedFormulae.count > 0)];
	}

	// The installed list is the app's front door and returns in well under a
	// second. It used to sit behind the slowest call in the batch — a cold cask
	// catalog, 80 seconds — with nothing on screen but an indeterminate spinner.
	if (mode == kBPListInstalled && self.loadingView != nil)
	{
		[self revealContentForFirstPublishedList];
	}

	// Only redraw the table if what landed is what is on screen.
	if (self.loadingView == nil && self.formulaeDataSource.mode == mode)
	{
		[self.formulaeDataSource refreshBackingArray];
		[self.formulaeTableView reloadData];
		[self refreshEmptyState];
	}
}

/// Tears down the loading overlay and shows the list, on the first list to
/// land rather than on the whole batch.
///
/// Deliberately does not restore the previously selected formula or reselect a
/// row that is already selected: -homebrewManagerFinishedUpdating: still runs
/// at the end of the reload and owns that.
- (void)revealContentForFirstPublishedList
{
	[self.loadingView removeFromSuperview];
	self.loadingView = nil;

	[self.mainWindowController setContentViewHidden:NO];
	[self.label_information setHidden:NO];

	[self.toolbar configureForMode:BPToolbarModeDefault];
	[self.toolbar unlockItems];

	// No row selection here. -configureSidebarSettings has already restored the
	// row the user left off on, and -homebrewManagerFinishedUpdating: owns the
	// fallback when there is none.
	[self.formulaeDataSource refreshBackingArray];
	[self.formulaeTableView reloadData];
	[self refreshEmptyState];
}

- (void)homebrewManagerFinishedUpdating:(BPHomebrewManager *)manager
{
	[self.loadingView removeFromSuperview];
	self.loadingView = nil;
	
	if (self.isHomebrewInstalled)
	{
		[[self.formulaeTableView menu] cancelTracking];

		// Remember what the user had selected: a reload triggered by an
		// operation (pin, install, …) shouldn't throw away their place in the
		// list or blank the detail pane.
		BPFormula *previouslySelectedFormula = self.currentFormula;

		[self.mainWindowController setContentViewHidden:NO];
		[self.label_information setHidden:NO];
		
		[self.toolbar configureForMode:BPToolbarModeDefault];
		[self.toolbar unlockItems];
		[self.formulaeDataSource refreshBackingArray];

		// Used after unlocking the app when inserting custom homebrew installation path
		BOOL shouldReselectFirstRow = ([self.sidebarController.sidebar selectedRow] < 0);

		[self.sidebarController refreshSidebarBadges];
		[self.sidebarController.sidebar reloadData];

		[self setEnableUpgradeFormulasMenu:([[BPHomebrewManager sharedManager] outdatedFormulae].count > 0)];
		
		if (shouldReselectFirstRow) {
			[self.sidebarController.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:FormulaeSideBarItemInstalled] byExtendingSelection:NO];
		} else {
			[self.sidebarController.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)_lastSelectedSidebarIndex] byExtendingSelection:NO];
		}

		[self restoreSelectedFormula:previouslySelectedFormula];
		[self refreshEmptyState];
	}
}

/// Puts the table selection back on `formula` after a reload rebuilt the list.
/// Selecting the row drives -tableViewSelectionDidChange:, which repopulates
/// currentFormula and the detail pane.
- (void)restoreSelectedFormula:(BPFormula *)formula
{
	NSInteger row = formula ? [self.formulaeDataSource indexOfFormulaNamed:formula.name] : -1;

	if (row < 0)
	{
		// Gone from this list (uninstalled, or the sidebar moved on).
		self.currentFormula = nil;
		self.selectedFormulaeViewController.formulae = nil;
		return;
	}

	[self.formulaeTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
	[self.formulaeTableView scrollRowToVisible:row];
}

- (void)homebrewManager:(BPHomebrewManager *)manager didUpdateSearchResults:(NSArray *)searchResults
{
	[self loadSearchResults];
}

- (void)homebrewManager:(BPHomebrewManager *)manager shouldDisplayNoBrewMessage:(BOOL)yesOrNo
{
	[self setHomebrewInstalled:!yesOrNo];
	
	if (yesOrNo)
	{
		[self addDisabledView];
		[self.label_information setHidden:YES];
		[self.mainWindowController setContentViewHidden:YES];
		[self.toolbar lockItems];

		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:NSLocalizedString(@"Generic_Error", nil)];
		[alert addButtonWithTitle:NSLocalizedString(@"Message_No_Homebrew_Title", nil)];
		[alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
		[alert setInformativeText:NSLocalizedString(@"Message_No_Homebrew_Body", nil)];
		[alert.window setTitle:NSLocalizedString(@"Cakebrew", nil)];
		
		NSURL *brew_URL = [NSURL URLWithString:@"https://brew.sh"];

		[alert beginSheetModalForWindow:_appDelegate.window completionHandler:^(NSModalResponse returnCode) {
			if (returnCode == NSAlertFirstButtonReturn) {
				[[NSWorkspace sharedWorkspace] openURL:brew_URL];
			}
		}];
	}
	else
	{
		[self.disabledView removeFromSuperview];
		self.disabledView = nil;
		[self.label_information setHidden:NO];
		[self.mainWindowController setContentViewHidden:NO];
		
		[self.toolbar unlockItems];
		
		[[BPHomebrewManager sharedManager] reloadFromInterfaceRebuildingCache:YES];
	}
}

- (void)showFormulaInfoForCurrentlySelectedFormulaUsingInfoType:(BPFormulaInfoType)type
{
	NSPopover *popover = self.formulaPopoverViewController.formulaPopover;
	if ([popover isShown])
	{
		[popover close];
	}
	NSInteger selectedIndex = [self.formulaeTableView selectedRow];
	BPFormula *formula = [self selectedFormula];

	if (!formula)
	{
		return;
	}

	[self.formulaPopoverViewController setInfoType:type];
	[self.formulaPopoverViewController setFormula:formula];

	NSRect anchorRect = [self.formulaeTableView rectOfRow:selectedIndex];
	anchorRect.origin = [self.scrollView_formulae convertPoint:anchorRect.origin fromView:self.formulaeTableView];

	[popover showRelativeToRect:anchorRect
						 ofView:self.scrollView_formulae
				  preferredEdge:NSMaxXEdge];
}

#pragma mark - Search Mode

- (void)loadSearchResults
{
	// Remember where the user was. Search used to force-select All Formulae,
	// so someone browsing All Casks who typed three characters was thrown into
	// the formula namespace and shown an empty table.
	if (![self isSearching])
	{
		self.sidebarRowBeforeSearch = [self.sidebarController.sidebar selectedRow];
	}

	[self setSearching:YES];
	[self configureTableForListing:kBPListSearch];
}

- (void)endSearchAndCleanup
{
	[self.toolbar.searchField setStringValue:@""];
	[self setSearching:NO];

	// Discard anything still in flight, then return the user to the list they
	// were on rather than leaving them on All Formulae.
	[[BPHomebrewManager sharedManager] cancelSearch];

	NSInteger row = [BPSideBarController restorableRowFrom:self.sidebarRowBeforeSearch
												  rowCount:[self.sidebarController.sidebar numberOfRows]];
	[self.sidebarController.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
								byExtendingSelection:NO];
	[self updateInfoLabelWithSidebarSelection];
}

#pragma mark - NSTableView Delegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self updateInterfaceItems];
}

#pragma mark - BPSelectedFormulaViewController Delegate

- (void)selectedFormulaViewDidUpdateFormulaInfoForFormula:(BPFormula *)formula
{
	if (formula) [self setCurrentFormula:formula];
}

#pragma mark - BPSideBarDelegate Delegate

- (void)sourceListSelectionDidChange
{
	BPContentTab tabIndex = kBPContentTabFormulae;
	NSInteger selectedSidebarRow = [self.sidebarController.sidebar selectedRow];
	
	if ([self isSearching]) {
		[self endSearchAndCleanup];
	}
	
	if (selectedSidebarRow >= 0) {
		_lastSelectedSidebarIndex = selectedSidebarRow;
		// Remembered across launches, so the app reopens where the user left it.
		[BPPreferences setLastSelectedSidebarRow:selectedSidebarRow];
	}
	
	[self.formulaeTableView deselectAll:nil];
	[self setCurrentFormula:nil];
	
	[self updateInterfaceItems];
	
	switch (selectedSidebarRow) {
		case FormulaeSideBarItemInstalled: // Installed Formulae
			[self configureTableForListing:kBPListInstalled];
			break;
			
		case FormulaeSideBarItemOutdated: // Outdated Formulae
			[self configureTableForListing:kBPListOutdated];
			break;
			
		case FormulaeSideBarItemAll: // All Formulae
			[self configureTableForListing:kBPListAll];
			break;
			
		case FormulaeSideBarItemLeaves:	// Leaves
			[self configureTableForListing:kBPListLeaves];
			break;

		case FormulaeSideBarItemPinned:	// Pinned
			[self configureTableForListing:kBPListPinned];
			break;

		case FormulaeSideBarItemRepositories: // Repositories
			[self configureTableForListing:kBPListRepositories];
			break;

		case FormulaeSideBarItemInstalledCasks: // Installed Casks
			[self configureTableForListing:kBPListInstalledCasks];
			break;

		case FormulaeSideBarItemOutdatedCasks: // Outdated Casks
			[self configureTableForListing:kBPListOutdatedCasks];
			break;

		case FormulaeSideBarItemAllCasks: // All Casks
			[self configureTableForListing:kBPListAllCasks];
			break;
			
		case FormulaeSideBarItemDoctor: // Doctor
			tabIndex = kBPContentTabDoctor;
			break;
			
		case FormulaeSideBarItemUpdate: // Update Tool
			tabIndex = kBPContentTabUpdate;
			break;

		case FormulaeSideBarItemServices: // Services Tool
			tabIndex = kBPContentTabServices;
			[self.servicesViewController refreshServices];
			break;
			
		default:
			break;
	}
	
	[self updateInfoLabelWithSidebarSelection];
	
	[self.tabView selectTabViewItemAtIndex:tabIndex];
}

#pragma mark - NSMenu Delegate

- (void)menuNeedsUpdate:(NSMenu *)menu
{
	[self.formulaeTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:[self.formulaeTableView clickedRow]] byExtendingSelection:NO];
}

#pragma mark - IBActions

- (IBAction)showFormulaInfo:(id)sender
{
	[self showFormulaInfoForCurrentlySelectedFormulaUsingInfoType:kBPFormulaInfoTypeGeneral];
}

- (IBAction)showFormulaDependents:(id)sender
{
	BOOL onlyInstalledFormulae = YES;

	if ([sender isKindOfClass:[NSMenuItem class]])
	{
		onlyInstalledFormulae = ![sender isAlternate];
	}

	BPFormulaInfoType type = onlyInstalledFormulae ?
								kBPFormulaInfoTypeInstalledDependents :
								kBPFormulaInfoTypeAllDependents;

	[self showFormulaInfoForCurrentlySelectedFormulaUsingInfoType:type];
}

- (IBAction)installFormula:(id)sender
{
	if ([self hasBlockingBackgroundTask]) return;
	BPFormula *formula = [self selectedFormula];
	if (!formula) {
		return;
	}

	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:NSLocalizedString(@"Generic_Attention", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Yes", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
	[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Confirmation_Install_Formula", nil),
							   formula.name]];

	// Present as a sheet rather than an app-modal runModal: it keeps the main run
	// loop responsive (so the app stays UI-testable) and is the expected macOS
	// confirmation style. Attach to the app's main window, matching the other
	// sheet in this controller.
	[alert beginSheetModalForWindow:_appDelegate.window completionHandler:^(NSModalResponse returnCode) {
		if (returnCode == NSAlertFirstButtonReturn) {
			self.operationWindowController = [BPInstallationWindowController runWithOperation:kBPWindowOperationInstall
																					 formulae:@[formula]
																					  options:nil];
		}
	}];
}

- (IBAction)installFormulaWithOptions:(id)sender
{
	if ([self hasBlockingBackgroundTask]) return;
	BPFormula *formula = [self selectedFormula];
	if (!formula) {
		return;
	}
	if (formula.cask) { // casks take no install options; run the plain install
		[self installFormula:sender];
		return;
	}
	self.formulaOptionsWindowController = [BPFormulaOptionsWindowController runFormula:formula withCompletionBlock:^(NSArray *options) {
		self.operationWindowController = [BPInstallationWindowController runWithOperation:kBPWindowOperationInstall
																				 formulae:@[formula]
																				  options:options];
	}];
}

- (IBAction)uninstallFormula:(id)sender
{
	if ([self hasBlockingBackgroundTask]) return;
	BPFormula *formula = [self selectedFormula];
	if (!formula) {
		return;
	}

	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:NSLocalizedString(@"Generic_Attention", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Yes", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
	[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Confirmation_Uninstall_Formula", nil),
							   formula.name]];

	// Only casks have a zap stanza; a plain uninstall leaves their preferences,
	// application support directories and launch agents behind.
	NSButton *zapCheckbox = nil;
	if (formula.cask)
	{
		zapCheckbox = [NSButton checkboxWithTitle:NSLocalizedString(@"Confirmation_Uninstall_Cask_Zap", nil)
										   target:nil
										   action:nil];
		[zapCheckbox sizeToFit];
		zapCheckbox.state = [BPPreferences zapCasksOnUninstall] ? NSControlStateValueOn : NSControlStateValueOff;
		alert.accessoryView = zapCheckbox;
	}

	// Present as a sheet rather than an app-modal runModal: non-blocking (so the
	// app stays responsive / UI-testable) and the expected macOS confirmation
	// style. Attach to the app's main window like the other sheets here.
	[alert beginSheetModalForWindow:_appDelegate.window completionHandler:^(NSModalResponse returnCode) {
		if (returnCode == NSAlertFirstButtonReturn) {
			BOOL zap = zapCheckbox && zapCheckbox.state == NSControlStateValueOn;
			if (zapCheckbox)
			{
				[BPPreferences setZapCasksOnUninstall:zap];
			}
			self.operationWindowController = [BPInstallationWindowController runWithOperation:kBPWindowOperationUninstall
																					 formulae:@[formula]
																					  options:nil
																						  zap:zap];
		}
	}];
}

+ (NSSet *)keyPathsForValuesAffectingCurrentFormulaPinned
{
	return [NSSet setWithObject:@"currentFormula"];
}

- (BOOL)currentFormulaPinned
{
	return self.currentFormula != nil && [[BPHomebrewManager sharedManager] isFormulaPinned:self.currentFormula];
}

- (IBAction)pinSelectedFormula:(id)sender
{
	BPFormula *formula = [self selectedFormula];
	if (!formula || formula.cask) { // brew pin is formula-only
		return;
	}
	// Pin is instant and non-destructive, so no confirmation sheet. The interface
	// posts a formulae-updated call that reloads state (including pinnedFormulae).
	[[BPHomebrewInterface sharedInterface] pinFormula:formula.name withReturnBlock:nil];
}

- (IBAction)unpinSelectedFormula:(id)sender
{
	BPFormula *formula = [self selectedFormula];
	if (!formula || formula.cask) { // brew pin is formula-only
		return;
	}
	[[BPHomebrewInterface sharedInterface] unpinFormula:formula.name withReturnBlock:nil];
}

- (IBAction)upgradeSelectedFormulae:(id)sender
{
	if ([self hasBlockingBackgroundTask]) return;
	NSArray *selectedFormulae = [self selectedFormulae];
	if (![selectedFormulae count]) {
		return;
	}
	NSString *formulaNames = [[self selectedFormulaNames] componentsJoinedByString:@", "];
	
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:NSLocalizedString(@"Message_Update_Formulae_Title", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Yes", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
	[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Message_Update_Formulae_Body", nil),
							   formulaNames]];

	// Present as a sheet rather than an app-modal runModal (non-blocking,
	// UI-testable, standard macOS style), matching the other confirmations here.
	[alert beginSheetModalForWindow:_appDelegate.window completionHandler:^(NSModalResponse returnCode) {
		if (returnCode == NSAlertFirstButtonReturn) {
			self.operationWindowController = [BPInstallationWindowController runWithOperation:kBPWindowOperationUpgrade
																					 formulae:selectedFormulae
																					  options:nil];
		}
	}];
}


- (IBAction)upgradeAllOutdatedFormulae:(id)sender
{
	if ([self hasBlockingBackgroundTask]) return;

	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:NSLocalizedString(@"Message_Update_All_Outdated_Title", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Yes", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
	[alert setInformativeText:NSLocalizedString(@"Message_Update_All_Outdated_Body", nil)];

	// Present as a sheet rather than an app-modal runModal (non-blocking,
	// UI-testable, standard macOS style), matching the other confirmations here.
	[alert beginSheetModalForWindow:_appDelegate.window completionHandler:^(NSModalResponse returnCode) {
		if (returnCode == NSAlertFirstButtonReturn) {
			self.operationWindowController = [BPInstallationWindowController runWithOperation:kBPWindowOperationUpgrade
																					 formulae:nil
																					  options:nil];
		}
	}];
}

- (IBAction)tapRepository:(id)sender
{
	if ([self hasBlockingBackgroundTask]) return;

	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:NSLocalizedString(@"Message_Tap_Title", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_OK", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
	[alert setInformativeText:NSLocalizedString(@"Message_Tap_Body", nil)];

	NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,200,24)];
	[alert setAccessoryView:input];

	// Present as a sheet rather than an app-modal runModal (non-blocking,
	// UI-testable, standard macOS style), matching the other confirmations here.
	[alert beginSheetModalForWindow:_appDelegate.window completionHandler:^(NSModalResponse returnCode) {
		if (returnCode != NSAlertFirstButtonReturn) {
			return;
		}
		NSString *name = [[input stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([name length] <= 0) {
			return;
		}
		if (![BPHomebrewInterface isValidTapName:name]) {
			NSAlert *error = [[NSAlert alloc] init];
			error.messageText = NSLocalizedString(@"Message_Tap_Invalid_Title", nil);
			error.informativeText = NSLocalizedString(@"Message_Tap_Invalid_Body", nil);
			[error addButtonWithTitle:NSLocalizedString(@"Generic_OK", nil)];
			[error beginSheetModalForWindow:self->_appDelegate.window completionHandler:nil];
			return;
		}
		BPFormula *lformula = [BPFormula formulaWithName:name];
		self.operationWindowController = [BPInstallationWindowController runWithOperation:kBPWindowOperationTap
																				 formulae:@[lformula]
																				  options:nil];
	}];
}

- (IBAction)untapRepository:(id)sender
{
	if ([self hasBlockingBackgroundTask]) return;
	BPFormula *formula = [self selectedFormula];
	
	if (!formula)
	{
		return;
	}

	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:NSLocalizedString(@"Message_Untap_Title", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_OK", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
	[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Message_Untap_Body", nil), formula.name]];

	// Present as a sheet rather than an app-modal runModal (non-blocking,
	// UI-testable, standard macOS style), matching the other confirmations here.
	[alert beginSheetModalForWindow:_appDelegate.window completionHandler:^(NSModalResponse returnCode) {
		if (returnCode == NSAlertFirstButtonReturn) {
			self.operationWindowController = [BPInstallationWindowController runWithOperation:kBPWindowOperationUntap
																					 formulae:@[formula]
																					  options:nil];
		}
	}];
}

- (IBAction)updateHomebrew:(id)sender
{
	[self.sidebarController.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:FormulaeSideBarItemUpdate] byExtendingSelection:NO];
	[self.updateViewController runStopUpdate:nil];
}

- (IBAction)showOutdatedFormulae:(id)sender
{
	[self.sidebarController.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:FormulaeSideBarItemOutdated]
								byExtendingSelection:NO];
}

- (IBAction)openSelectedFormulaWebsite:(id)sender
{
	BPFormula *formula = [self selectedFormula];
	if (!formula) {
		return;
	}
	[[NSWorkspace sharedWorkspace] openURL:formula.website];
}

- (void)performSearchWithString:(NSString *)searchPhrase
{
	if ([searchPhrase isEqualToString:@""])
	{
		[self endSearchAndCleanup];
		return;
	}

	if (!self.searchDispatch)
	{
		self.searchDispatch = [BPTimedDispatch new];
	}

	// The field is continuous, so this runs per keystroke; each scan walks the
	// whole catalog. Coalesce so a burst of typing costs one scan.
	[self.searchDispatch scheduleDispatchAfterTimeInterval:0.15
												   inQueue:dispatch_get_main_queue()
												   ofBlock:^{
		[[BPHomebrewManager sharedManager] updateSearchWithName:searchPhrase];
	}];
}

- (IBAction)beginFormulaSearch:(id)sender
{
	[self.toolbar makeSearchFieldFirstResponder];
}

- (IBAction)runHomebrewCleanup:(id)sender
{
	if ([self hasBlockingBackgroundTask]) return;
	if (self.cleanupPreviewInFlight) return;

	// Cleanup permanently deletes cached downloads and old installed versions.
	// It is the app's only destructive one-click action, so ask brew what it
	// would remove before removing it. The dry run walks the cache and the
	// Cellar, so it runs off the main thread.
	self.cleanupPreviewInFlight = YES;

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		BPCleanupPreview *preview = [[BPHomebrewInterface sharedInterface] previewCleanup];

		dispatch_async(dispatch_get_main_queue(), ^{
			self.cleanupPreviewInFlight = NO;
			[self presentCleanupConfirmationForPreview:preview];
		});
	});
}

- (void)presentCleanupConfirmationForPreview:(BPCleanupPreview *)preview
{
	// A second click while the dry run was in flight, or a background reload
	// that started meanwhile — the sheet would confirm a cleanup that cannot run.
	if ([self hasBlockingBackgroundTask]) return;

	NSAlert *alert = [[NSAlert alloc] init];

	if (preview.isEmpty)
	{
		[alert setMessageText:NSLocalizedString(@"Cleanup_Nothing_Title", nil)];
		[alert setInformativeText:NSLocalizedString(@"Cleanup_Nothing_Body", nil)];
		[alert addButtonWithTitle:NSLocalizedString(@"Generic_OK", nil)];

		[alert beginSheetModalForWindow:_appDelegate.window completionHandler:nil];
		return;
	}

	[alert setMessageText:NSLocalizedString(@"Generic_Attention", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Yes", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
	[alert setInformativeText:[self cleanupConfirmationBodyForPreview:preview]];

	// Sheet, not runModal: keeps the app responsive and the flow UI-testable.
	// Attached to the app's window like every other sheet here.
	[alert beginSheetModalForWindow:_appDelegate.window completionHandler:^(NSModalResponse returnCode) {
		if (returnCode != NSAlertFirstButtonReturn) return;

		self.operationWindowController = [BPInstallationWindowController runWithOperation:kBPWindowOperationCleanup
																				 formulae:nil
																				  options:nil];
	}];
}

- (NSString *)cleanupConfirmationBodyForPreview:(BPCleanupPreview *)preview
{
	NSString *items = preview.itemCount == 1 ?
		NSLocalizedString(@"Cleanup_Item_Count_One", nil) :
		[NSString localizedStringWithFormat:NSLocalizedString(@"Cleanup_Item_Count_Other", nil),
		 (unsigned long)preview.itemCount];

	if (preview.reclaimableBytes == 0)
	{
		// brew found things to remove but could not size them. Say only what is
		// known rather than printing "0 bytes", which reads as "nothing to do".
		return [NSString localizedStringWithFormat:
				NSLocalizedString(@"Confirmation_Cleanup_No_Size", nil), items];
	}

	// Binary style, because brew's own "MB" is 1024-based — a decimal formatter
	// here would print a smaller-looking number than brew just reported.
	NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
	formatter.countStyle = NSByteCountFormatterCountStyleBinary;

	NSString *size = [formatter stringFromByteCount:(long long)preview.reclaimableBytes];

	return [NSString localizedStringWithFormat:
			NSLocalizedString(@"Confirmation_Cleanup", nil), items, size];
}

- (IBAction)runHomebrewExport:(id)sender
{
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setNameFieldLabel:NSLocalizedString(@"Panel_Export_Message", nil)];
	[savePanel setPrompt:NSLocalizedString(@"Panel_Export_Button", nil)];
	[savePanel setNameFieldStringValue:@"Brewfile"];
	
	[savePanel beginSheetModalForWindow:[NSApp mainWindow] completionHandler:^(NSInteger result) {
		NSURL *fileURL = [savePanel URL];
		
		if (fileURL && result)
		{
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
						   dispatch_get_main_queue(), ^{
							   self.operationWindowController = [BPBundleWindowController runExportOperationWithFile:fileURL];
						   });
		}
	}];
}

/// A Brewfile arriving from outside the app — a Finder double-click, "Open
/// With", `open -a`, or a drop on the Dock icon or the window.
///
/// Confirms first, unlike Tools ▸ Import: importing runs `brew bundle`, which
/// installs everything the file lists, and a drop is easy to do by accident.
- (void)importBrewfileAtURL:(NSURL *)url
{
	if (!url || [self hasBlockingBackgroundTask]) return;

	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:NSLocalizedString(@"Generic_Attention", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Yes", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
	[alert setInformativeText:[NSString localizedStringWithFormat:
							   NSLocalizedString(@"Confirmation_Import_Brewfile", nil),
							   url.lastPathComponent]];

	[alert beginSheetModalForWindow:_appDelegate.window completionHandler:^(NSModalResponse returnCode) {
		if (returnCode != NSAlertFirstButtonReturn) return;

		self.operationWindowController = [BPBundleWindowController runImportOperationWithFile:url];
	}];
}

- (IBAction)runHomebrewImport:(id)sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setNameFieldLabel:NSLocalizedString(@"Panel_Import_Message", nil)];
	[openPanel setPrompt:NSLocalizedString(@"Panel_Import_Button", nil)];
	[openPanel setNameFieldStringValue:@"Brewfile"];
	[openPanel setAllowsMultipleSelection:NO];
	[openPanel setCanChooseDirectories:NO];
	[openPanel setCanChooseFiles:YES];
	[openPanel setDelegate:self];
	
	[openPanel beginSheetModalForWindow:[NSApp mainWindow] completionHandler:^(NSInteger result) {
		NSURL *fileURL = [openPanel URL];
		
		if (fileURL && result)
		{
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
						   dispatch_get_main_queue(), ^{
							   self.operationWindowController = [BPBundleWindowController runImportOperationWithFile:fileURL];
						   });
		}
	}];
}

/// Presents the warning and reports whether the caller must stop.
///
/// This used to return void, so its `return` only exited the guard: callers
/// showed the warning and then carried straight on into their own confirmation
/// sheet, and confirming started a second brew run.
- (BOOL)hasBlockingBackgroundTask
{
	if (![BPAppDelegate shouldBlockOperationWhileRunningBackgroundTask:_appDelegate.isRunningBackgroundTask])
	{
		return NO;
	}

	[_appDelegate displayBackgroundWarning];
	return YES;
}

- (BPFormula *)selectedFormula
{
	NSInteger selectedIndex = [self.formulaeTableView selectedRow];
	return [self.formulaeDataSource formulaAtIndex:selectedIndex];
}

- (NSArray *)selectedFormulae
{
	NSIndexSet *selectedIndexes = [self.formulaeTableView selectedRowIndexes];
	return [self.formulaeDataSource formulasAtIndexSet:selectedIndexes];
}

- (NSArray *)selectedFormulaNames
{
	NSArray *formulas = [self selectedFormulae];
	return [formulas valueForKeyPath:@"@unionOfObjects.name"];
}

#pragma mark - Open Save Panels Delegate

- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url
{
	// One rule for what counts as a Brewfile, shared with the Finder-open and
	// drop paths — the panel used to be stricter than both.
	return [BPBrewfile isBrewfileURL:url];
}

@end
