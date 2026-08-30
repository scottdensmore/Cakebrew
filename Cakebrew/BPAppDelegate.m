//
//	AppDelegate.m
//	Cakebrew – The Homebrew GUI App for OS X
//
//	Created by Vincent Saluzzo on 06/12/11.
//	Copyright (c) 2014 Bruno Philipe. All rights reserved.
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

#import "BPHomebrewManager.h"
#import "DCOAboutWindowController.h"
#import "BPAppDelegate.h"
#import "BPPreferences.h"
#import "BPPreferencesWindowController.h"
#import "BPBackgroundUpdater.h"
#import "BPBrewfile.h"
#import <UserNotifications/UserNotifications.h>

NSString *const kBP_HOMEBREW_WEBSITE = @"https://www.cakebrew.com";
NSString *const kBP_CAKEBREW_DOCUMENTATION = @"https://github.com/scottdensmore/Cakebrew#readme";


@interface BPAppDelegate () <UNUserNotificationCenterDelegate>
@property (strong, nonatomic) BPPreferencesWindowController *preferencesWindowController;
@property (strong, nonatomic) BPBackgroundUpdater *backgroundUpdater;

@property (nonatomic, strong) DCOAboutWindowController *aboutWindowController;

/// A Brewfile that arrived before there was a window to import it into.
@property (strong) NSURL *pendingBrewfileURL;

@end

@interface BPAppDelegate (SignalHandler)
- (void)setupSignalHandler;
@end

@implementation BPAppDelegate

- (DCOAboutWindowController *)aboutWindowController
{
	if (!_aboutWindowController){
		_aboutWindowController = [[DCOAboutWindowController alloc] init];
		[_aboutWindowController setAppWebsiteURL:[NSURL URLWithString:kBP_HOMEBREW_WEBSITE]];
	}
	return _aboutWindowController;
}

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[BPPreferences registerDefaults];
	[self setupSignalHandler];

	self.backgroundUpdater = [[BPBackgroundUpdater alloc] init];
	[self.backgroundUpdater start];
	
	[[BPHomebrewManager sharedManager] reloadFromInterfaceRebuildingCache:NO];
	
	// The delegate is needed to route taps, but authorization is deliberately
	// not requested here: at launch the user has done nothing and has no reason
	// to know the app checks for updates in the background. BPBackgroundUpdater
	// asks the first time it actually has an update to report.
	[[UNUserNotificationCenter currentNotificationCenter] setDelegate:self];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
	if (!flag)
	{
		[self.window makeKeyAndOrderFront:self];
	}
	
	[self cleanupTaskAlerts];

	return YES;
}

#pragma mark - Opening Brewfiles

// Reached by double-clicking a Brewfile in Finder, "Open With", `open -a`, and
// dropping one on the Dock icon — all of which arrive here rather than through
// the app's own open panel.
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls
{
	NSURL *brewfile = [BPBrewfile brewfileURLsFrom:urls].firstObject;
	if (!brewfile)
	{
		// Launch Services can hand over anything the user forced open with this
		// app. Saying so beats silently doing nothing.
		[self displayBrewfileNotRecognizedForURLs:urls];
		return;
	}

	// An open can arrive before the first window exists. The import target is
	// set when the view controller comes up, so hold the file until then.
	if (!self.brewfileImportTarget)
	{
		self.pendingBrewfileURL = brewfile;
		return;
	}

	[self.brewfileImportTarget importBrewfileAtURL:brewfile];
}

- (void)setBrewfileImportTarget:(id<BPBrewfileImporting>)brewfileImportTarget
{
	_brewfileImportTarget = brewfileImportTarget;

	NSURL *pending = self.pendingBrewfileURL;

	if (brewfileImportTarget && pending)
	{
		self.pendingBrewfileURL = nil;
		[brewfileImportTarget importBrewfileAtURL:pending];
	}
}

- (void)displayBrewfileNotRecognizedForURLs:(NSArray<NSURL *> *)urls
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:NSLocalizedString(@"Brewfile_Not_Recognized_Title", nil)];
	[alert setInformativeText:[NSString localizedStringWithFormat:
							   NSLocalizedString(@"Brewfile_Not_Recognized_Body", nil),
							   urls.firstObject.lastPathComponent ?: @""]];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_OK", nil)];

	if (self.window)
	{
		[alert beginSheetModalForWindow:self.window completionHandler:nil];
	}
}

#pragma mark - Dock menu

- (NSMenu *)applicationDockMenu:(NSApplication *)sender
{
	// The three things worth doing without switching to the app. Off when
	// Homebrew is missing or a background reload is holding the app: the Dock
	// menu appears with the app in the background, where the app's own
	// explanation of either state is not visible.
	id<BPDockMenuTarget> target = self.dockActionTarget;

	BOOL enabled = target.isHomebrewInstalled
		&& ![BPAppDelegate shouldBlockOperationWhileRunningBackgroundTask:self.isRunningBackgroundTask];

	return [BPDockMenu dockMenuWithTarget:self enabled:enabled];
}

- (IBAction)performDockMenuAction:(id)sender
{
	SEL action = [BPDockMenu controllerActionForItem:(BPDockMenuItem)[sender tag]];
	id<BPDockMenuTarget> target = self.dockActionTarget;

	if (action == NULL || ![target respondsToSelector:action]) return;

	// Two of the three put a sheet on the main window, and the Dock menu is
	// used precisely when the app is not front — so come forward first, or the
	// confirmation goes up where the user cannot see it.
	[NSApp activate];
	[self.window makeKeyAndOrderFront:self];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	[target performSelector:action withObject:sender];
#pragma clang diagnostic pop
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	[[BPHomebrewManager sharedManager] cleanUp];
	return NSTerminateNow;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
	return YES;
}

- (void)cleanupTaskAlerts
{
	UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
	[center removeAllPendingNotificationRequests];
	[center removeAllDeliveredNotifications];
	[[[NSApplication sharedApplication] dockTile] setBadgeLabel:nil];
}

+ (NSURL*)urlForApplicationSupportFolder
{
	NSError *error = nil;
	NSURL *path = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];

	if (error) return nil;
	error = nil;

	path = [path URLByAppendingPathComponent:@"Cakebrew/"];

	[[NSFileManager defaultManager] createDirectoryAtPath:path.relativePath withIntermediateDirectories:YES attributes:nil error:&error];

	if (error) return nil;
	error = nil;

	return path;
}

+ (NSURL*)urlForApplicationCachesFolder
{
	NSError *error = nil;
	NSURL *path = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];

	if (error)
	{
		NSLog(@"Error finding caches directory: %@", path);
		return nil;
	}
	
	error = nil;

	path = [path URLByAppendingPathComponent:@"com.brunophilipe.Cakebrew/"];

	[[NSFileManager defaultManager] createDirectoryAtPath:path.relativePath withIntermediateDirectories:YES attributes:nil error:&error];

	if (error)
	{
		NSLog(@"Error creating Cakebrew cache directory: %@", path);
		return nil;
	}
	
	error = nil;

	return path;
}

- (void)displayBackgroundWarning
{
	// A fresh alert each time so it can be presented as a non-blocking sheet
	// (a reused static instance can't be re-presented while already on screen).
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:NSLocalizedString(@"Message_BGTask_Title", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Generic_OK", nil)];
	[alert setInformativeText:NSLocalizedString(@"Message_BGTask_Body", nil)];

	[alert beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)requestUserAttentionWithMessageTitle:(NSString*)title andDescription:(NSString*)desc
{
	[[NSApplication sharedApplication] requestUserAttention:NSInformationalRequest];
	
	if (![[NSApplication sharedApplication] isActive])
	{
		[[[NSApplication sharedApplication] dockTile] setBadgeLabel:@"●"];
	}
	
	UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
	content.title = title;
	content.subtitle = desc;
	content.sound = [UNNotificationSound defaultSound];
	
	UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.1 repeats:NO];
	
	NSString *identifier = [[NSUUID UUID] UUIDString];
	UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
	
	[[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
		if (error) {
			NSLog(@"Error scheduling notification: %@", error);
		}
	}];
}

#pragma mark - IBActions

- (IBAction)showAboutWindow:(id)sender
{
	[self.aboutWindowController showWindow:sender];
	[self.aboutWindowController.window becomeFirstResponder];
}

- (IBAction)openPreferences:(id)sender
{
	if (!self.preferencesWindowController)
	{
		self.preferencesWindowController = [[BPPreferencesWindowController alloc] init];
		[self.preferencesWindowController.window center];
	}
	[self.preferencesWindowController showWindow:sender];
	[NSApp activateIgnoringOtherApps:YES];
}

+ (BOOL)shouldBlockOperationWhileRunningBackgroundTask:(BOOL)isRunningBackgroundTask
{
	return isRunningBackgroundTask;
}

- (IBAction)openWebsite:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kBP_HOMEBREW_WEBSITE]];
}

- (IBAction)openDocumentation:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kBP_CAKEBREW_DOCUMENTATION]];
}

#pragma mark - User Notification Center Delegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center 
	   didReceiveNotificationResponse:(UNNotificationResponse *)response 
				withCompletionHandler:(void(^)(void))completionHandler
{
	[self cleanupTaskAlerts];
	completionHandler();
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center 
	   willPresentNotification:(UNNotification *)notification 
				withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler
{
	// Show notification even when app is in foreground
	completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
}

@end

@implementation BPAppDelegate (SignalHandler)
void signalHandler(int sig);

- (void)setupSignalHandler
{
	signal(SIGTERM, signalHandler);
}

void signalHandler(int sig) {
	if (sig == SIGTERM) {
		// Force Quit
		[[BPHomebrewManager sharedManager] cleanUp];
	}

	signal(sig, SIG_DFL);
}

@end
