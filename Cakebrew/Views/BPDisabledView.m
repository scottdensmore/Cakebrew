//
//  BPDisabledView.m
//
//
//  Created by Marek Hrusovsky on 26/08/15.
//
//

#import "BPDisabledView.h"
#import "BPFormulaInformation-Swift.h"

@interface BPDisabledView()

@property (strong) IBOutlet NSView *view;
@property (weak) IBOutlet NSTextField *titleField;
@property (weak) IBOutlet NSTextField *messageField;
@property (weak) IBOutlet NSButton *retryButton;
@property (weak) IBOutlet NSButton *installButton;
@property (strong, nonatomic) BPDisabledHost *disabledHost;
@property (assign, nonatomic) BOOL retryEnabled;

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
	self.retryEnabled = YES;
	self.disabledHost = [[BPDisabledHost alloc] init];
	__weak typeof(self) weakSelf = self;
	self.disabledHost.onRetry = ^{
		[weakSelf retry:nil];
	};
	self.disabledHost.onOpenInstructions = ^{
		[weakSelf openInstallationInstructions:nil];
	};

	NSView *hostView = self.disabledHost.viewController.view;
	hostView.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:hostView];
	self.view = hostView;

	[self addConstraint:[self pin:hostView attribute:NSLayoutAttributeTop]];
	[self addConstraint:[self pin:hostView attribute:NSLayoutAttributeLeft]];
	[self addConstraint:[self pin:hostView attribute:NSLayoutAttributeBottom]];
	[self addConstraint:[self pin:hostView attribute:NSLayoutAttributeRight]];
}

- (void)showDiscoveryResult:(BPHomebrewDiscoveryResult)result checking:(BOOL)checking
{
	self.retryEnabled = !checking;
	self.retryButton.enabled = !checking;
	NSString *title = @"";
	NSString *message = @"";
	if (checking) {
		title = NSLocalizedString(@"Checking for Homebrew…", nil);
		message = NSLocalizedString(@"Checking your login shell for Homebrew. This may take a moment.", nil);
	} else {
		switch (result) {
			case BPHomebrewDiscoveryMissing:
				title = NSLocalizedString(@"Homebrew wasn’t found", nil);
				message = NSLocalizedString(@"Cakebrew couldn’t find Homebrew in your login shell’s PATH. Open brew.sh for installation instructions, or fix your shell configuration, then choose Try Again.", nil);
				break;
			case BPHomebrewDiscoveryInvalidShell:
				title = NSLocalizedString(@"Your login shell is unavailable", nil);
				message = NSLocalizedString(@"Cakebrew needs an executable login shell listed in /etc/shells. Check your shell configuration, then choose Try Again. Homebrew installation instructions are available at brew.sh.", nil);
				break;
			default:
				title = NSLocalizedString(@"Homebrew couldn’t be checked", nil);
				message = NSLocalizedString(@"Your login shell didn’t return a usable Homebrew executable. Check its startup configuration and PATH, then choose Try Again. Installation instructions are available at brew.sh.", nil);
				break;
		}
	}
	self.titleField.stringValue = title;
	self.messageField.stringValue = message;
	[self.disabledHost updateWithTitle:title
							   message:message
						  retryEnabled:!checking
							  checking:checking];
}

- (IBAction)retry:(id)sender
{
	if (self.retryEnabled && self.retryHandler) self.retryHandler();
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
