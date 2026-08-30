//
//  BPCancelReloadTests.m
//  CakebrewTests
//
//  A reload's cask catalog can take 80+ seconds against real brew cold, with
//  no way to stop it. The obvious home for Cancel — the loading overlay — is
//  the wrong one: since the reload publishes each list as it lands, that
//  overlay comes down after about two seconds, so a button there would be gone
//  for the whole minute worth cancelling. It lives in the toolbar instead,
//  shown only while a reload is running.
//

#import <XCTest/XCTest.h>
#import "BPToolbar.h"
#import "BPHomebrewManager.h"

@interface BPCancelReloadTests : XCTestCase
@end

@implementation BPCancelReloadTests

#pragma mark - When the toolbar offers Cancel

- (void)testCancelIsAbsentWhenNoReloadIsRunning
{
	NSArray<NSString *> *identifiers = [BPToolbar defaultItemIdentifiersShowingCancel:NO];

	XCTAssertFalse([identifiers containsObject:[BPToolbar cancelReloadItemIdentifier]]);
}

- (void)testCancelAppearsExactlyOnceWhileReloading
{
	NSArray<NSString *> *identifiers = [BPToolbar defaultItemIdentifiersShowingCancel:YES];

	NSUInteger count = [identifiers indexesOfObjectsPassingTest:^BOOL(NSString *identifier, NSUInteger idx, BOOL *stop) {
		return [identifier isEqualToString:[BPToolbar cancelReloadItemIdentifier]];
	}].count;

	XCTAssertEqual(count, 1u, @"a second insert would leave a duplicate behind: %@", identifiers);
}

/// Showing Cancel must not disturb anything else. The toolbar is rebuilt from
/// this list, so a dropped identifier silently removes a control.
- (void)testShowingCancelAddsNothingElseAndRemovesNothing
{
	NSArray<NSString *> *without = [BPToolbar defaultItemIdentifiersShowingCancel:NO];
	NSArray<NSString *> *with = [BPToolbar defaultItemIdentifiersShowingCancel:YES];

	XCTAssertEqual(with.count, without.count + 1);

	NSMutableArray *stripped = [with mutableCopy];
	[stripped removeObject:[BPToolbar cancelReloadItemIdentifier]];

	XCTAssertEqualObjects(stripped, without, @"showing Cancel reordered or dropped an item");
}

/// The index the toolbar inserts at has to match where the list says it goes,
/// or the item lands somewhere else and the next removal takes the wrong one.
- (void)testTheInsertionIndexMatchesTheListedPosition
{
	NSArray<NSString *> *with = [BPToolbar defaultItemIdentifiersShowingCancel:YES];

	XCTAssertEqual([with indexOfObject:[BPToolbar cancelReloadItemIdentifier]],
				   [BPToolbar cancelReloadItemIndex]);
}

#pragma mark - What cancelling does

/// Cancelling has to make the in-flight reload silent, or its lists land after
/// the user asked it to stop. Bumping the generation is what does that — the
/// same guard publishing already uses.
- (void)testCancellingAReloadStopsItPublishing
{
	BPHomebrewManager *manager = [BPHomebrewManager sharedManager];
	NSUInteger generation = manager.currentReloadGeneration;

	[manager cancelReload];

	XCTAssertNotEqual(manager.currentReloadGeneration, generation,
					  @"a cancelled reload must not be allowed to publish");
}

@end
