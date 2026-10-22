//
//  BPLoadingView.m
//  Cakebrew
//
//  Created by Bruno Philipe on 3/13/15.
//  Copyright (c) 2015 Bruno Philipe. All rights reserved.
//

#import "BPLoadingView.h"
#import "BPFormulaInformation-Swift.h"

@interface BPLoadingView()

@property (strong) IBOutlet NSView *view;
@property (weak) IBOutlet NSProgressIndicator *progressIndicator;
@property (strong, nonatomic) BPLoadingHost *loadingHost;

@end

@implementation BPLoadingView

- (void)awakeFromNib
{
	[self.progressIndicator startAnimation:self];
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self) {
		[self commonInit];
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if (self) {
		[self commonInit];
	}
	return self;
}

- (void)commonInit
{
	self.loadingHost = [[BPLoadingHost alloc] init];
	NSView *hostView = self.loadingHost.viewController.view;
	hostView.frame = self.bounds;
	hostView.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:hostView];
	self.view = hostView;

	[self addConstraint:[self pin:hostView attribute:NSLayoutAttributeTop]];
	[self addConstraint:[self pin:hostView attribute:NSLayoutAttributeLeft]];
	[self addConstraint:[self pin:hostView attribute:NSLayoutAttributeBottom]];
	[self addConstraint:[self pin:hostView attribute:NSLayoutAttributeRight]];
}

- (NSLayoutConstraint *)pin:(id)item attribute:(NSLayoutAttribute)attribute
{
	return [NSLayoutConstraint constraintWithItem:self
										attribute:attribute
										relatedBy:NSLayoutRelationEqual
										   toItem:item
										attribute:attribute
									   multiplier:1.0
										 constant:0.0];
}

@end
