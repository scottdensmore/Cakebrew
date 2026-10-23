//
//  BPDoctorViewController.m
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

#import "BPDoctorViewController.h"
#import "BPHomebrewInterface.h"
#import "BPAppDelegate.h"
#import "BPStyle.h"
#import "BPAutoScrollTextView.h"
#import "BPFormulaInformation-Swift.h"

@interface BPDoctorViewController ()

@property (strong, nonatomic) IBOutlet BPAutoScrollTextView *doctorTextView;
@property (weak, nonatomic) IBOutlet NSProgressIndicator *progressIndicator;
@property (assign) BOOL isPerformingDoctor;
@property (strong, nonatomic) BPConsoleToolHost *consoleHost;

@end

@implementation BPDoctorViewController

- (void)loadView {
	BPAutoScrollTextView *textView = [[BPAutoScrollTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 232)];
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
	self.doctorTextView = textView;
	self.isPerformingDoctor = NO;

	NSString *title = [NSBundle.mainBundle localizedStringForKey:@"UHp-GH-2qP.title"
														   value:NSLocalizedString(@"Homebrew Doctor", nil)
														   table:@"BPDoctorView"];
	NSString *runTitle = [NSBundle.mainBundle localizedStringForKey:@"YyI-zq-THZ.title"
															  value:NSLocalizedString(@"Run Doctor", nil)
															  table:@"BPDoctorView"];
	NSString *clearTitle = [NSBundle.mainBundle localizedStringForKey:@"AlR-6d-ju7.title"
																value:NSLocalizedString(@"Clear Log", nil)
																table:@"BPDoctorView"];

	self.consoleHost = [[BPConsoleToolHost alloc] initWithTextView:textView
															 title:title
														  subtitle:nil
													runButtonTitle:runTitle
												  clearButtonTitle:clearTitle];
	__weak typeof(self) weakSelf = self;
	self.consoleHost.onRun = ^{
		[weakSelf runStopDoctor:nil];
	};
	self.consoleHost.onClear = ^{
		[weakSelf clearLogDoctor:nil];
	};
	self.view = self.consoleHost.viewController.view;
}

- (void)awakeFromNib {
	self.progressIndicator.accessibilityLabel = NSLocalizedString(@"VoiceOver_Operation_Progress", nil);
	NSFont *font = [BPStyle defaultFixedWidthFont];
	[self.doctorTextView setFont:font];
	self.isPerformingDoctor = NO;
}

- (NSString *)nibName {
	return @"BPDoctorView";
}

- (IBAction)runStopDoctor:(id)sender {
	BPAppDelegate *appDelegate = BPAppDelegateRef;
	
	if (appDelegate.isRunningBackgroundTask)
	{
		[appDelegate displayBackgroundWarning];
		return;
	}
	[appDelegate setRunningBackgroundTask:YES];
	
	[self.doctorTextView clearOutput];
	self.isPerformingDoctor = YES;
	self.consoleHost.isRunning = YES;
	[self.consoleHost syncLogFromTextView];
	[self.progressIndicator startAnimation:sender];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
		[[BPHomebrewInterface sharedInterface] runDoctorWithReturnBlock:^(NSString *output) {
			[self.doctorTextView appendOutput:output];
			dispatch_async(dispatch_get_main_queue(), ^{
				[self.consoleHost syncLogFromTextView];
			});
		}];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			NSLog(@"Finished doctor");
			[self.doctorTextView flushPendingOutput];
			[self.progressIndicator stopAnimation:sender];
			self.isPerformingDoctor = NO;
			self.consoleHost.isRunning = NO;
			[self.consoleHost syncLogFromTextView];
			[appDelegate setRunningBackgroundTask:NO];
			
			NSString *title = NSLocalizedString(@"Homebrew_Task_Finished", nil);
			NSString *desc = NSLocalizedString(@"Notification_Doctor", nil);
			[BPAppDelegateRef requestUserAttentionWithMessageTitle:title andDescription:desc];
		});
	});
}

- (IBAction)clearLogDoctor:(id)sender {
	[self.doctorTextView clearOutput];
	self.doctorTextView.string = @"";
	[self.consoleHost syncLogFromTextView];
}

@end
