//
//  BPFormulaPopoverViewController.m
//  Cakebrew
//
//  Created by Marek Hrusovsky on 05/09/14.
//  Copyright (c) 2014 Bruno Philipe. All rights reserved.
//

#import "BPFormulaPopoverViewController.h"
#import "BPFormula.h"
#import "BPHomebrewInterface.h"
#import "BPTimedDispatch.h"
#import "BPStyle.h"
#import "BPFormulaInformation-Swift.h"

@interface BPFormulaPopoverViewController ()

@property (strong) BPTimedDispatch *timedDispatch;
@property (strong) BPFormulaInformationHost *informationHost;

@end

@implementation BPFormulaPopoverViewController

- (void)awakeFromNib
{
	NSFont *font = [BPStyle defaultFixedWidthFont];
	[self.formulaTextView setFont:font];
	[self.formulaTextView setTextColor:[BPStyle popoverTextViewColor]];
	[self.formulaPopover setContentViewController:self];
	[self setTimedDispatch:[BPTimedDispatch new]];
	[self.formulaTitleLabel setTextColor:[BPStyle popoverTitleColor]];
	[self setInfoType:kBPFormulaInfoTypeGeneral];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(informationPopoverWillClose:)
		name:NSPopoverWillCloseNotification object:self.formulaPopover];
}

- (void)setInfoType:(BPFormulaInfoType)infoType
{
    _infoType = infoType;
    [self.informationHost close];
    self.formulaPopover.behavior = infoType == kBPFormulaInfoTypeGeneral
        ? NSPopoverBehaviorTransient : NSPopoverBehaviorSemitransient;
}

- (void)informationPopoverWillClose:(NSNotification *)notification
{
    // Invalidate before the closing animation. DidClose arrives after animation
    // and can belong to an old presentation when the same popover is reopened.
    [self.informationHost close];
}

- (void)setFormula:(BPFormula *)formula
{
    _formula = formula;
    [self.informationHost close];
    [self.formulaTextView setString:@""];

    if (self.infoType != kBPFormulaInfoTypeGeneral) {
        [self.formulaPopover setContentViewController:self];
        [self displayDependentsInformationForFormula];
        return;
    }
    if (!formula) { return; }

    if (!self.informationHost) {
        self.informationHost = [BPFormulaInformationHost new];
    }
    [self.progressIndicator stopAnimation:nil];
    NSString *name = [formula.name copy];
    BOOL cask = formula.cask;
    uint64_t generation = [self.informationHost beginWithName:name cask:cask];
    [self.formulaPopover setContentViewController:self.informationHost.viewController];

    if (formula.information) {
        [self.informationHost receiveInformation:[formula.information copy] website:[formula.website copy]
            name:name cask:cask generation:generation];
        return;
    }

    // BPFormula remains behind the Objective-C boundary. Its synchronous information
    // load runs off the main queue; only copied values are delivered to the Swift UI.
    __weak typeof(self) weakSelf = self;
    [self.timedDispatch scheduleDispatchAfterTimeInterval:0.3
        inQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0) ofBlock:^{
        [formula setNeedsInformation:YES];
        NSString *information = [formula.information copy];
        NSURL *website = [formula.website copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.informationHost receiveInformation:information website:website
                name:name cask:cask generation:generation];
        });
    }];
}

- (NSString *)nibName
{
    return @"BPFormulaPopoverView";
}

- (void)displayDependentsInformationForFormula
{
	NSString *name = [self.formula name];

	[self.formulaTextView setString:@""];
	[self.progressIndicator startAnimation:nil];

	if (self.infoType == kBPFormulaInfoTypeInstalledDependents)
	{
		[self.formulaTitleLabel setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Formula_Installed_Dependents_Title", nil), name]];

		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
			NSString *string = [[BPHomebrewInterface sharedInterface] dependantsForFormulaName:name onlyInstalled:YES];

			dispatch_async(dispatch_get_main_queue(), ^{
				[self.progressIndicator stopAnimation:nil];
				[self.formulaTextView setString:string];
				[self.formulaTextView scrollToBeginningOfDocument:nil];
				[self.formulaTextView setNeedsDisplay:YES];
			});
		});
	}
	else if (self.infoType == kBPFormulaInfoTypeAllDependents)
	{
		[self.formulaTitleLabel setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Formula_All_Dependents_Title", nil), name]];

		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
			NSString *string = [[BPHomebrewInterface sharedInterface] dependantsForFormulaName:name onlyInstalled:NO];

			dispatch_async(dispatch_get_main_queue(), ^{
				[self.progressIndicator stopAnimation:nil];
				[self.formulaTextView setString:string];
				[self.formulaTextView scrollToBeginningOfDocument:nil];
				[self.formulaTextView setNeedsDisplay:YES];
			});

		});
	}
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
