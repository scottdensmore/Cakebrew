//
//  BPWindow.m
//  Cakebrew
//
//  Created by Bruno on 06.02.21.
//  Copyright © 2021 Bruno Philipe. All rights reserved.
//

#import "BPWindow.h"
#import "BPBrewfile.h"
#import "BPAppDelegate.h"

@implementation BPWindow

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backingStoreType defer:(BOOL)flag
{
	self = [super initWithContentRect:contentRect styleMask:style backing:backingStoreType defer:flag];
	if (self) {
		[self sharedInit];
	}
	return self;
}

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backingStoreType defer:(BOOL)flag screen:(nullable NSScreen *)screen
{
	self = [super initWithContentRect:contentRect styleMask:style backing:backingStoreType defer:flag screen:screen];
	if (self) {
		[self sharedInit];
	}
	return self;
}

- (void)sharedInit
{
	NSWindowStyleMask mask = [self styleMask];
	mask |= NSWindowStyleMaskFullSizeContentView;
	[self setStyleMask:mask];

	// Tahoe / Liquid Glass: merge the toolbar into the title bar and let the
	// full-height sidebar's material show through the title bar area.
	self.titlebarAppearsTransparent = YES;
	self.toolbarStyle = NSWindowToolbarStyleUnified;

	// Registered on the window rather than a view: the content view is
	// reparented into a split view controller at setup, so a view-level drop
	// target would cover only part of the window.
	[self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
}

#pragma mark - Dropping a Brewfile

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
	return [self brewfileFromDrag:sender] ? NSDragOperationCopy : NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender
{
	return [self draggingEntered:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
	NSURL *brewfile = [self brewfileFromDrag:sender];

	if (!brewfile)
	{
		return NO;
	}

	[BPAppDelegateRef.brewfileImportTarget importBrewfileAtURL:brewfile];
	return YES;
}

/// The first Brewfile in the drag, or nil. A drag can carry several files; the
/// rest are ignored rather than the whole drop refused.
- (NSURL *)brewfileFromDrag:(id<NSDraggingInfo>)sender
{
	NSArray<NSURL *> *urls = [sender.draggingPasteboard readObjectsForClasses:@[[NSURL class]]
																	  options:@{ NSPasteboardURLReadingFileURLsOnlyKey: @YES }];

	return [BPBrewfile brewfileURLsFrom:urls].firstObject;
}

@end
