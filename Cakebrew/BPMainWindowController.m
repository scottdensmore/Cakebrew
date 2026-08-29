//
//  BPMainWindowController.m
//  Cakebrew
//
//  Created by Bruno on 06.02.21.
//  Copyright © 2021 Bruno Philipe. All rights reserved.
//

#import "BPMainWindowController.h"
#import "NSLayoutConstraint+Shims.h"

@interface BPMainWindowController ()

@property (strong) NSSplitViewController *splitViewController;

@end

@implementation BPMainWindowController

/**
 *  Forwards the Show/Hide Sidebar action (menu item and toolbar button) to the
 *  split view controller.
 *
 *  The split controller's *view* is a subview of the window's content view
 *  rather than the window's contentViewController, so whether the action
 *  reaches it through the responder chain depends on what currently has focus.
 *  The window controller is always in that chain, so it forwards explicitly.
 */
- (void)toggleSidebar:(id)sender
{
	[self.splitViewController toggleSidebar:sender];
}

- (void)setUpViews
{
	_splitViewController = [[NSSplitViewController alloc] initWithNibName:nil bundle:nil];

	[_splitViewController addSplitViewItem:[self makeSidebarSplitViewItem]];
	[_splitViewController addSplitViewItem:[self makeContentSplitViewItem]];

	NSView *splitControllerView = [[self splitViewController] view];
	NSView *windowContentView = [[self window] contentView];

	NSAssert(splitControllerView, @"View should not be nil");
	NSAssert(windowContentView, @"View should not be nil");

	[splitControllerView setTranslatesAutoresizingMaskIntoConstraints:NO];
	[windowContentView addSubview:splitControllerView];

	[NSLayoutConstraint activate:@[
		[NSLayoutConstraint constraintWithItem:splitControllerView attribute:NSLayoutAttributeLeading
									 relatedBy:NSLayoutRelationEqual toItem:windowContentView
									 attribute:NSLayoutAttributeLeading multiplier:1 constant:0],
		[NSLayoutConstraint constraintWithItem:splitControllerView attribute:NSLayoutAttributeTrailing
									 relatedBy:NSLayoutRelationEqual toItem:windowContentView
									 attribute:NSLayoutAttributeTrailing multiplier:1 constant:0],
		[NSLayoutConstraint constraintWithItem:splitControllerView attribute:NSLayoutAttributeTop
									 relatedBy:NSLayoutRelationEqual toItem:windowContentView
									 attribute:NSLayoutAttributeTop multiplier:1 constant:0],
		[NSLayoutConstraint constraintWithItem:splitControllerView attribute:NSLayoutAttributeBottom
									 relatedBy:NSLayoutRelationEqual toItem:windowContentView
									 attribute:NSLayoutAttributeBottom multiplier:1 constant:0],
	]];
}

- (void)setContentViewHidden:(BOOL)hide
{
	[self.windowContentView setHidden:hide];
}

- (NSSplitViewItem *)makeSidebarSplitViewItem
{
	NSViewController *sidebarViewController = [[NSViewController alloc] initWithNibName:nil bundle:nil];
	[sidebarViewController setView:[self sidebarView]];

	return [NSSplitViewItem sidebarWithViewController:sidebarViewController];
}

- (NSSplitViewItem *)makeContentSplitViewItem
{
	NSViewController *contentViewController = [[NSViewController alloc] initWithNibName:nil bundle:nil];
	[contentViewController setView:[self windowContentView]];
	NSSplitViewItem *sidebarContentViewItem = [NSSplitViewItem splitViewItemWithViewController:contentViewController];

	return sidebarContentViewItem;
}

@end
