//
//  BPAutoScrollTextViewTests.m
//  CakebrewTests
//
//  The three streaming log views (install/upgrade, Update, Doctor) each
//  replaced the text view's whole document on every chunk: quadratic in
//  transcript length, all on the main thread, and it threw VoiceOver's review
//  cursor back to the top on every update. Doctor was worse — it captured the
//  "previous" string *after* clearing the view, so every chunk overwrote the
//  last and all but the final chunk of `brew doctor` was lost.
//
//  Appending is now the view's job, so these tests pin the behaviour the three
//  controllers depend on.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>
#import "BPAutoScrollTextView.h"

@interface BPAutoScrollTextViewTests : XCTestCase
@end

@implementation BPAutoScrollTextViewTests
{
	BPAutoScrollTextView *_textView;
}

- (void)setUp
{
	[super setUp];
	_textView = [[BPAutoScrollTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
}

- (void)tearDown
{
	_textView = nil;
	[super tearDown];
}

#pragma mark - accumulation

- (void)testStreamedTextRetainsSemanticForegroundColorAfterClearAndReappend
{
	// Setting NSTextView.textColor on an empty view is not enough: direct plain
	// textStorage insertion can discard its typing attributes (the import case).
	_textView.textColor = NSColor.textColor;
	for (NSUInteger cycle = 0; cycle < 2; cycle++)
	{
		[_textView clearOutput];
		[_textView appendOutput:@"first "];
		[_textView appendOutput:@"second"];
		[_textView flushPendingOutput];
		[_textView.textStorage enumerateAttribute:NSForegroundColorAttributeName
			inRange:NSMakeRange(0, _textView.textStorage.length) options:0
			usingBlock:^(NSColor *color, NSRange range, BOOL *stop) {
				XCTAssertEqualObjects(color, NSColor.textColor,
					@"every streamed character needs an appearance-adaptive foreground");
				__block CGFloat light = 0, dark = 0;
				[[NSAppearance appearanceNamed:NSAppearanceNameAqua] performAsCurrentDrawingAppearance:^{
					light = [color colorUsingColorSpace:NSColorSpace.genericRGBColorSpace].redComponent;
				}];
				[[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] performAsCurrentDrawingAppearance:^{
					dark = [color colorUsingColorSpace:NSColorSpace.genericRGBColorSpace].redComponent;
				}];
				XCTAssertGreaterThan(dark, light, @"the stored color must adapt when appearance changes");
			}];
	}
}

- (void)testChunksAccumulateInOrder
{
	[_textView appendOutput:@"one "];
	[_textView appendOutput:@"two "];
	[_textView appendOutput:@"three"];
	[_textView flushPendingOutput];

	XCTAssertEqualObjects(_textView.string, @"one two three");
}

- (void)testManyChunksAreAllPresentAndOrdered
{
	// The Doctor regression in miniature: before the fix only the last chunk
	// survived, so this is the shape that matters.
	NSMutableString *expected = [NSMutableString string];
	for (NSUInteger i = 0; i < 500; i++)
	{
		NSString *chunk = [NSString stringWithFormat:@"line-%lu\n", (unsigned long)i];
		[expected appendString:chunk];
		[_textView appendOutput:chunk];
	}
	[_textView flushPendingOutput];

	XCTAssertEqualObjects(_textView.string, expected, @"chunks were dropped or reordered");
}

- (void)testAppendingDoesNotDiscardTextAlreadyInTheView
{
	_textView.string = @"header\n";
	[_textView appendOutput:@"streamed"];
	[_textView flushPendingOutput];

	XCTAssertEqualObjects(_textView.string, @"header\nstreamed");
}

- (void)testClearingResetsTheBufferToo
{
	[_textView appendOutput:@"stale"];
	[_textView clearOutput];
	[_textView appendOutput:@"fresh"];
	[_textView flushPendingOutput];

	XCTAssertEqualObjects(_textView.string, @"fresh",
						  @"a chunk buffered before the clear must not reappear after it");
}

- (void)testEmptyAndNilChunksAreIgnored
{
	[_textView appendOutput:@"kept"];
	[_textView appendOutput:@""];
	[_textView appendOutput:nil];
	[_textView flushPendingOutput];

	XCTAssertEqualObjects(_textView.string, @"kept");
}

#pragma mark - coalescing

- (void)testBufferedChunksAreAppliedInASingleEdit
{
	// Coalescing is the point: one textStorage edit per flush, not one per
	// chunk, so a chatty install doesn't hammer the main thread.
	__block NSUInteger edits = 0;
	id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSTextDidChangeNotification
																	object:_textView
																	 queue:nil
																usingBlock:^(NSNotification *note) { edits++; }];

	for (NSUInteger i = 0; i < 50; i++)
	{
		[_textView appendOutput:@"x"];
	}
	[_textView flushPendingOutput];
	[[NSNotificationCenter defaultCenter] removeObserver:observer];

	XCTAssertEqualObjects(_textView.string, [@"" stringByPaddingToLength:50 withString:@"x" startingAtIndex:0]);
	XCTAssertLessThanOrEqual(edits, 1u, @"each chunk caused its own edit instead of being coalesced");
}

- (void)testFlushingWithNothingBufferedIsHarmless
{
	[_textView flushPendingOutput];
	[_textView flushPendingOutput];
	XCTAssertEqualObjects(_textView.string, @"");
}

#pragma mark - bounded scrollback

- (void)testScrollbackIsCappedSoALongRunCannotGrowUnbounded
{
	NSString *line = [[@"" stringByPaddingToLength:99 withString:@"y" startingAtIndex:0] stringByAppendingString:@"\n"];
	for (NSUInteger i = 0; i < 40000; i++)   // 4 MB
	{
		[_textView appendOutput:line];
	}
	[_textView flushPendingOutput];

	XCTAssertLessThanOrEqual(_textView.string.length, [BPAutoScrollTextView maximumScrollbackLength],
							 @"transcript grew past the cap");
	XCTAssertGreaterThan(_textView.string.length, 0u);
	XCTAssertTrue([_textView.string hasSuffix:line], @"the tail — the part the user is watching — must survive");
}

#pragma mark - threading

- (void)testAppendingFromABackgroundThreadIsSafeAndOrderPreserving
{
	// Chunks arrive on BPTask's delivery queue, never the main thread.
	dispatch_queue_t producer = dispatch_queue_create("test.producer", DISPATCH_QUEUE_SERIAL);
	NSMutableString *expected = [NSMutableString string];
	for (NSUInteger i = 0; i < 200; i++)
	{
		NSString *chunk = [NSString stringWithFormat:@"%lu,", (unsigned long)i];
		[expected appendString:chunk];
		dispatch_async(producer, ^{ [self->_textView appendOutput:chunk]; });
	}
	dispatch_sync(producer, ^{});
	[_textView flushPendingOutput];

	XCTAssertEqualObjects(_textView.string, expected);
}

@end
