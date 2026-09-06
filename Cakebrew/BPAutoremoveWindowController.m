#import "BPAutoremoveWindowController.h"
#import "BPAutoremovePreview.h"
#import "BPAutoremoveOperation.h"
#import "BPHomebrewInterface.h"
#import "BPHomebrewManager.h"
#import "BPAutoScrollTextView.h"
#import "BPAppDelegate.h"

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
	NSStackView *stack = [NSStackView stackViewWithViews:@[]];
	stack.orientation = NSUserInterfaceLayoutOrientationVertical;
	stack.alignment = NSLayoutAttributeLeading;
	stack.spacing = 14;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[self.window.contentView addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:20],
		[stack.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-20],
		[stack.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:20],
		[stack.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor constant:-20]]];
	self.statusLabel = [NSTextField wrappingLabelWithString:NSLocalizedString(@"Checking unused dependencies…", nil)];
	self.statusLabel.font = [NSFont boldSystemFontOfSize:14];
	self.statusLabel.accessibilityIdentifier = @"autoremove.status";
	[stack addArrangedSubview:self.statusLabel];
	NSTextField *warning = [NSTextField wrappingLabelWithString:NSLocalizedString(@"Only the reviewed formulae will be submitted for removal. Homebrew will recheck its dependency rules. Do not run other Homebrew operations until this finishes: external changes cannot be checked atomically.", nil)];
	[stack addArrangedSubview:warning];
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	scroll.hasVerticalScroller = YES; scroll.borderType = NSBezelBorder;
	self.outputView = [[BPAutoScrollTextView alloc] initWithFrame:NSMakeRect(0, 0, 620, 280)];
	self.outputView.editable = NO; self.outputView.selectable = YES;
	self.outputView.richText = NO; self.outputView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
	self.outputView.textColor = NSColor.textColor; self.outputView.backgroundColor = NSColor.textBackgroundColor;
	self.outputView.textContainerInset = NSMakeSize(8, 8);
	self.outputView.autoresizingMask = NSViewWidthSizable;
	self.outputView.verticallyResizable = YES; self.outputView.textContainer.widthTracksTextView = YES;
	self.outputView.accessibilityIdentifier = @"autoremove.output";
	self.outputView.accessibilityLabel = NSLocalizedString(@"Unused dependency preview and command output", nil);
	scroll.documentView = self.outputView;
	[stack addArrangedSubview:scroll];
	self.removeButton = [NSButton buttonWithTitle:NSLocalizedString(@"Remove Reviewed Dependencies", nil) target:self action:@selector(removeReviewed:)];
	self.removeButton.accessibilityIdentifier = @"autoremove.remove";
	self.removeButton.enabled = NO;
	self.cancelButton = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", nil) target:self action:@selector(cancelOrClose:)];
	self.cancelButton.accessibilityIdentifier = @"autoremove.cancel";
	self.cancelButton.keyEquivalent = @"\e";
	NSStackView *buttons = [NSStackView stackViewWithViews:@[self.cancelButton, self.removeButton]];
	buttons.spacing = 12;
	[stack addArrangedSubview:buttons];
	[NSLayoutConstraint activateConstraints:@[
		[self.statusLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
		[warning.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
		[scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
		[scroll.heightAnchor constraintGreaterThanOrEqualToConstant:180]]];
	[scroll setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
}
- (void)loadPreview
{
	self.busy = YES;
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
		});
	});
}
- (void)removeReviewed:(id)sender
{
	if (self.busy || !self.removeButton.enabled || !self.preview.valid || !self.preview.names.count) return;
	self.busy = YES; self.removeButton.enabled = NO;
	self.cancelButton.title = NSLocalizedString(@"Cancel", nil);
	self.statusLabel.stringValue = NSLocalizedString(@"Rechecking and removing reviewed dependencies…", nil);
	self.operation = [[BPAutoremoveOperation alloc] initWithPreview:self.preview interface:self.interface];
	[self.outputView appendOutput:@"\n"];
	[self.operation startWithOutput:^(NSString *chunk) { [self.outputView appendOutput:chunk]; }
	completion:^(BOOL success, BOOL cancelled, BOOL attempted, NSString *message) {
		[self.outputView flushPendingOutput];
		self.cancelButton.enabled = NO;
		void (^finished)(BOOL) = ^(BOOL refreshed) {
			self.statusLabel.stringValue = refreshed ? message : [message stringByAppendingFormat:@"\n%@", NSLocalizedString(@"Some formula or service lists could not be refreshed. Previous values were retained; refresh again before another operation.", nil)];
			self.busy = NO;
			self.cancelButton.title = NSLocalizedString(@"Close", nil);
			self.cancelButton.enabled = YES;
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
		if (self.operation) [self.operation cancel];
		else { @synchronized (self.previewProgress) { [self.previewProgress cancel]; } }
	} else {
		[self.window.sheetParent endSheet:self.window];
	}
}
@end
