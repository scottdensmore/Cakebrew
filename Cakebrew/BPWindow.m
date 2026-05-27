//
//  BPWindow.m
//  Cakebrew
//
//  Created by Bruno on 06.02.21.
//  Copyright © 2021 Bruno Philipe. All rights reserved.
//

#import "BPWindow.h"

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
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if ([menuItem action] == @selector(runToolbarCustomizationPalette:)) {
		return NO;
	}

	return [super validateMenuItem:menuItem];
}

@end
