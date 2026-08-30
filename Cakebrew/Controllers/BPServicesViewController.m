//
//  BPServicesViewController.m
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

#import "BPServicesViewController.h"
#import "BPHomebrewInterface.h"
#import "BPService.h"
#import "BPStyle.h"
#import "BPAppDelegate.h"
#import "BPBrewError.h"

static NSString * const kServiceColumnName   = @"Name";
static NSString * const kServiceColumnStatus = @"Status";
static NSString * const kServiceColumnUser   = @"User";

@interface BPServicesViewController () <NSTableViewDataSource, NSTableViewDelegate>

@property (strong) NSArray<BPService *> *services;
@property (strong) NSTableView *tableView;
@property (strong) NSButton *startButton;
@property (strong) NSButton *stopButton;
@property (strong) NSButton *restartButton;
@property (assign) BOOL operationInFlight;

@end

@implementation BPServicesViewController

- (void)loadView
{
	NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 826, 416)];

	NSTextField *titleLabel = [NSTextField labelWithString:NSLocalizedString(@"Services_Title", nil)];
	titleLabel.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
	titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[view addSubview:titleLabel];

	NSTableView *tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
	for (NSString *identifier in @[ kServiceColumnName, kServiceColumnStatus, kServiceColumnUser ]) {
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
		column.title = NSLocalizedString(([@"Services_Column_" stringByAppendingString:identifier]), nil);
		column.width = [identifier isEqualToString:kServiceColumnName] ? 260 : 140;
		[tableView addTableColumn:column];
	}
	tableView.dataSource = self;
	tableView.delegate = self;
	tableView.allowsMultipleSelection = NO;
	[tableView setAccessibilityLabel:NSLocalizedString(@"Services_Title", nil)];
	self.tableView = tableView;

	NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	scrollView.documentView = tableView;
	scrollView.hasVerticalScroller = YES;
	scrollView.borderType = NSBezelBorder;
	scrollView.translatesAutoresizingMaskIntoConstraints = NO;
	[view addSubview:scrollView];

	self.startButton = [self buttonWithTitle:NSLocalizedString(@"Services_Start", nil) action:@selector(startSelectedService:)];
	self.stopButton = [self buttonWithTitle:NSLocalizedString(@"Services_Stop", nil) action:@selector(stopSelectedService:)];
	self.restartButton = [self buttonWithTitle:NSLocalizedString(@"Services_Restart", nil) action:@selector(restartSelectedService:)];
	[view addSubview:self.startButton];
	[view addSubview:self.stopButton];
	[view addSubview:self.restartButton];

	[NSLayoutConstraint activateConstraints:@[
		[titleLabel.topAnchor constraintEqualToAnchor:view.topAnchor constant:16],
		[titleLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],

		[scrollView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12],
		[scrollView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],
		[scrollView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20],

		[self.startButton.topAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:12],
		[self.startButton.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],
		[self.startButton.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-16],
		[self.stopButton.leadingAnchor constraintEqualToAnchor:self.startButton.trailingAnchor constant:8],
		[self.stopButton.centerYAnchor constraintEqualToAnchor:self.startButton.centerYAnchor],
		[self.restartButton.leadingAnchor constraintEqualToAnchor:self.stopButton.trailingAnchor constant:8],
		[self.restartButton.centerYAnchor constraintEqualToAnchor:self.startButton.centerYAnchor],
	]];

	self.view = view;
	[self updateButtonStates];
}

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action
{
	NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
	button.bezelStyle = NSBezelStyleRounded;
	button.enabled = NO;
	button.translatesAutoresizingMaskIntoConstraints = NO;
	return button;
}

#pragma mark - Data

- (void)refreshServices
{
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		NSArray<BPService *> *services = [[BPHomebrewInterface sharedInterface] listServices];
		dispatch_async(dispatch_get_main_queue(), ^{
			self.services = services;
			[self.tableView reloadData];
			[self updateButtonStates];
		});
	});
}

#pragma mark - Operations

- (void)startSelectedService:(id)sender
{
	[self runOperation:^BOOL(BPHomebrewInterface *interface, NSString *name, void (^output)(NSString *)) {
		return [interface startService:name withReturnBlock:output];
	}];
}

- (void)stopSelectedService:(id)sender
{
	[self runOperation:^BOOL(BPHomebrewInterface *interface, NSString *name, void (^output)(NSString *)) {
		return [interface stopService:name withReturnBlock:output];
	}];
}

- (void)restartSelectedService:(id)sender
{
	[self runOperation:^BOOL(BPHomebrewInterface *interface, NSString *name, void (^output)(NSString *)) {
		return [interface restartService:name withReturnBlock:output];
	}];
}

- (void)runOperation:(BOOL (^)(BPHomebrewInterface *interface, NSString *name, void (^output)(NSString *)))operation
{
	NSInteger row = self.tableView.selectedRow;
	if (self.operationInFlight || row < 0 || (NSUInteger)row >= self.services.count)
	{
		return;
	}

	// operationInFlight only tracks this view's own service operations; a brew
	// run started elsewhere in the app takes Homebrew's lock just the same.
	BPAppDelegate *appDelegate = BPAppDelegateRef;
	if ([BPAppDelegate shouldBlockOperationWhileRunningBackgroundTask:appDelegate.isRunningBackgroundTask])
	{
		[appDelegate displayBackgroundWarning];
		return;
	}

	NSString *name = self.services[(NSUInteger)row].name;
	self.operationInFlight = YES;
	[self updateButtonStates];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		// Both the exit status and brew's output used to be thrown away, so a
		// failed start re-enabled the buttons, reloaded the table, and showed
		// the unchanged old status with no explanation.
		NSMutableString *output = [NSMutableString string];
		BOOL succeeded = operation([BPHomebrewInterface sharedInterface], name, ^(NSString *chunk) {
			@synchronized (output) { [output appendString:chunk ?: @""]; }
		});

		dispatch_async(dispatch_get_main_queue(), ^{
			self.operationInFlight = NO;
			[self refreshServices];

			if (!succeeded)
			{
				NSString *transcript;
				@synchronized (output) { transcript = [output copy]; }
				[self presentServiceFailureForName:name output:transcript];
			}
		});
	});
}

/// Shows brew's own words. Attached to the app window per the sheets-not-modals
/// convention — self.view.window is nil under the split-view reparenting.
- (void)presentServiceFailureForName:(NSString *)name output:(NSString *)output
{
	NSError *error = [BPBrewError errorForExitStatus:1 output:output];

	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = [NSString stringWithFormat:NSLocalizedString(@"Services_Operation_Failed_Title", nil), name];
	alert.informativeText = error.localizedDescription;
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_OK", nil)];
	[alert beginSheetModalForWindow:BPAppDelegateRef.window completionHandler:nil];
}

#pragma mark - Button state

- (void)updateButtonStates
{
	NSInteger row = self.tableView.selectedRow;
	BPService *service = (row >= 0 && (NSUInteger)row < self.services.count) ? self.services[(NSUInteger)row] : nil;

	BOOL enabled = (service != nil && !self.operationInFlight);
	BOOL running = (service.status == kBPServiceStatusStarted || service.status == kBPServiceStatusScheduled);

	self.startButton.enabled = enabled && !running;
	self.stopButton.enabled = enabled && running;
	self.restartButton.enabled = enabled;
}

#pragma mark - NSTableView

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)self.services.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row < 0 || (NSUInteger)row >= self.services.count)
	{
		return @"";
	}
	BPService *service = self.services[(NSUInteger)row];

	if ([tableColumn.identifier isEqualToString:kServiceColumnName])
	{
		return service.name;
	}
	if ([tableColumn.identifier isEqualToString:kServiceColumnStatus])
	{
		// The enum, not brew's raw JSON token — statusString is none/started/
		// stopped/error/scheduled and reached the column verbatim.
		return [BPService localizedNameForStatus:service.status];
	}
	if ([tableColumn.identifier isEqualToString:kServiceColumnUser])
	{
		return service.user ?: @"--";
	}
	return @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self updateButtonStates];
}

@end
