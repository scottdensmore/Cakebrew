//
//  BPBundleWindowController.m
//  Cakebrew
//
//  Created by Bruno Philipe on 20/02/16.
//  Copyright © 2016 Bruno Philipe. All rights reserved.
//

#import "BPBundleWindowController.h"
#import <objc/runtime.h>
#import "BPAppDelegate.h"
#import "BPHomebrewInterface.h"
#import "BPAutoScrollTextView.h"
#import "BPBrewfilePlan.h"
#import "BPBrewfileImportOperation.h"
#import "BPBrewfileExportOperation.h"
#import "BPFormulaInformation-Swift.h"

static const void *kBPBrewfileReviewHostAssocKey = &kBPBrewfileReviewHostAssocKey;

@interface BPBundleWindowController ()

@property (strong) IBOutlet NSView *viewOperationContainer;

@property (strong) IBOutlet NSView *viewExportProgress;
@property (strong) IBOutlet NSView *viewImportProgress;

@property (strong) IBOutlet BPAutoScrollTextView *textViewImport;
@property (strong) IBOutlet NSTextField *progressLabelImport;
@property (strong) IBOutlet NSImageView *statusViewExport;
@property (strong) IBOutlet NSTextField *statusLabelExport;
@property (strong) IBOutlet NSTextField *progressLabelExport;

@property (strong) IBOutlet NSProgressIndicator *progressIndicator;
@property (strong) IBOutlet NSButton *buttonClose;

@property (nonatomic, copy) void (^windowLoadedBlock)(void);
@property (nonatomic, copy) void (^operationBlock)(void);
@property (strong) BPBrewfileImportOperation *importOperation;
@property (strong) BPBrewfileExportOperation *exportOperation;
@property (strong, nonatomic) BPBundleOperationHost *bundleHost;


@end

@implementation BPBundleWindowController

+ (BPBrewfileReviewHost *)reviewHostForPlan:(BPBrewfilePlan *)plan
								   fileName:(NSString *)fileName
									  error:(NSError *)error
							entriesTextView:(NSTextView **)outTextView
{
	NSTextView *text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 550, 210)];
	text.editable = NO;
	text.selectable = YES;
	text.richText = NO;
	text.font = [NSFont systemFontOfSize:13];
	text.textColor = NSColor.textColor;
	text.backgroundColor = NSColor.textBackgroundColor;
	text.textContainerInset = NSMakeSize(10, 10);
	text.autoresizingMask = NSViewWidthSizable;
	text.verticallyResizable = YES;
	text.textContainer.widthTracksTextView = YES;
	text.accessibilityIdentifier = @"brewfile.review.entries";
	text.string = error.localizedDescription ?: (plan.reviewText ?: @"");
	if ([BPHomebrewInterface sharedInterface].brewTransport != kBPBrewTransportDirect) {
		text.string = NSLocalizedString(@"Reviewed import requires the standard, non-sandboxed Cakebrew app. Helper transport is not supported.", nil);
	}
	if (outTextView) {
		*outTextView = text;
	}

	NSInteger installedCount = 0;
	NSInteger missingCount = 0;
	NSInteger notCheckedCount = 0;
	NSInteger formulaCount = 0;
	NSInteger caskCount = 0;
	NSInteger tapCount = 0;
	NSInteger otherCount = 0;

	for (BPBrewfileEntry *entry in plan.entries) {
		if ([entry.status isEqualToString:@"Installed"]) {
			installedCount++;
		} else if ([entry.status isEqualToString:@"Missing"]) {
			missingCount++;
		} else {
			notCheckedCount++;
		}

		if ([entry.kind isEqualToString:@"brew"]) {
			formulaCount++;
		} else if ([entry.kind isEqualToString:@"cask"]) {
			caskCount++;
		} else if ([entry.kind isEqualToString:@"tap"]) {
			tapCount++;
		} else {
			otherCount++;
		}
	}

	BOOL canInstall = plan.canInstall && [BPHomebrewInterface sharedInterface].brewTransport == kBPBrewTransportDirect;
	BPBrewfileReviewHost *host = [[BPBrewfileReviewHost alloc] initWithEntriesTextView:text
																			  fileName:fileName.length ? fileName : @"Brewfile"
																		installedCount:installedCount
																		  missingCount:missingCount
																	   notCheckedCount:notCheckedCount
																		  formulaCount:formulaCount
																			 caskCount:caskCount
																			  tapCount:tapCount
																			otherCount:otherCount
																			canInstall:canInstall
																		   summaryText:plan.reviewText ?: @""];
	host.viewController.view.frame = NSMakeRect(0, 0, 570, 280);
	return host;
}

+ (void)reviewFile:(NSURL *)url inventories:(NSDictionary *)inventories parentWindow:(NSWindow *)window completion:(void (^)(BPBrewfilePlan *))completion
{
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
  NSError *error = nil;
  BPBrewfilePlan *plan = [BPBrewfilePlan planWithURL:url inventories:inventories error:&error];
  dispatch_async(dispatch_get_main_queue(), ^{
   NSAlert *alert = [NSAlert new];
   alert.messageText = NSLocalizedString(@"Review Brewfile", nil);
   alert.informativeText = [NSString stringWithFormat:@"%@\n\n%@", url.lastPathComponent,
    NSLocalizedString(@"Direct entries only, not a dependency or upgrade plan. Installed means present in the current inventory, not up to date. Homebrew may upgrade packages, install dependencies and required tools, and run package installation scripts. Only the reviewed literal entries will be submitted.", nil)];
   NSButton *install = [alert addButtonWithTitle:NSLocalizedString(@"Install Reviewed Entries", nil)];
   install.accessibilityIdentifier = @"brewfile.review.install";
   install.enabled = plan.canInstall && [BPHomebrewInterface sharedInterface].brewTransport == kBPBrewTransportDirect;
   NSButton *cancel = [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
   cancel.accessibilityIdentifier = @"brewfile.review.cancel";
   BPBrewfileReviewHost *reviewHost = [self reviewHostForPlan:plan
                                                     fileName:url.lastPathComponent
                                                        error:error
                                              entriesTextView:NULL];
   objc_setAssociatedObject(alert, kBPBrewfileReviewHostAssocKey, reviewHost, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
   alert.accessoryView = reviewHost.viewController.view;
   [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
    if (completion) completion(result == NSAlertFirstButtonReturn && install.enabled ? plan : nil);
   }];
  });
 });
}

+ (BPBundleWindowController *)runImportOperationWithPlan:(BPBrewfilePlan *)plan
{
	BPBundleWindowController *controller = [self createWindow];
	[BPAppDelegateRef setRunningBackgroundTask:YES];
	[controller startSheetOnMainWindow];
	[controller runImportOperationWithPlan:plan];
	return controller;
}

+ (BPBundleWindowController*)runExportOperationWithFile:(NSURL*)fileURL
{
	BPBundleWindowController *controller = [self createWindow];
	[BPAppDelegateRef setRunningBackgroundTask:YES];
	[controller startSheetOnMainWindow];
	[controller runExportOperationWithFile:fileURL];
	return controller;
}

+ (BPBundleWindowController*)createWindow
{
	return [[BPBundleWindowController alloc] initWithWindowNibName:@"BPBundleWindow"];
}

- (void)loadWindow
{
	if ([NSBundle.mainBundle pathForResource:@"BPBundleWindow" ofType:@"nib"]) {
		[super loadWindow];
	} else {
		self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 413, 289)
												  styleMask:NSWindowStyleMaskTitled
													backing:NSBackingStoreBuffered
													  defer:NO];
	}
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	if (!self.textViewImport) {
		self.textViewImport = [[BPAutoScrollTextView alloc] initWithFrame:NSMakeRect(0, 0, 373, 197)];
	}
	if (!self.buttonClose) {
		self.buttonClose = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 28)];
	}
	self.textViewImport.editable = NO;
	self.textViewImport.selectable = YES;
	self.textViewImport.richText = NO;
	self.textViewImport.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
	self.textViewImport.accessibilityIdentifier = @"brewfile.import.output";

	self.bundleHost = [[BPBundleOperationHost alloc] initWithImportTextView:self.textViewImport];
	__weak typeof(self) weakSelf = self;
	self.bundleHost.onAction = ^{
		[weakSelf didClickClose:nil];
	};

	NSView *contentView = self.window.contentView;
	for (NSView *subview in [contentView.subviews copy]) {
		[subview removeFromSuperview];
	}
	NSView *hostView = self.bundleHost.viewController.view;
	hostView.translatesAutoresizingMaskIntoConstraints = NO;
	[contentView addSubview:hostView];
	[NSLayoutConstraint activateConstraints:@[
		[hostView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
		[hostView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
		[hostView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
		[hostView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
	]];
}

- (void)startSheetOnMainWindow
{
	[BPAppDelegateRef.window beginSheet:self.window completionHandler:^(NSModalResponse returnCode) {
		[BPAppDelegateRef setRunningBackgroundTask:NO];
	}];
}

- (void)runImportOperationWithPlan:(BPBrewfilePlan *)plan
{
	[self.textViewImport clearOutput];
	self.window.title = NSLocalizedString(@"Import Brewfile", nil);
	[self.window setContentSize:NSMakeSize(650, 380)];
	self.textViewImport.accessibilityIdentifier = @"brewfile.import.output";
	self.buttonClose.title = NSLocalizedString(@"Cancel", nil);
	self.buttonClose.enabled = YES;
	[self.bundleHost configureImportWithStatusText:nil
									   actionTitle:NSLocalizedString(@"Cancel", nil)
									 actionEnabled:YES
										   running:YES];
	self.importOperation = [[BPBrewfileImportOperation alloc] initWithPlan:plan interface:[BPHomebrewInterface sharedInterface]];
	[self.importOperation startWithOutput:^(NSString *output) {
		[self.textViewImport appendOutput:output];
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.bundleHost syncLogFromTextView];
		});
	} completion:^(BOOL success, BOOL cancelled, NSError *error) {
		NSString *status = cancelled ? NSLocalizedString(@"Import cancelled. Some changes may already have been made.", nil) :
			success ? NSLocalizedString(@"Import finished.", nil) : NSLocalizedString(@"Import failed. Review the output for details.", nil);
		self.progressLabelImport.stringValue = status;
		if (error) [self.textViewImport appendOutput:error.localizedDescription];
		[self.textViewImport flushPendingOutput];
		self.buttonClose.title = NSLocalizedString(@"Close", nil);
		self.buttonClose.enabled = YES;
		[self.bundleHost configureImportWithStatusText:status
										   actionTitle:NSLocalizedString(@"Close", nil)
										 actionEnabled:YES
											   running:NO];
		[self.bundleHost syncLogFromTextView];
	}];
}

- (void)runExportOperationWithFile:(NSURL*)fileURL
{
	self.buttonClose.enabled = NO;
	[self.bundleHost configureExportWithStatusText:nil
										detailText:nil
									   actionTitle:nil
									 actionEnabled:NO
										   running:YES
										  finished:NO
										 succeeded:NO];
	self.exportOperation = [[BPBrewfileExportOperation alloc] initWithURL:fileURL interface:[BPHomebrewInterface sharedInterface]];
	[self.exportOperation startWithCompletion:^(NSError *error) {
		BOOL succeeded = (error == nil);
		NSString *statusText = error ? NSLocalizedString(@"Brewfile_Export_Failed", nil) : nil;
		NSString *detailText = error ? error.localizedDescription : nil;
		self.buttonClose.enabled = YES;
		[self.bundleHost configureExportWithStatusText:statusText
											detailText:detailText
										   actionTitle:nil
										 actionEnabled:YES
											   running:NO
											  finished:YES
											 succeeded:succeeded];
	}];
}

- (void)embedView:(NSView*)view
{
}

- (IBAction)didClickClose:(id)sender
{
	if (self.exportOperation.running) return;
	if (self.importOperation.running) {
		[self.importOperation cancel];
		self.buttonClose.enabled = NO;
		NSString *cancelling = NSLocalizedString(@"Cancelling… Waiting for Homebrew to exit.", nil);
		self.progressLabelImport.stringValue = cancelling;
		[self.bundleHost configureImportWithStatusText:cancelling
										   actionTitle:NSLocalizedString(@"Cancel", nil)
										 actionEnabled:NO
											   running:YES];
		return;
	}
	NSWindow *mainWindow = self.window.sheetParent;
	[mainWindow endSheet:self.window];
}

@end
