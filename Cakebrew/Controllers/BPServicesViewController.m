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
#import "BPServiceDetails.h"
#import "BPStyle.h"
#import "BPAppDelegate.h"
#import "BPBrewError.h"
#import "BPEmptyState.h"
#import "BPEmptyStateView.h"
#import "BPSideBarController.h"

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
@property (strong) BPServiceDetails *details;
@property (assign) NSUInteger detailsGeneration;
@property (assign) NSUInteger listGeneration;
@property (assign) BOOL applyingServices;
@property (strong) NSTextView *detailsText;
@property (strong) NSButton *revealButton;
@property (strong) NSButton *logsButton;
@property (strong) NSButton *outputCopyButton;

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

	NSScrollView *detailsScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	detailsScroll.hasVerticalScroller = YES;
	detailsScroll.borderType = NSBezelBorder;
	detailsScroll.translatesAutoresizingMaskIntoConstraints = NO;
	self.detailsText = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 600, 100)];
	self.detailsText.editable = NO;
	self.detailsText.selectable = YES;
	self.detailsText.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
	self.detailsText.textColor = NSColor.labelColor;
	self.detailsText.backgroundColor = NSColor.textBackgroundColor;
	self.detailsText.textContainerInset = NSMakeSize(8, 6);
	self.detailsText.autoresizingMask = NSViewWidthSizable;
	self.detailsText.verticallyResizable = YES;
	self.detailsText.horizontallyResizable = NO;
	self.detailsText.textContainer.widthTracksTextView = YES;
	self.detailsText.textContainer.containerSize = NSMakeSize(600, CGFLOAT_MAX);
	[self.detailsText setAccessibilityIdentifier:@"services.details"];
	[self.detailsText setAccessibilityLabel:NSLocalizedString(@"Services_Details_Title", nil)];
	detailsScroll.documentView = self.detailsText;
	[view addSubview:detailsScroll];
	self.revealButton = [self buttonWithTitle:NSLocalizedString(@"Services_Reveal_File", nil) action:@selector(revealServiceFile:)];
	self.logsButton = [self buttonWithTitle:NSLocalizedString(@"Services_Open_Logs", nil) action:@selector(openServiceLogs:)];
	self.outputCopyButton = [self buttonWithTitle:NSLocalizedString(@"Services_Copy_Output", nil) action:@selector(copyServiceOutput:)];
	[self.revealButton setAccessibilityIdentifier:@"services.revealFile"];
	[self.logsButton setAccessibilityIdentifier:@"services.openLogs"];
	[self.outputCopyButton setAccessibilityIdentifier:@"services.copyOutput"];
	[view addSubview:self.revealButton];
	[view addSubview:self.logsButton];
	[view addSubview:self.outputCopyButton];
	NSLayoutConstraint *detailHeight = [detailsScroll.heightAnchor constraintEqualToConstant:115];
	detailHeight.priority = NSLayoutPriorityDefaultHigh;
	detailHeight.active = YES;

	[NSLayoutConstraint activateConstraints:@[
		[titleLabel.topAnchor constraintEqualToAnchor:view.topAnchor constant:16],
		[titleLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],

		[scrollView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12],
		[scrollView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],
		[scrollView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20],

		[self.startButton.topAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:12],
		[self.startButton.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],
		[self.stopButton.leadingAnchor constraintEqualToAnchor:self.startButton.trailingAnchor constant:8],
		[self.stopButton.centerYAnchor constraintEqualToAnchor:self.startButton.centerYAnchor],
		[self.restartButton.leadingAnchor constraintEqualToAnchor:self.stopButton.trailingAnchor constant:8],
		[self.restartButton.centerYAnchor constraintEqualToAnchor:self.startButton.centerYAnchor],
		[scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:45],
		[detailsScroll.topAnchor constraintEqualToAnchor:self.startButton.bottomAnchor constant:8],
		[detailsScroll.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
		[detailsScroll.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
		[detailsScroll.heightAnchor constraintGreaterThanOrEqualToConstant:40],
		[self.revealButton.topAnchor constraintEqualToAnchor:detailsScroll.bottomAnchor constant:8],
		[self.revealButton.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
		[self.logsButton.leadingAnchor constraintEqualToAnchor:self.revealButton.trailingAnchor constant:6],
		[self.logsButton.centerYAnchor constraintEqualToAnchor:self.revealButton.centerYAnchor],
		[self.outputCopyButton.leadingAnchor constraintEqualToAnchor:self.logsButton.trailingAnchor constant:6],
		[self.outputCopyButton.centerYAnchor constraintEqualToAnchor:self.revealButton.centerYAnchor],
		[self.outputCopyButton.trailingAnchor constraintLessThanOrEqualToAnchor:scrollView.trailingAnchor],
		[self.revealButton.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-12],
	]];

	self.view = view;
	[self updateButtonStates];
	[self showDetailsMessage:NSLocalizedString(@"Services_Details_Select", nil)];
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
	NSString *selectedName = [self selectedService].name;
	[self invalidateServiceDetails];
	NSUInteger generation = self.listGeneration;
	[self fetchServicesWithCompletion:^(NSArray<BPService *> *services) {
		if (generation != self.listGeneration) return;
		self.applyingServices = YES;
		self.services = services;
		[self.tableView reloadData];
		NSUInteger index = [services indexOfObjectPassingTest:^BOOL(BPService *service, NSUInteger idx, BOOL *stop) {
			return [service.name isEqualToString:selectedName];
		}];
		if (index != NSNotFound) [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
		else [self.tableView deselectAll:nil];
		self.applyingServices = NO;
		[self updateButtonStates];
		[self refreshEmptyState];
		// reloadData may preserve the same row without a selection notification.
		[self requestSelectedServiceDetails];
	}];
}

- (void)fetchServicesWithCompletion:(void (^)(NSArray<BPService *> *))completion
{
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSArray *services = [[BPHomebrewInterface sharedInterface] listServices];
		dispatch_async(dispatch_get_main_queue(), ^{ completion(services); });
	});
}

#pragma mark - Operations

- (BPService *)selectedService
{
	NSInteger row = self.tableView.selectedRow;
	return row >= 0 && (NSUInteger)row < self.services.count ? self.services[(NSUInteger)row] : nil;
}

- (void)invalidateServiceDetails
{
	self.detailsGeneration++;
	self.listGeneration++;
	self.details = nil;
	[self showDetailsMessage:NSLocalizedString(@"Services_Details_Select", nil)];
}

- (void)fetchDetailsForName:(NSString *)name completion:(void (^)(BPServiceDetails *))completion
{
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		BPServiceDetails *result = [[BPHomebrewInterface sharedInterface] serviceDetailsForName:name];
		dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
	});
}

- (void)requestSelectedServiceDetails
{
	NSUInteger generation = ++self.detailsGeneration;
	self.details = nil;
	NSString *name = [self selectedService].name;
	if (!name.length) {
		[self showDetailsMessage:NSLocalizedString(@"Services_Details_Select", nil)];
		return;
	}
	[self showDetailsMessage:[NSString stringWithFormat:NSLocalizedString(@"Services_Details_Loading", nil), name]];
	__weak typeof(self) weakSelf = self;
	[self fetchDetailsForName:name completion:^(BPServiceDetails *details) {
		typeof(self) self = weakSelf;
		if (!self || generation != self.detailsGeneration || ![[self selectedService].name isEqualToString:name]) return;
		self.details = details;
		[self renderServiceDetails];
	}];
}

- (void)showDetailsMessage:(NSString *)message
{
	self.detailsText.string = message ?: @"";
	self.revealButton.enabled = [self validatedServiceFileURL] != nil;
	self.logsButton.enabled = [self validatedLogURLs].count > 0;
	self.outputCopyButton.enabled = self.details.rawOutput.length > 0;
}

- (void)renderServiceDetails
{
	BPService *service = self.details.service ?: [self selectedService];
	NSString *unknown = NSLocalizedString(@"Services_Details_Not_Available", nil);
	NSString *text = [NSString stringWithFormat:NSLocalizedString(@"Services_Details_Format", nil),
		service.name ?: unknown, [BPService localizedNameForStatus:service.status], service.pid.stringValue ?: unknown,
		service.user ?: unknown, self.details.serviceFile ?: unknown, self.details.loadedFile ?: unknown, self.details.logPath ?: unknown,
		self.details.errorLogPath ?: unknown, self.details.exitCode.stringValue ?: unknown];
	if (!self.details.available) text = [NSString stringWithFormat:@"%@\n%@\n\n%@", NSLocalizedString(@"Services_Details_Failed", nil), self.details.rawOutput, text];
	[self showDetailsMessage:text];
	[self.detailsText scrollRangeToVisible:NSMakeRange(0, 0)];
}

- (NSArray<NSURL *> *)validatedLogURLs
{
	NSMutableOrderedSet *urls = [NSMutableOrderedSet orderedSet];
	for (NSString *path in @[self.details.logPath ?: @"", self.details.errorLogPath ?: @""]) {
		NSURL *url = [BPServiceDetails readableFileURLForPath:path];
		if (url) [urls addObject:url];
	}
	return urls.array;
}

- (void)showUnavailableFileMessage
{
	[self showDetailsMessage:[self.detailsText.string stringByAppendingFormat:@"\n\n%@", NSLocalizedString(@"Services_File_Unavailable", nil)]];
}

- (void)revealServiceFile:(id)sender
{
	NSURL *url = [self validatedServiceFileURL];
	if (!url) { [self showUnavailableFileMessage]; return; }
	[self revealValidatedFileURL:url];
}

- (NSURL *)validatedServiceFileURL
{
	return [BPServiceDetails readableFileURLForPath:self.details.loadedFile] ?: [BPServiceDetails readableFileURLForPath:self.details.serviceFile];
}

- (void)revealValidatedFileURL:(NSURL *)url
{
	[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[url]];
}

- (void)openServiceLogs:(id)sender
{
	NSArray<NSURL *> *urls = [self validatedLogURLs];
	if (!urls.count) { [self showUnavailableFileMessage]; return; }
	[self openLogURLs:urls];
}

- (void)openLogURLs:(NSArray<NSURL *> *)urls
{
	NSURL *editor = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.TextEdit"];
	if (!editor) { [self showUnavailableFileMessage]; return; }
	NSUInteger generation = self.detailsGeneration;
	[NSWorkspace.sharedWorkspace openURLs:urls withApplicationAtURL:editor configuration:NSWorkspaceOpenConfiguration.configuration
		completionHandler:^(NSRunningApplication *app, NSError *error) {
			if (error) dispatch_async(dispatch_get_main_queue(), ^{
				if (generation == self.detailsGeneration) [self showUnavailableFileMessage];
			});
		}];
}

- (void)copyServiceOutput:(id)sender
{
	if (!self.details.rawOutput.length) return;
	[NSPasteboard.generalPasteboard clearContents];
	[NSPasteboard.generalPasteboard setString:self.details.rawOutput forType:NSPasteboardTypeString];
}

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
	[self invalidateServiceDetails];
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

/// Services with none installed showed headers over blank space too.
- (void)refreshEmptyState
{
	BPEmptyState *state = nil;
	if ([BPEmptyState shouldShowForRowCount:(NSInteger)self.services.count loading:NO])
	{
		state = [BPEmptyState stateForSidebarRow:FormulaeSideBarItemServices searching:NO];
	}
	[BPEmptyStateView presentState:state overView:self.tableView.enclosingScrollView];
}

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
	if (!self.applyingServices) [self requestSelectedServiceDetails];
}

@end
