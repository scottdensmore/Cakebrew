//
//  BPSelectedFormulaViewController.m
//  Cakebrew
//
//  Created by Marek Hrusovsky on 05/09/14.
//  Copyright (c) 2014 Bruno Philipe. All rights reserved.
//

#import "BPSelectedFormulaViewController.h"
#import "BPTimedDispatch.h"
#import "BPHomebrewInterface.h"
#import "BPHomebrewManager.h"
#import "BPFormulaInformation-Swift.h"

@interface BPSelectedFormulaViewController ()

@property (strong) BPTimedDispatch *timedDispatch;
@property (strong, nonatomic, readwrite) BPSelectedFormulaHost *inspectorHost;

@end

@implementation BPSelectedFormulaViewController

- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
	self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
	if (self) {
		_timedDispatch = [BPTimedDispatch new];
		_inspectorHost = [BPSelectedFormulaHost new];
		[self configureInspectorHostCallbacks];
	}
	return self;
}

- (void)configureInspectorHostCallbacks
{
	if (!self.inspectorHost) return;
	__weak typeof(self) weakSelf = self;
	if ([self.inspectorHost respondsToSelector:@selector(setOnSelectRelatedPackage:)]) {
		self.inspectorHost.onSelectRelatedPackage = ^(NSString *packageName) {
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (!strongSelf || packageName.length == 0) return;
			if ([strongSelf.delegate respondsToSelector:@selector(selectedFormulaViewDidRequestSelectRelatedFormulaNamed:)]) {
				[strongSelf.delegate selectedFormulaViewDidRequestSelectRelatedFormulaNamed:packageName];
			}
		};
	}
	if ([self.inspectorHost respondsToSelector:@selector(setOnShowMoreInfo:)]) {
		self.inspectorHost.onShowMoreInfo = ^{
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (!strongSelf) return;
			if ([strongSelf.delegate respondsToSelector:@selector(selectedFormulaViewDidRequestShowMoreInformation)]) {
				[strongSelf.delegate selectedFormulaViewDidRequestShowMoreInformation];
			}
		};
	}
	if ([self.inspectorHost respondsToSelector:@selector(setOnOpenWebsite:)]) {
		self.inspectorHost.onOpenWebsite = ^{
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (!strongSelf) return;
			if ([strongSelf.delegate respondsToSelector:@selector(selectedFormulaViewDidRequestOpenWebsite)]) {
				[strongSelf.delegate selectedFormulaViewDidRequestOpenWebsite];
			}
		};
	}
}

- (void)loadView
{
	if (!self.timedDispatch) {
		self.timedDispatch = [BPTimedDispatch new];
	}
	if (!self.inspectorHost) {
		self.inspectorHost = [BPSelectedFormulaHost new];
		[self configureInspectorHostCallbacks];
	}
	[self configureInspectorHostCallbacks];
	self.view = self.inspectorHost.viewController.view;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setFormulae:(NSArray *)formulae
{
	for (BPFormula *formula in _formulae) {
		[[NSNotificationCenter defaultCenter] removeObserver:self
														name:BPFormulaDidUpdateNotification
													  object:formula];
	}
	_formulae = [formulae copy];
	for (BPFormula *formula in _formulae) {
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(updateFormulaInformation:)
													 name:BPFormulaDidUpdateNotification
												   object:formula];
	}

	if (!self.inspectorHost) {
		self.inspectorHost = [BPSelectedFormulaHost new];
		[self configureInspectorHostCallbacks];
	}
	if (!self.timedDispatch) {
		self.timedDispatch = [BPTimedDispatch new];
	}

	if (!_formulae || [_formulae count] == 0) {
		[self.inspectorHost clearSelection];
		return;
	}

	if ([_formulae count] > 1) {
		[self.inspectorHost showMultipleSelection];
		return;
	}

	BPFormula *formula = [_formulae firstObject];
	NSString *name = [formula.name copy] ?: @"";
	BOOL cask = formula.cask;
	BOOL pinned = !cask && [[BPHomebrewManager sharedManager] isFormulaPinned:formula];
	uint64_t generation = [self.inspectorHost beginSelectionWithName:name
																cask:cask
														   installed:formula.isInstalled
															  pinned:pinned
														 installPath:[formula.installPath copy]
													   latestVersion:[formula.latestVersion copy]
														dependencies:[formula.dependencies copy]
														   conflicts:[formula.conflicts copy]
													shortDescription:[formula.shortDescription copy]];

	if ([self.delegate respondsToSelector:@selector(selectedFormulaViewDidUpdateFormulaInfoForFormula:)]) {
		[self.delegate selectedFormulaViewDidUpdateFormulaInfoForFormula:formula];
	}

	NSString *(^provider)(NSString *, BOOL) = self.dependentsProvider;
	__weak typeof(self) weakSelf = self;
	[self.timedDispatch scheduleDispatchAfterTimeInterval:0.3
												  inQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)
												  ofBlock:^{
		[formula setNeedsInformation:YES];
		if (cask) {
			return;
		}
		NSString *raw = provider
			? provider(name, YES)
			: [[BPHomebrewInterface sharedInterface] dependantsForFormulaName:name onlyInstalled:YES];
		NSArray<NSString *> *dependents = [BPFormula namesFromListOutput:raw] ?: @[];
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf.inspectorHost receiveDependents:dependents
												 name:name
												 cask:cask
										   generation:generation];
		});
	}];
}

- (void)updateFormulaInformation:(NSNotification *)notification
{
	BPFormula *updatedFormula = [notification.object isKindOfClass:[BPFormula class]] ? notification.object : nil;
	dispatch_async(dispatch_get_main_queue(), ^{
		if ([self.formulae count] != 1) {
			return;
		}
		BPFormula *formula = [self.formulae firstObject];
		if (updatedFormula && (updatedFormula.cask != formula.cask || ![updatedFormula.name isEqualToString:formula.name])) {
			return;
		}
		BOOL pinned = !formula.cask && [[BPHomebrewManager sharedManager] isFormulaPinned:formula];
		[self.inspectorHost updateSelectionWithName:formula.name ?: @""
											   cask:formula.cask
										  installed:formula.isInstalled
											 pinned:pinned
										installPath:[formula.installPath copy]
									  latestVersion:[formula.latestVersion copy]
									   dependencies:[formula.dependencies copy]
										  conflicts:[formula.conflicts copy]
								   shortDescription:[formula.shortDescription copy]];
		if ([self.delegate respondsToSelector:@selector(selectedFormulaViewDidUpdateFormulaInfoForFormula:)]) {
			[self.delegate selectedFormulaViewDidUpdateFormulaInfoForFormula:formula];
		}
	});
}

@end
