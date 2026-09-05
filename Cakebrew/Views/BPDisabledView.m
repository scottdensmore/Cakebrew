//
//  BPDisabledView.m
//
//
//  Created by Marek Hrusovsky on 26/08/15.
//
//

#import "BPDisabledView.h"

@interface BPDisabledView()

@property (strong) IBOutlet NSView *view;
@property (weak) IBOutlet NSTextField *titleField;
@property (weak) IBOutlet NSTextField *messageField;
@property (weak) IBOutlet NSButton *retryButton;
@property (weak) IBOutlet NSButton *installButton;

@end


@implementation BPDisabledView

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
	NSNib *nib = [[NSNib alloc] initWithNibNamed:@"Disabled" bundle:nil];
	[nib instantiateWithOwner:self topLevelObjects:NULL];
	[self addSubview:self.view];
	
	self.view.translatesAutoresizingMaskIntoConstraints = NO;
	
	[self addConstraint:[self pin:self.view attribute:NSLayoutAttributeTop]];
	[self addConstraint:[self pin:self.view attribute:NSLayoutAttributeLeft]];
	[self addConstraint:[self pin:self.view attribute:NSLayoutAttributeBottom]];
	[self addConstraint:[self pin:self.view attribute:NSLayoutAttributeRight]];
	self.titleField.accessibilityIdentifier = @"homebrew.recovery.title";
	self.messageField.accessibilityIdentifier = @"homebrew.recovery.message";
	self.retryButton.accessibilityIdentifier = @"homebrew.retry";
	self.installButton.accessibilityIdentifier = @"homebrew.install";
	self.retryButton.title = NSLocalizedString(@"Try Again", nil);
	self.installButton.title = NSLocalizedString(@"Open brew.sh", nil);
}

- (void)showDiscoveryResult:(BPHomebrewDiscoveryResult)result checking:(BOOL)checking
{
	self.retryButton.enabled = !checking;
	if (checking) {
		self.titleField.stringValue = NSLocalizedString(@"Checking for Homebrew…", nil);
		self.messageField.stringValue = NSLocalizedString(@"Checking your login shell for Homebrew. This may take a moment.", nil);
		return;
	}
	switch (result) {
		case BPHomebrewDiscoveryMissing:
			self.titleField.stringValue = NSLocalizedString(@"Homebrew wasn’t found", nil);
			self.messageField.stringValue = NSLocalizedString(@"Cakebrew couldn’t find Homebrew in your login shell’s PATH. Open brew.sh for installation instructions, or fix your shell configuration, then choose Try Again.", nil);
			break;
		case BPHomebrewDiscoveryInvalidShell:
			self.titleField.stringValue = NSLocalizedString(@"Your login shell is unavailable", nil);
			self.messageField.stringValue = NSLocalizedString(@"Cakebrew needs an executable login shell listed in /etc/shells. Check your shell configuration, then choose Try Again. Homebrew installation instructions are available at brew.sh.", nil);
			break;
		default:
			self.titleField.stringValue = NSLocalizedString(@"Homebrew couldn’t be checked", nil);
			self.messageField.stringValue = NSLocalizedString(@"Your login shell didn’t return a usable Homebrew executable. Check its startup configuration and PATH, then choose Try Again. Installation instructions are available at brew.sh.", nil);
			break;
	}
}

- (IBAction)retry:(id)sender
{
	if (self.retryButton.enabled && self.retryHandler) self.retryHandler();
}

- (IBAction)openInstallationInstructions:(id)sender
{
	[NSWorkspace.sharedWorkspace openURL:BPHomebrewInterface.installationURL];
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
