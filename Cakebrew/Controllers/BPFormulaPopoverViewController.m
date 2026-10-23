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
@property (strong) NSPopover *retainedPopover;

@end

@implementation BPFormulaPopoverViewController

- (void)loadView
{
	self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 460, 320)];
	if (!self.formulaPopover) {
		self.retainedPopover = [[NSPopover alloc] init];
		self.formulaPopover = self.retainedPopover;
	}
	[self awakeFromNib];
}

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
    [self.progressIndicator stopAnimation:nil];
    if (!formula) { return; }

    if (!self.informationHost) {
        self.informationHost = [BPFormulaInformationHost new];
    }
    NSString *name = [formula.name copy];
    BOOL cask = formula.cask;
    BPFormulaInfoType infoType = self.infoType;
    uint64_t generation = [self.informationHost beginWithName:name cask:cask infoType:infoType];
    [self.formulaPopover setContentViewController:self.informationHost.viewController];

    if (infoType != kBPFormulaInfoTypeGeneral) {
        if (cask) {
            [self.informationHost receiveInformation:nil website:nil
                name:name cask:cask infoType:infoType generation:generation];
            return;
        }
        BOOL onlyInstalled = (infoType == kBPFormulaInfoTypeInstalledDependents);
        NSString *(^provider)(NSString *, BOOL) = self.dependentsProvider;
        __weak typeof(self) weakSelf = self;
        [self.timedDispatch scheduleDispatchAfterTimeInterval:0.0
            inQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0) ofBlock:^{
            NSString *dependents = provider
                ? provider(name, onlyInstalled)
                : [[BPHomebrewInterface sharedInterface] dependantsForFormulaName:name onlyInstalled:onlyInstalled];
            NSString *copiedDependents = [dependents copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.informationHost receiveInformation:copiedDependents website:nil
                    name:name cask:cask infoType:infoType generation:generation];
            });
        }];
        return;
    }

    if (formula.information) {
        [self.informationHost receiveInformation:[formula.information copy] website:[formula.website copy]
            name:name cask:cask infoType:infoType generation:generation];
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
                name:name cask:cask infoType:infoType generation:generation];
        });
    }];
}

- (NSString *)nibName
{
    return @"BPFormulaPopoverView";
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
