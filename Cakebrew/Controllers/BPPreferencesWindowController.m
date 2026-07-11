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

@interface BPPreferencesWindowController ()

@property (strong) NSButton *backgroundCheckCheckbox;
@property (strong) NSPopUpButton *intervalPopUp;
@property (strong) NSButton *greedyCheckbox;

@end

@implementation BPPreferencesWindowController

- (instancetype)init
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 460, 190)
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

	NSTextField *intervalLabel = [NSTextField labelWithString:NSLocalizedString(@"Preferences_Check_Interval", nil)];

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

	NSTextField *greedyNote = [NSTextField wrappingLabelWithString:NSLocalizedString(@"Preferences_Greedy_Casks_Note", nil)];
	greedyNote.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	greedyNote.textColor = [NSColor secondaryLabelColor];

	for (NSView *view in @[ self.backgroundCheckCheckbox, intervalLabel, self.intervalPopUp, self.greedyCheckbox, greedyNote ]) {
		view.translatesAutoresizingMaskIntoConstraints = NO;
		[content addSubview:view];
	}

	[NSLayoutConstraint activateConstraints:@[
		[self.backgroundCheckCheckbox.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
		[self.backgroundCheckCheckbox.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],

		[intervalLabel.centerYAnchor constraintEqualToAnchor:self.intervalPopUp.centerYAnchor],
		[intervalLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:38],
		[self.intervalPopUp.topAnchor constraintEqualToAnchor:self.backgroundCheckCheckbox.bottomAnchor constant:10],
		[self.intervalPopUp.leadingAnchor constraintEqualToAnchor:intervalLabel.trailingAnchor constant:8],

		[self.greedyCheckbox.topAnchor constraintEqualToAnchor:self.intervalPopUp.bottomAnchor constant:18],
		[self.greedyCheckbox.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],

		[greedyNote.topAnchor constraintEqualToAnchor:self.greedyCheckbox.bottomAnchor constant:6],
		[greedyNote.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:38],
		[greedyNote.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
	]];

	[self updateIntervalEnabled];
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

#pragma mark - Actions

- (void)toggleBackgroundCheck:(id)sender
{
	[BPPreferences setBackgroundCheckEnabled:(self.backgroundCheckCheckbox.state == NSControlStateValueOn)];
	[self updateIntervalEnabled];
}

- (void)intervalChanged:(id)sender
{
	NSNumber *interval = self.intervalPopUp.selectedItem.representedObject;
	if (interval) {
		[BPPreferences setBackgroundCheckInterval:interval.doubleValue];
	}
}

- (void)toggleGreedy:(id)sender
{
	// Takes effect on the next refresh of the outdated-casks list.
	[BPPreferences setGreedyCaskUpgrades:(self.greedyCheckbox.state == NSControlStateValueOn)];
}

@end
