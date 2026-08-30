//
//  BPEmptyStateView.m
//  Cakebrew
//

#import "BPEmptyStateView.h"

/// Tag so an existing view can be found and replaced without keeping a
/// reference on every caller.
static const NSInteger kBPEmptyStateViewTag = 0x43424553;

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

	BPEmptyStateView *view = [[BPEmptyStateView alloc] initWithFrame:container.bounds];
	view.translatesAutoresizingMaskIntoConstraints = NO;

	NSImageView *symbol = [[NSImageView alloc] init];
	symbol.image = [NSImage imageWithSystemSymbolName:state.symbolName accessibilityDescription:nil];
	symbol.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:38
																				weight:NSFontWeightRegular];
	symbol.contentTintColor = [NSColor tertiaryLabelColor];
	symbol.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *title = [NSTextField labelWithString:NSLocalizedString(state.titleKey, nil)];
	title.font = [NSFont systemFontOfSize:[NSFont systemFontSize] + 3 weight:NSFontWeightSemibold];
	title.textColor = [NSColor secondaryLabelColor];
	title.alignment = NSTextAlignmentCenter;
	title.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *message = [NSTextField wrappingLabelWithString:NSLocalizedString(state.messageKey, nil)];
	message.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	message.textColor = [NSColor tertiaryLabelColor];
	message.alignment = NSTextAlignmentCenter;
	message.selectable = NO;
	message.translatesAutoresizingMaskIntoConstraints = NO;

	NSStackView *stack = [NSStackView stackViewWithViews:@[symbol, title, message]];
	stack.orientation = NSUserInterfaceLayoutOrientationVertical;
	stack.alignment = NSLayoutAttributeCenterX;
	stack.spacing = 8;
	stack.translatesAutoresizingMaskIntoConstraints = NO;

	[view addSubview:stack];
	[container addSubview:view];

	// One announcement rather than three labels read separately.
	view.accessibilityElement = YES;
	view.accessibilityRole = NSAccessibilityStaticTextRole;
	view.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", title.stringValue, message.stringValue];

	[NSLayoutConstraint activateConstraints:@[
		[view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
		[view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
		[view.topAnchor constraintEqualToAnchor:container.topAnchor],
		[view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

		[stack.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
		[stack.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
		[stack.widthAnchor constraintLessThanOrEqualToConstant:320],
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
