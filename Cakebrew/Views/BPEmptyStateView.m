//
//  BPEmptyStateView.m
//  Cakebrew
//

#import "BPEmptyStateView.h"
#import "BPFormulaInformation-Swift.h"

/// Tag so an existing view can be found and replaced without keeping a
/// reference on every caller.
static const NSInteger kBPEmptyStateViewTag = 0x43424553;

@interface BPEmptyStateView ()
@property (strong, nonatomic) BPEmptyStateHost *host;
@end

@implementation BPEmptyStateView

+ (void)presentState:(BPEmptyState *)state overView:(NSView *)container
{
	for (NSView *subview in [container.subviews copy])
	{
		if (subview.tag == kBPEmptyStateViewTag)
		{
			[subview removeFromSuperview];
		}
	}

	if (!state || !container)
	{
		return;
	}

	NSString *title = NSLocalizedString(state.titleKey, nil);
	NSString *message = NSLocalizedString(state.messageKey, nil);

	BPEmptyStateView *view = [[BPEmptyStateView alloc] initWithFrame:container.bounds];
	view.translatesAutoresizingMaskIntoConstraints = NO;
	view.host = [[BPEmptyStateHost alloc] initWithSymbolName:state.symbolName ?: @"tray"
													   title:title ?: @""
													 message:message ?: @""];

	NSView *hostView = view.host.viewController.view;
	hostView.translatesAutoresizingMaskIntoConstraints = NO;
	[view addSubview:hostView];
	[container addSubview:view];

	// One announcement rather than three labels read separately.
	view.accessibilityElement = YES;
	view.accessibilityRole = NSAccessibilityStaticTextRole;
	view.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", title, message];

	[NSLayoutConstraint activateConstraints:@[
		[view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
		[view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
		[view.topAnchor constraintEqualToAnchor:container.topAnchor],
		[view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

		[hostView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
		[hostView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
		[hostView.topAnchor constraintEqualToAnchor:view.topAnchor],
		[hostView.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
	]];
}

- (NSInteger)tag
{
	return kBPEmptyStateViewTag;
}

/// Transparent: the table's own background shows through, so this adapts to
/// appearance without painting anything of its own.
- (BOOL)isOpaque
{
	return NO;
}

@end
