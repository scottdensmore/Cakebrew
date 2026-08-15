//
//  BPAutoScrollTextView.h
//  Cakebrew
//
//  Created by Bruno Philipe on 6/17/14.
//  Copyright (c) 2014 Bruno Philipe. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/**
 *  A text view for live command output: appends at the tail and follows it.
 *
 *  Callers used to rebuild the whole document per chunk (`setString:` with the
 *  running transcript), which is quadratic, blocks the producer on the main
 *  thread, and resets VoiceOver's review cursor to the top on every update.
 */
@interface BPAutoScrollTextView : NSTextView

/**
 *  Appends a chunk of output and scrolls to follow it.
 *
 *  Safe to call from any thread — chunks are buffered in arrival order and
 *  applied to the text storage as one edit on the main queue, so a chatty
 *  install costs one edit per flush rather than one per chunk. Nil and empty
 *  chunks are ignored.
 */
- (void)appendOutput:(nullable NSString *)chunk;

/// Empties the view and discards anything buffered but not yet applied.
- (void)clearOutput;

/// Applies buffered output immediately. Called automatically on the main queue.
- (void)flushPendingOutput;

/// Longest transcript kept, in characters; older text is trimmed from the top.
+ (NSUInteger)maximumScrollbackLength;

@end

NS_ASSUME_NONNULL_END
