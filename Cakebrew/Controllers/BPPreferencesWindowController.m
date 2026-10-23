//
//  BPPreferencesWindowController.m
//  Cakebrew
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

#import "BPPreferencesWindowController.h"
#import "BPPreferences.h"
#import "BPHelperRegistration.h"
#import "BPAppDelegate.h"
#import "BPFormulaInformation-Swift.h"

@interface BPPreferencesWindowController ()

@property (strong) NSButton *backgroundCheckCheckbox;
@property (strong) NSPopUpButton *intervalPopUp;
@property (strong) NSButton *greedyCheckbox;
@property (strong) NSTextField *helperStatusLabel;
@property (strong) NSButton *helperActionButton;
@property (strong, nonatomic) BPPreferencesHost *preferencesHost;

@end

@implementation BPPreferencesWindowController

- (instancetype)init
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 320)
												   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
													 backing:NSBackingStoreBuffered
													   defer:YES];
	window.title = NSLocalizedString(@"Preferences_Title", nil);
	window.releasedWhenClosed = NO;

	self = [super initWithWindow:window];
	if (self)
	{
		[self buildContentView];
	}
	return self;
}

- (void)buildContentView
{
	NSView *content = self.window.contentView;

	self.backgroundCheckCheckbox = [NSButton checkboxWithTitle:NSLocalizedString(@"Preferences_Background_Check", nil)
														target:self
														action:@selector(toggleBackgroundCheck:)];
	self.backgroundCheckCheckbox.state = [BPPreferences backgroundCheckEnabled] ? NSControlStateValueOn : NSControlStateValueOff;

	self.intervalPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
	NSArray<NSArray *> *intervals = @[
		@[NSLocalizedString(@"Preferences_Interval_Hourly", nil), @(3600.0)],
		@[NSLocalizedString(@"Preferences_Interval_Six_Hours", nil), @(21600.0)],
		@[NSLocalizedString(@"Preferences_Interval_Daily", nil), @(86400.0)],
	];
	for (NSArray *interval in intervals) {
		[self.intervalPopUp addItemWithTitle:interval[0]];
		self.intervalPopUp.lastItem.representedObject = interval[1];
	}
	[self selectIntervalItemMatchingPreference];
	self.intervalPopUp.target = self;
	self.intervalPopUp.action = @selector(intervalChanged:);

	self.greedyCheckbox = [NSButton checkboxWithTitle:NSLocalizedString(@"Preferences_Greedy_Casks", nil)
											   target:self
											   action:@selector(toggleGreedy:)];
	self.greedyCheckbox.state = [BPPreferences greedyCaskUpgrades] ? NSControlStateValueOn : NSControlStateValueOff;

	self.helperStatusLabel = [NSTextField wrappingLabelWithString:@""];
	self.helperActionButton = [NSButton buttonWithTitle:@"" target:self action:@selector(helperAction:)];
	self.helperActionButton.bezelStyle = NSBezelStyleRounded;

	BPPreferencesHost *host = [[BPPreferencesHost alloc] init];
	__weak typeof(self) weakSelf = self;
	host.onBackgroundCheckChanged = ^(BOOL enabled) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.backgroundCheckCheckbox.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
		[BPPreferences setBackgroundCheckEnabled:enabled];
		[strongSelf updateIntervalEnabled];
		[strongSelf syncSwiftUIHost];
	};
	host.onIntervalChanged = ^(double interval) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		[BPPreferences setBackgroundCheckInterval:interval];
		[strongSelf selectIntervalItemMatchingPreference];
		[strongSelf syncSwiftUIHost];
	};
	host.onGreedyChanged = ^(BOOL greedy) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.greedyCheckbox.state = greedy ? NSControlStateValueOn : NSControlStateValueOff;
		[BPPreferences setGreedyCaskUpgrades:greedy];
		[strongSelf syncSwiftUIHost];
	};
	host.onAutomaticAppUpdateCheckChanged = ^(BOOL enabled) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		[BPPreferences setAutomaticAppUpdateCheckEnabled:enabled];
		[strongSelf syncSwiftUIHost];
	};
	host.onShowMenuBarExtraChanged = ^(BOOL enabled) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		[BPPreferences setShowMenuBarExtra:enabled];
		[BPAppDelegateRef updateMenuBarExtra];
		[strongSelf syncSwiftUIHost];
	};
	host.onCheckForAppUpdates = ^{
		[BPAppDelegateRef checkForAppUpdates:nil];
	};
	host.onHelperAction = ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		[strongSelf helperAction:nil];
	};
	self.preferencesHost = host;

	NSView *hostView = host.viewController.view;
	hostView.translatesAutoresizingMaskIntoConstraints = NO;
	[content addSubview:hostView];
	[NSLayoutConstraint activateConstraints:@[
		[hostView.topAnchor constraintEqualToAnchor:content.topAnchor],
		[hostView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
		[hostView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
		[hostView.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
	]];

	[self updateIntervalEnabled];
	[self refreshHelperStatus];
}

- (void)syncSwiftUIHost
{
	if (!self.preferencesHost) return;
	NSString *actionTitle = self.helperActionButton.hidden ? nil : self.helperActionButton.title;
	self.preferencesHost.showMenuBarExtra = [BPPreferences showMenuBarExtra];
	[self.preferencesHost syncWithBackgroundCheckEnabled:[BPPreferences backgroundCheckEnabled]
												interval:[BPPreferences backgroundCheckInterval]
												  greedy:[BPPreferences greedyCaskUpgrades]
									 automaticAppUpdates:[BPPreferences automaticAppUpdateCheckEnabled]
											helperStatus:self.helperStatusLabel.stringValue ?: @""
									   helperActionTitle:actionTitle];
}

- (void)selectIntervalItemMatchingPreference
{
	NSTimeInterval current = [BPPreferences backgroundCheckInterval];
	for (NSMenuItem *item in self.intervalPopUp.itemArray) {
		if ([item.representedObject doubleValue] == current) {
			[self.intervalPopUp selectItem:item];
			return;
		}
	}
	[self.intervalPopUp selectItemAtIndex:1]; // 6 hours, the registered default
}

- (void)updateIntervalEnabled
{
	self.intervalPopUp.enabled = (self.backgroundCheckCheckbox.state == NSControlStateValueOn);
}

#pragma mark - Helper

- (void)refreshHelperStatus
{
	BPHelperState state = [[BPHelperRegistration sharedRegistration] currentState];
	self.helperStatusLabel.stringValue = [BPHelperRegistration localizedDescriptionForState:state];

	// Only offer an action the user can actually act on.
	BOOL offersLoginItems = [BPHelperRegistration stateOffersLoginItemsShortcut:state];
	BOOL offersInstall = (state == kBPHelperStateNotRegistered);
	self.helperActionButton.hidden = !(offersLoginItems || offersInstall);
	self.helperActionButton.title = offersLoginItems
		? NSLocalizedString(@"Helper_Action_Open_Login_Items", nil)
		: NSLocalizedString(@"Helper_Action_Install", nil);
	[self syncSwiftUIHost];
}

- (void)helperAction:(id)sender
{
	BPHelperState state = [[BPHelperRegistration sharedRegistration] currentState];

	if ([BPHelperRegistration stateOffersLoginItemsShortcut:state])
	{
		[BPHelperRegistration openLoginItemsSettings];
	}
	else
	{
		NSError *error = nil;
		if (![[BPHelperRegistration sharedRegistration] registerReturningError:&error])
		{
			NSLog(@"Cakebrew helper registration failed: %@", error.localizedDescription);
		}
	}
	[self refreshHelperStatus];
}

#pragma mark - Actions

- (void)toggleBackgroundCheck:(id)sender
{
	[BPPreferences setBackgroundCheckEnabled:(self.backgroundCheckCheckbox.state == NSControlStateValueOn)];
	[self updateIntervalEnabled];
	[self syncSwiftUIHost];
}

- (void)intervalChanged:(id)sender
{
	NSNumber *interval = self.intervalPopUp.selectedItem.representedObject;
	if (interval) {
		[BPPreferences setBackgroundCheckInterval:interval.doubleValue];
	}
	[self syncSwiftUIHost];
}

- (void)showWindow:(id)sender
{
	[super showWindow:sender];
	[self refreshHelperStatus];
}

- (void)toggleGreedy:(id)sender
{
	// Takes effect on the next refresh of the outdated-casks list.
	[BPPreferences setGreedyCaskUpgrades:(self.greedyCheckbox.state == NSControlStateValueOn)];
	[self syncSwiftUIHost];
}

@end
