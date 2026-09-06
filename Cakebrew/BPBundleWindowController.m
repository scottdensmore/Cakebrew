//
//  BPBundleWindowController.m
//  Cakebrew
//
//  Created by Bruno Philipe on 20/02/16.
//  Copyright © 2016 Bruno Philipe. All rights reserved.
//

#import "BPBundleWindowController.h"
#import "BPAppDelegate.h"
#import "BPHomebrewInterface.h"
#import "BPAutoScrollTextView.h"
#import "BPBrewfilePlan.h"
#import "BPBrewfileImportOperation.h"

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


@end

@implementation BPBundleWindowController

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
   NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 570, 260)];
   scroll.hasVerticalScroller = YES; scroll.borderType = NSBezelBorder;
   NSTextView *text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 550, 260)];
   text.editable = NO; text.selectable = YES; text.richText = NO;
   text.font = [NSFont systemFontOfSize:13]; text.textColor = NSColor.textColor; text.backgroundColor = NSColor.textBackgroundColor;
   text.textContainerInset = NSMakeSize(10, 10);
   text.autoresizingMask = NSViewWidthSizable; text.verticallyResizable = YES;
   text.textContainer.widthTracksTextView = YES;
   text.accessibilityIdentifier = @"brewfile.review.entries";
   text.string = error.localizedDescription ?: plan.reviewText;
   if ([BPHomebrewInterface sharedInterface].brewTransport != kBPBrewTransportDirect)
    text.string = NSLocalizedString(@"Reviewed import requires the standard, non-sandboxed Cakebrew app. Helper transport is not supported.", nil);
   scroll.documentView = text; alert.accessoryView = scroll;
   [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
    if (completion) completion(result == NSAlertFirstButtonReturn && install.enabled ? plan : nil);
   }];
  });
 });
}

+ (BPBundleWindowController *)runImportOperationWithPlan:(BPBrewfilePlan *)plan
{
	BPBundleWindowController *controller = [self createWindow];
	__weak BPBundleWindowController *weakController = controller;
	
	[controller setWindowLoadedBlock:^{
		[weakController embedView:[weakController viewImportProgress]];
	}];
	
	[BPAppDelegateRef setRunningBackgroundTask:YES];
	
	[controller startSheetOnMainWindow];
	[controller runImportOperationWithPlan:plan];
	
	return controller;
}

+ (BPBundleWindowController*)runExportOperationWithFile:(NSURL*)fileURL
{
	BPBundleWindowController *controller = [self createWindow];
	__weak BPBundleWindowController *weakController = controller;
	
	[controller setWindowLoadedBlock:^{
		[weakController embedView:[weakController viewExportProgress]];
	}];
	
	[BPAppDelegateRef setRunningBackgroundTask:YES];
	
	[controller startSheetOnMainWindow];
	[controller runExportOperationWithFile:fileURL];
	
	return controller;
}

+ (BPBundleWindowController*)createWindow
{
	return [[BPBundleWindowController alloc] initWithWindowNibName:@"BPBundleWindow"];
}

- (void)windowDidLoad
{
	if (self.windowLoadedBlock)
	{
		self.windowLoadedBlock();
		[self setWindowLoadedBlock:nil];
	}
	
	[self.progressIndicator startAnimation:nil];
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
 self.progressLabelImport.accessibilityIdentifier = @"brewfile.import.status";
 self.buttonClose.accessibilityIdentifier = @"brewfile.import.action";
 self.buttonClose.title = NSLocalizedString(@"Cancel", nil); self.buttonClose.enabled = YES;
 self.importOperation = [[BPBrewfileImportOperation alloc] initWithPlan:plan interface:[BPHomebrewInterface sharedInterface]];
 [self.importOperation startWithOutput:^(NSString *output) {
  [self.textViewImport appendOutput:output];
 } completion:^(BOOL success, BOOL cancelled, NSError *error) {
  self.progressLabelImport.stringValue = cancelled ? NSLocalizedString(@"Import cancelled. Some changes may already have been made.", nil) :
   success ? NSLocalizedString(@"Import finished.", nil) : NSLocalizedString(@"Import failed. Review the output for details.", nil);
  if (error) [self.textViewImport appendOutput:error.localizedDescription];
  self.buttonClose.title = NSLocalizedString(@"Close", nil); self.buttonClose.enabled = YES;
  [self.progressIndicator stopAnimation:nil];
 }];
}

- (void)runExportOperationWithFile:(NSURL*)fileURL
{
	NSError *error = [[BPHomebrewInterface sharedInterface] runBrewExportToolWithPath:[fileURL path]];
	
	if (error)
	{
		[self.statusLabelExport setStringValue:NSLocalizedString(@"Brewfile_Export_Failed", nil)];
		[self.statusViewExport setImage:[NSImage imageNamed:@"status_Error"]];
		[self.progressLabelExport setStringValue:[error localizedDescription]];
		[self.progressLabelExport setHidden:NO];
		
		NSLog(@"%@", error.localizedDescription);
	}
	else
	{
		[self.progressLabelExport setHidden:YES];
	}
	
	[self.statusLabelExport setHidden:NO];
	[self.statusViewExport setHidden:NO];
	[self.buttonClose setEnabled:YES];
	[self.progressIndicator stopAnimation:nil];
}

- (void)embedView:(NSView*)view
{
	[view setTranslatesAutoresizingMaskIntoConstraints:NO];
	
	[self.viewOperationContainer addSubview:view];
	
	[self.viewOperationContainer addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[view]-0-|"
																						options:0
																						metrics:nil
																						  views:@{@"view": view}]];
	
	[self.viewOperationContainer addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[view]-0-|"
																						options:0
																						metrics:nil
																						  views:@{@"view": view}]];
	
	[self.viewOperationContainer setNeedsLayout:YES];
}

- (IBAction)didClickClose:(id)sender
{
 if (self.importOperation.running) {
  [self.importOperation cancel]; self.buttonClose.enabled = NO;
  self.progressLabelImport.stringValue = NSLocalizedString(@"Cancelling… Waiting for Homebrew to exit.", nil);
  return;
 }
	NSWindow *mainWindow = self.window.sheetParent;
	
	[mainWindow endSheet:self.window];
}

@end
