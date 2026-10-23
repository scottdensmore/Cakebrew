//
//  BPUpdateViewController.m
//  Cakebrew
//
//  Created by Marek Hrusovsky on 21/08/14.
//	Copyright (c) 2014 Bruno Philipe. All rights reserved.
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

#import "BPUpdateViewController.h"
#import "BPHomebrewInterface.h"
#import "BPStyle.h"
#import "BPAppDelegate.h"
#import "BPAutoScrollTextView.h"
#import "BPFormulaInformation-Swift.h"

@interface BPUpdateViewController ()

@property (strong, nonatomic) IBOutlet BPAutoScrollTextView *updateTextView;
@property (weak, nonatomic) IBOutlet NSProgressIndicator *progressIndicator;
@property (assign) BOOL isPerformingUpdate;
@property (strong, nonatomic) BPConsoleToolHost *consoleHost;

@end

@implementation BPUpdateViewController

- (void)loadView {
	BPAutoScrollTextView *textView = [[BPAutoScrollTextView alloc] initWithFrame:NSMakeRect(0, 0, 404, 232)];
	textView.editable = NO;
	textView.selectable = YES;
	textView.richText = NO;
	textView.font = [BPStyle defaultFixedWidthFont];
	textView.textColor = NSColor.textColor;
	textView.backgroundColor = NSColor.textBackgroundColor;
	textView.textContainerInset = NSMakeSize(8, 8);
	textView.autoresizingMask = NSViewWidthSizable;
	textView.verticallyResizable = YES;
	textView.textContainer.widthTracksTextView = YES;
	self.updateTextView = textView;
	self.isPerformingUpdate = NO;

	NSString *title = [NSBundle.mainBundle localizedStringForKey:@"a3Y-VX-bpV.title"
														   value:NSLocalizedString(@"Homebrew Updater", nil)
														   table:@"BPUpdateView"];
	NSString *runTitle = [NSBundle.mainBundle localizedStringForKey:@"MVF-cn-lfW.title"
															  value:NSLocalizedString(@"Update Homebrew", nil)
															  table:@"BPUpdateView"];
	NSString *clearTitle = [NSBundle.mainBundle localizedStringForKey:@"EE6-5g-Jos.title"
																value:NSLocalizedString(@"Clear Log", nil)
																table:@"BPUpdateView"];

	self.consoleHost = [[BPConsoleToolHost alloc] initWithTextView:textView
															 title:title
														  subtitle:nil
													runButtonTitle:runTitle
												  clearButtonTitle:clearTitle];
	__weak typeof(self) weakSelf = self;
	self.consoleHost.onRun = ^{
		[weakSelf runStopUpdate:nil];
	};
	self.consoleHost.onClear = ^{
		[weakSelf clearLogUpdate:nil];
	};
	self.view = self.consoleHost.viewController.view;
}

- (void)awakeFromNib {
	self.progressIndicator.accessibilityLabel = NSLocalizedString(@"VoiceOver_Operation_Progress", nil);
	NSFont *font = [BPStyle defaultFixedWidthFont];
	[self.updateTextView setFont:font];
	self.isPerformingUpdate = NO;
}

- (NSString *)nibName {
	return @"BPUpdateView";
}

- (IBAction)runStopUpdate:(id)sender {
	BPAppDelegate *appDelegate = BPAppDelegateRef;
	
	if (appDelegate.isRunningBackgroundTask)
	{
		[appDelegate displayBackgroundWarning];
		return;
	}
	[appDelegate setRunningBackgroundTask:YES];
	
	[self.updateTextView clearOutput];
	self.isPerformingUpdate = YES;
	self.consoleHost.isRunning = YES;
	[self.consoleHost syncLogFromTextView];
	[self.progressIndicator startAnimation:sender];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
		[[BPHomebrewInterface sharedInterface] updateWithReturnBlock:^(NSString *output) {
			[self.updateTextView appendOutput:output];
			dispatch_async(dispatch_get_main_queue(), ^{
				[self.consoleHost syncLogFromTextView];
			});
		}];

		dispatch_async(dispatch_get_main_queue(), ^{
			[self.updateTextView flushPendingOutput];
			[self.progressIndicator stopAnimation:sender];
			self.isPerformingUpdate = NO;
			self.consoleHost.isRunning = NO;
			[self.consoleHost syncLogFromTextView];
			[appDelegate setRunningBackgroundTask:NO];
			
			NSString *title = NSLocalizedString(@"Homebrew_Task_Finished", nil);
			NSString *desc = NSLocalizedString(@"Notification_Update", nil);
			[BPAppDelegateRef requestUserAttentionWithMessageTitle:title andDescription:desc];
		});
	});
}

- (IBAction)clearLogUpdate:(id)sender {
	[self.updateTextView clearOutput];
	self.updateTextView.string = @"";
	[self.consoleHost syncLogFromTextView];
}

@end
