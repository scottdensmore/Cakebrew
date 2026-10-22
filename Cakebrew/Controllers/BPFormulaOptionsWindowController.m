//
//  BPFormulaOptionsWindowController.m
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

#import "BPFormulaOptionsWindowController.h"
#import "BPFormula.h"
#import "BPAppDelegate.h"
#import "BPFormulaInformation-Swift.h"

//these constants must match arraycontroller in XIB (array controller + binding on table columns)
static NSString * const kFormulaOptionCommand = @"formulaOptionCommand";
static NSString * const kIsFormulaOptionCommandApplied = @"isFormulaOptionCommandApplied";
static NSString * const kFormulaOptionDescription = @"formulaOptionDescription";

static NSString * const kFormulaOptionsTitleColumnId = @"title";

@interface BPFormulaOptionsWindowController () <NSTableViewDelegate>

@property (weak) IBOutlet NSTextField *userHelpLabel;
@property (weak) IBOutlet NSTextField *formulaNameLabel;
@property (weak) IBOutlet NSTextField *optionDetailsTextField;
@property (weak) IBOutlet NSTableView *formulaOptionsTableView;
@property (strong) IBOutlet NSArrayController *formulasArrayController;

@property (nonatomic, strong) NSMutableArray *availableOptions;
@property (strong) BPFormula *formula;
@property (strong, nonatomic) BPFormulaOptionsHost *optionsHost;

@end

@implementation BPFormulaOptionsWindowController

- (void)awakeFromNib {
	NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:self.availableOptions.count];
	NSMutableArray<NSString *> *explanations = [NSMutableArray arrayWithCapacity:self.availableOptions.count];
	for (NSDictionary *dict in self.availableOptions) {
		[names addObject:dict[kFormulaOptionCommand] ?: @""];
		[explanations addObject:dict[kFormulaOptionDescription] ?: @""];
	}

	self.optionsHost = [[BPFormulaOptionsHost alloc] init];
	[self.optionsHost configureWithFormulaName:self.formula.name ?: @""
								   optionNames:names
							optionExplanations:explanations];

	__weak typeof(self) weakSelf = self;
	self.optionsHost.onOptionToggled = ^(NSString *optionName, BOOL applied) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) return;
		for (NSMutableDictionary *entry in strongSelf.availableOptions) {
			if ([entry[kFormulaOptionCommand] isEqualToString:optionName]) {
				entry[kIsFormulaOptionCommandApplied] = @(applied);
			}
		}
	};
	self.optionsHost.onCancel = ^{
		[weakSelf cancel:nil];
	};
	self.optionsHost.onInstall = ^{
		[weakSelf install:nil];
	};

	NSView *contentView = self.window.contentView;
	for (NSView *subview in [contentView.subviews copy]) {
		[subview removeFromSuperview];
	}
	NSView *hostView = self.optionsHost.viewController.view;
	hostView.translatesAutoresizingMaskIntoConstraints = NO;
	[contentView addSubview:hostView];
	[NSLayoutConstraint activateConstraints:@[
		[hostView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
		[hostView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
		[hostView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
		[hostView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
	]];
}

+ (BPFormulaOptionsWindowController *)runFormula:(BPFormula *)formula withCompletionBlock:(InstalWithOptionsBlock_t)completionBlock
{
	BPFormulaOptionsWindowController *formulaOptionsWindowController;
	formulaOptionsWindowController = [[BPFormulaOptionsWindowController alloc] initWithWindowNibName:@"BPFormulaOptionsWindow"];
	formulaOptionsWindowController.formula = formula;
	formulaOptionsWindowController.installWithOptionsBlock = completionBlock;
	NSMutableArray *availableOptions = [[NSMutableArray alloc] init];
	
	for (BPFormulaOption *option in [formula options]) {
		id optionCommand = option.name;
		id optionDescription = option.explanation ? : @"";
		if (optionCommand) {
			
			// We want to be able to modify content of kWantsToInstallOption within table view
			NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] initWithDictionary:@{ kFormulaOptionCommand : optionCommand,
																								 kIsFormulaOptionCommandApplied : @NO,
																								 kFormulaOptionDescription : optionDescription}];
			[availableOptions addObject:dictionary];
		}
	}
	formulaOptionsWindowController.availableOptions = availableOptions;
	
	
	NSWindow *formulaWindow = formulaOptionsWindowController.window;
	[BPAppDelegateRef setRunningBackgroundTask:YES];
	
	[[NSApp mainWindow] beginSheet:formulaWindow completionHandler:^(NSModalResponse returnCode) {
		if (returnCode == NSModalResponseStop) {
			NSArray *options = [formulaOptionsWindowController allSelectedOptions];
			formulaOptionsWindowController.installWithOptionsBlock(options);
		} else {
			[BPAppDelegateRef setRunningBackgroundTask:NO];
		}

	}];

	return formulaOptionsWindowController;
}


/*
 * Return an array with formula options that user wants to use with formula
 */
- (NSArray *)allSelectedOptions {
	if (self.optionsHost) {
		return self.optionsHost.selectedOptionNames;
	}
	NSPredicate *selectedFormulas = [NSPredicate predicateWithFormat:@"%K == %@", kIsFormulaOptionCommandApplied, @YES];
	NSArray *filteredArray = [self.availableOptions filteredArrayUsingPredicate:selectedFormulas];
	NSArray *allOptions = [filteredArray valueForKeyPath:kFormulaOptionCommand];
	return allOptions;
}

- (IBAction)cancel:(id)sender {
	NSWindow *mainWindow = [NSApp mainWindow];
	if ([mainWindow respondsToSelector:@selector(endSheet:returnCode:)]) {
		[mainWindow endSheet:self.window returnCode:NSModalResponseAbort];
	} else {
		[[NSApplication sharedApplication] endSheet:self.window returnCode:NSModalResponseAbort];
	}
}

- (IBAction)install:(id)sender {
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:NSLocalizedString(@"Generic_Attention", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Yes", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_Cancel", nil)];
	[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Formula_Options_Confirmation", nil),
							   self.formula.name]];
	[alert.window setTitle:NSLocalizedString(@"Cakebrew", nil)];
	
	
	NSInteger returnValue = [alert runModal];
	NSInteger modalResponse = NSModalResponseStop;
	if (returnValue != NSAlertFirstButtonReturn) {
		modalResponse = NSModalResponseAbort;
	}
	
	NSWindow *mainWindow = [NSApp mainWindow];
	if ([mainWindow respondsToSelector:@selector(endSheet:returnCode:)]) {
		[mainWindow endSheet:self.window returnCode:modalResponse];
	} else {
		[[NSApplication sharedApplication] endSheet:self.window returnCode:modalResponse];
	}
}

-(void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if ([tableColumn.identifier isEqualToString:kFormulaOptionsTitleColumnId])
		[cell setAccessibilityLabel:[[_formulasArrayController.arrangedObjects objectAtIndex:row] valueForKey:kFormulaOptionDescription]];
}

-(NSString*)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation
{
	return [[_formulasArrayController.arrangedObjects objectAtIndex:row] valueForKey:kFormulaOptionDescription];
}

@end
