//
//  BPBackgroundUpdater.m
//  Cakebrew
//
//	This program is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//
//	This program is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with this program.	If not, see <http://www.gnu.org/licenses/>.
//

#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>
#import "BPBackgroundUpdater.h"
#import "BPHomebrewManager.h"
#import "BPPreferences.h"
#import "BPAppDelegate.h"

static void *BPBackgroundUpdaterContext = &BPBackgroundUpdaterContext;

static NSString *const kBPLastNotifiedOutdatedCountKey = @"BPLastNotifiedOutdatedCount";

@interface BPBackgroundUpdater ()

@property (strong) NSTimer *timer;
@property (assign) NSUInteger lastKnownOutdatedCount;
@property (assign) NSTimeInterval scheduledInterval;

@end

@implementation BPBackgroundUpdater

+ (NSString *)badgeLabelForOutdatedCount:(NSUInteger)count
{
	return count == 0 ? nil : [NSString stringWithFormat:@"%lu", (unsigned long)count];
}

+ (BOOL)shouldNotifyForCount:(NSUInteger)count previousCount:(NSUInteger)previousCount
{
	return count > previousCount;
}

+ (BOOL)shouldNotifyForCount:(NSUInteger)count
			   previousCount:(NSUInteger)previousCount
				 hasBaseline:(BOOL)hasBaseline
{
	if (!hasBaseline)
	{
		return NO;
	}
	return [self shouldNotifyForCount:count previousCount:previousCount];
}

+ (NSUInteger)persistedOutdatedCount
{
	return (NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:kBPLastNotifiedOutdatedCountKey];
}

+ (void)setPersistedOutdatedCount:(NSUInteger)count
{
	[[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)count forKey:kBPLastNotifiedOutdatedCountKey];
}

+ (BOOL)hasPersistedOutdatedCount
{
	return [[NSUserDefaults standardUserDefaults] objectForKey:kBPLastNotifiedOutdatedCountKey] != nil;
}

+ (void)clearPersistedOutdatedCount
{
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:kBPLastNotifiedOutdatedCountKey];
}

- (void)start
{
	BPHomebrewManager *manager = [BPHomebrewManager sharedManager];
	[manager addObserver:self forKeyPath:NSStringFromSelector(@selector(outdatedFormulae))
				 options:0 context:BPBackgroundUpdaterContext];
	[manager addObserver:self forKeyPath:NSStringFromSelector(@selector(outdatedCasks))
				 options:0 context:BPBackgroundUpdaterContext];

	// Reschedule when the user changes the settings.
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(scheduleTimer)
												 name:NSUserDefaultsDidChangeNotification
											   object:nil];
	[self scheduleTimer];
}

- (void)dealloc
{
	BPHomebrewManager *manager = [BPHomebrewManager sharedManager];
	[manager removeObserver:self forKeyPath:NSStringFromSelector(@selector(outdatedFormulae)) context:BPBackgroundUpdaterContext];
	[manager removeObserver:self forKeyPath:NSStringFromSelector(@selector(outdatedCasks)) context:BPBackgroundUpdaterContext];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[self.timer invalidate];
}

#pragma mark - Timer

- (void)scheduleTimer
{
	BOOL enabled = [BPPreferences backgroundCheckEnabled];
	NSTimeInterval interval = MAX([BPPreferences backgroundCheckInterval], 3600.0);

	if (!enabled)
	{
		[self.timer invalidate];
		self.timer = nil;
		self.scheduledInterval = 0;
		return;
	}

	if (self.timer && self.scheduledInterval == interval)
	{
		return; // unrelated defaults change; keep the existing schedule
	}

	[self.timer invalidate];
	self.timer = [NSTimer scheduledTimerWithTimeInterval:interval
												  target:self
												selector:@selector(timerFired:)
												userInfo:nil
												 repeats:YES];
	self.timer.tolerance = interval * 0.1;
	self.scheduledInterval = interval;
}

- (void)timerFired:(NSTimer *)timer
{
	// Don't refresh under a running operation; the app reloads afterwards anyway.
	if ([BPAppDelegateRef isRunningBackgroundTask])
	{
		return;
	}
	[[BPHomebrewManager sharedManager] reloadFromInterfaceRebuildingCache:NO];
}

#pragma mark - Outdated count

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context != BPBackgroundUpdaterContext)
	{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
		return;
	}

	// One reload sets outdatedFormulae and outdatedCasks separately, so this
	// fires twice: once summing the new formulae with the *old* cask count, and
	// again with the true total — two banners with different numbers. Coalesce
	// to the end of the run-loop turn so a reload yields at most one.
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(outdatedCountDidSettle)
											   object:nil];
	[self performSelector:@selector(outdatedCountDidSettle) withObject:nil afterDelay:0];
}

- (void)outdatedCountDidSettle
{
	BPHomebrewManager *manager = [BPHomebrewManager sharedManager];
	NSUInteger count = manager.outdatedFormulae.count + manager.outdatedCasks.count;

	// The badge reflects every reload, whether or not it is news.
	[[[NSApplication sharedApplication] dockTile] setBadgeLabel:[BPBackgroundUpdater badgeLabelForOutdatedCount:count]];

	BOOL hasBaseline = [BPBackgroundUpdater hasPersistedOutdatedCount];
	NSUInteger previous = [BPBackgroundUpdater persistedOutdatedCount];
	[BPBackgroundUpdater setPersistedOutdatedCount:count];
	self.lastKnownOutdatedCount = count;

	if ([BPBackgroundUpdater shouldNotifyForCount:count previousCount:previous hasBaseline:hasBaseline])
	{
		[self postOutdatedNotificationWithCount:count];
	}
}

- (void)postOutdatedNotificationWithCount:(NSUInteger)count
{
	// Asked here rather than at launch, so the system prompt arrives with an
	// actual reason: the app has found updates and wants to tell you.
	UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
	[center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
						  completionHandler:^(BOOL granted, NSError *error) {
		if (error)
		{
			NSLog(@"Error requesting notification permissions: %@", error);
		}
		if (granted)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self deliverOutdatedNotificationWithCount:count];
			});
		}
	}];
}

- (void)deliverOutdatedNotificationWithCount:(NSUInteger)count
{
	UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
	content.title = NSLocalizedString(@"Background_Update_Notification_Title", nil);
	content.body = [NSString stringWithFormat:NSLocalizedString(@"Background_Update_Notification_Body", nil),
					(unsigned long)count];

	UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString]
																		  content:content
																		  trigger:nil];
	[[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
}

@end
