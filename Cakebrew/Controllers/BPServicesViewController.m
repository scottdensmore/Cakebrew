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
	[self runOperation:^BOOL(BPHomebrewInterface *interface, NSString *name) {
		return [interface startService:name withReturnBlock:nil];
	}];
}

- (void)stopSelectedService:(id)sender
{
	[self runOperation:^BOOL(BPHomebrewInterface *interface, NSString *name) {
		return [interface stopService:name withReturnBlock:nil];
	}];
}

- (void)restartSelectedService:(id)sender
{
	[self runOperation:^BOOL(BPHomebrewInterface *interface, NSString *name) {
		return [interface restartService:name withReturnBlock:nil];
	}];
}

- (void)runOperation:(BOOL (^)(BPHomebrewInterface *interface, NSString *name))operation
{
	NSInteger row = self.tableView.selectedRow;
	if (self.operationInFlight || row < 0 || (NSUInteger)row >= self.services.count)
	{
		return;
	}

	NSString *name = self.services[(NSUInteger)row].name;
	self.operationInFlight = YES;
	[self updateButtonStates];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		operation([BPHomebrewInterface sharedInterface], name);
		dispatch_async(dispatch_get_main_queue(), ^{
			self.operationInFlight = NO;
			[self refreshServices];
		});
	});
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
		return service.statusString ?: @"--";
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
