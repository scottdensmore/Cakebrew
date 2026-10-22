#import "BPAutoremoveWindowController.h"
#import "BPAutoremovePreview.h"
#import "BPAutoremoveOperation.h"
#import "BPHomebrewInterface.h"
#import "BPHomebrewManager.h"
#import "BPAutoScrollTextView.h"
#import "BPAppDelegate.h"
#import "BPFormulaInformation-Swift.h"

@interface BPAutoremoveWindowController ()
@property (strong) BPHomebrewInterface *interface;
@property (strong) BPHomebrewManager *manager;
@property (strong) BPAutoremovePreview *preview;
@property (strong) BPAutoremoveOperation *operation;
@property (strong) NSProgress *previewProgress;
@property (strong) NSTextField *statusLabel;
@property (strong) BPAutoScrollTextView *outputView;
@property (strong) NSButton *removeButton;
@property (strong) NSButton *cancelButton;
@property (strong, nonatomic) BPAutoremoveHost *autoremoveHost;
@property BOOL busy;
@end

@implementation BPAutoremoveWindowController
+ (instancetype)presentForWindow:(NSWindow *)parent interface:(BPHomebrewInterface *)interface manager:(BPHomebrewManager *)manager
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 680, 480) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	BPAutoremoveWindowController *controller = [[self alloc] initWithWindow:window];
	controller.interface = interface; controller.manager = manager;
	[controller buildContent];
	BPAppDelegateRef.runningBackgroundTask = YES;
	[parent beginSheet:window completionHandler:^(NSModalResponse response) { BPAppDelegateRef.runningBackgroundTask = NO; }];
	[controller loadPreview];
	return controller;
}
- (void)buildContent
{
	self.window.title = NSLocalizedString(@"Remove Unused Dependencies", nil);
	self.statusLabel = [NSTextField wrappingLabelWithString:NSLocalizedString(@"Checking unused dependencies…", nil)];
	self.outputView = [[BPAutoScrollTextView alloc] initWithFrame:NSMakeRect(0, 0, 620, 280)];
	self.outputView.editable = NO; self.outputView.selectable = YES;
	self.outputView.richText = NO; self.outputView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
	self.outputView.textColor = NSColor.textColor; self.outputView.backgroundColor = NSColor.textBackgroundColor;
	self.outputView.textContainerInset = NSMakeSize(8, 8);
	self.outputView.autoresizingMask = NSViewWidthSizable;
	self.outputView.verticallyResizable = YES; self.outputView.textContainer.widthTracksTextView = YES;
	self.outputView.accessibilityIdentifier = @"autoremove.output";
	self.outputView.accessibilityLabel = NSLocalizedString(@"Unused dependency preview and command output", nil);
	self.removeButton = [NSButton buttonWithTitle:NSLocalizedString(@"Remove Reviewed Dependencies", nil) target:self action:@selector(removeReviewed:)];
	self.removeButton.enabled = NO;
	self.cancelButton = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", nil) target:self action:@selector(cancelOrClose:)];
	self.cancelButton.enabled = YES;

	self.autoremoveHost = [[BPAutoremoveHost alloc] initWithOutputTextView:self.outputView];
	__weak typeof(self) weakSelf = self;
	self.autoremoveHost.onRemove = ^{ [weakSelf removeReviewed:nil]; };
	self.autoremoveHost.onCancelOrClose = ^{ [weakSelf cancelOrClose:nil]; };

	NSView *hostView = self.autoremoveHost.viewController.view;
	hostView.translatesAutoresizingMaskIntoConstraints = NO;
	[self.window.contentView addSubview:hostView];
	[NSLayoutConstraint activateConstraints:@[
		[hostView.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor],
		[hostView.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor],
		[hostView.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor],
		[hostView.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor]
	]];
	[self syncAutoremoveHostState];
}
- (void)syncAutoremoveHostState
{
	[self.autoremoveHost updateWithStatusText:self.statusLabel.stringValue ?: @""
								removeEnabled:self.removeButton.enabled
								  cancelTitle:self.cancelButton.title ?: @""
								cancelEnabled:self.cancelButton.enabled
										 busy:self.busy];
}
- (void)loadPreview
{
	self.busy = YES;
	[self syncAutoremoveHostState];
	self.previewProgress = [NSProgress progressWithTotalUnitCount:1];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		BPAutoremovePreview *preview = [self.interface previewAutoremoveWithProgress:self.previewProgress];
		dispatch_async(dispatch_get_main_queue(), ^{
			self.busy = NO; self.preview = preview;
			self.outputView.string = preview.rawOutput;
			self.cancelButton.enabled = YES;
			if (self.previewProgress.cancelled) {
				self.statusLabel.stringValue = NSLocalizedString(@"Cancelled before removal. Nothing was removed.", nil);
			} else if (!preview.valid) {
				self.statusLabel.stringValue = NSLocalizedString(@"The unused dependency preview could not be verified. Nothing can be removed.", nil);
			} else if (!preview.names.count) {
				self.statusLabel.stringValue = NSLocalizedString(@"No unused dependencies to remove.", nil);
			} else {
				self.statusLabel.stringValue = [NSString localizedStringWithFormat:NSLocalizedString(@"Review %lu unused dependencies before removal.", nil), (unsigned long)preview.names.count];
				self.removeButton.enabled = YES;
			}
			self.cancelButton.title = NSLocalizedString(@"Close", nil);
			[self syncAutoremoveHostState];
		});
	});
}
- (void)removeReviewed:(id)sender
{
	if (self.busy || !self.removeButton.enabled || !self.preview.valid || !self.preview.names.count) return;
	self.busy = YES; self.removeButton.enabled = NO;
	self.cancelButton.title = NSLocalizedString(@"Cancel", nil);
	self.statusLabel.stringValue = NSLocalizedString(@"Rechecking and removing reviewed dependencies…", nil);
	[self syncAutoremoveHostState];
	self.operation = [[BPAutoremoveOperation alloc] initWithPreview:self.preview interface:self.interface];
	[self.outputView appendOutput:@"\n"];
	[self.operation startWithOutput:^(NSString *chunk) { [self.outputView appendOutput:chunk]; }
	completion:^(BOOL success, BOOL cancelled, BOOL attempted, NSString *message) {
		[self.outputView flushPendingOutput];
		self.cancelButton.enabled = NO;
		[self syncAutoremoveHostState];
		void (^finished)(BOOL) = ^(BOOL refreshed) {
			self.statusLabel.stringValue = refreshed ? message : [message stringByAppendingFormat:@"\n%@", NSLocalizedString(@"Some formula or service lists could not be refreshed. Previous values were retained; refresh again before another operation.", nil)];
			self.busy = NO;
			self.cancelButton.title = NSLocalizedString(@"Close", nil);
			self.cancelButton.enabled = YES;
			[self syncAutoremoveHostState];
		};
		if (attempted) [self.manager refreshFormulaStateAfterRemovalWithCompletion:finished];
		else finished(YES);
	}];
}
- (void)cancelOrClose:(id)sender
{
	if (self.busy) {
		self.cancelButton.enabled = NO;
		self.statusLabel.stringValue = NSLocalizedString(@"Cancelling; waiting for Homebrew to stop…", nil);
		[self syncAutoremoveHostState];
		if (self.operation) [self.operation cancel];
		else { @synchronized (self.previewProgress) { [self.previewProgress cancel]; } }
	} else {
		[self.window.sheetParent endSheet:self.window];
	}
}
@end
