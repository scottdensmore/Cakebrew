//
//  BPAutoScrollTextView.m
//  Cakebrew
//
//  Created by Bruno Philipe on 6/17/14.
//  Copyright (c) 2014 Bruno Philipe. All rights reserved.
//

#import "BPAutoScrollTextView.h"

/// ~2 MB of transcript. A long `brew upgrade` can print far more than anyone
/// will scroll back through, and an unbounded text storage is a slow leak.
static const NSUInteger kMaximumScrollbackLength = 2 * 1024 * 1024;

/// Trim well past the cap so trimming is rare rather than once per flush.
static const NSUInteger kTrimTargetLength = (NSUInteger)(1.5 * 1024 * 1024);

@implementation BPAutoScrollTextView
{
	NSMutableString *_pending;      // chunks not yet applied; guarded by _lock
	BOOL _flushScheduled;           // guarded by _lock
	NSLock *_lock;
}

+ (NSUInteger)maximumScrollbackLength
{
	return kMaximumScrollbackLength;
}

- (void)commonInit
{
	_pending = [NSMutableString string];
	_lock = [[NSLock alloc] init];
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self)
	{
		[self commonInit];
	}
	return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect textContainer:(NSTextContainer *)container
{
	self = [super initWithFrame:frameRect textContainer:container];
	if (self)
	{
		[self commonInit];
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if (self)
	{
		[self commonInit];
	}
	return self;
}

- (void)setString:(NSString *)string
{
	[super setString:string];
	[self scrollToEndOfDocument:self];
}

#pragma mark - Streaming output

- (void)appendOutput:(NSString *)chunk
{
	if (chunk.length == 0)
	{
		return;
	}

	BOOL needsFlush = NO;

	[_lock lock];
	[_pending appendString:chunk];
	if (!_flushScheduled)
	{
		_flushScheduled = YES;
		needsFlush = YES;
	}
	[_lock unlock];

	if (!needsFlush)
	{
		// A flush is already queued; it will pick this chunk up too.
		return;
	}

	if ([NSThread isMainThread])
	{
		[self flushPendingOutput];
	}
	else
	{
		// Async, never waitUntilDone: blocking the producer on the main thread
		// is what stalled draining the pipe.
		dispatch_async(dispatch_get_main_queue(), ^{
			[self flushPendingOutput];
		});
	}
}

- (void)clearOutput
{
	[_lock lock];
	[_pending setString:@""];
	[_lock unlock];

	self.string = @"";
}

- (void)flushPendingOutput
{
	[_lock lock];
	NSString *chunk = [_pending copy];
	[_pending setString:@""];
	_flushScheduled = NO;
	[_lock unlock];

	if (chunk.length == 0)
	{
		return;
	}

	NSTextStorage *storage = self.textStorage;
	[storage beginEditing];
	[storage replaceCharactersInRange:NSMakeRange(storage.length, 0) withString:chunk];
	[self trimScrollbackInStorage:storage];
	[storage endEditing];

	[self scrollRangeToVisible:NSMakeRange(self.textStorage.length, 0)];
}

/// Drops the oldest text once the transcript passes the cap. Must be called
/// inside the storage's editing transaction.
- (void)trimScrollbackInStorage:(NSTextStorage *)storage
{
	if (storage.length <= kMaximumScrollbackLength)
	{
		return;
	}

	NSUInteger excess = storage.length - kTrimTargetLength;

	// Cut at a line boundary so the top of the view isn't a partial line.
	NSRange newline = [storage.string rangeOfString:@"\n"
											options:0
											  range:NSMakeRange(excess, MIN(4096u, storage.length - excess))];
	if (newline.location != NSNotFound)
	{
		excess = NSMaxRange(newline);
	}

	[storage replaceCharactersInRange:NSMakeRange(0, excess) withString:@""];
}

@end
