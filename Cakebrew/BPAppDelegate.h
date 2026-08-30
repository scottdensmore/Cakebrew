//
//	AppDelegate.h
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
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import <Cocoa/Cocoa.h>
#import "BPDockMenu.h"

#define BPAppDelegateRef ((BPAppDelegate*)[[NSApplication sharedApplication] delegate])

extern NSString *const kBP_HOMEBREW_PATH;
extern NSString *const kBP_HOMEBREW_PATH_KEY;
extern NSString *const kBP_HOMEBREW_WEBSITE;
extern NSString *const kBP_CAKEBREW_DOCUMENTATION;

/// Who a Brewfile opened from Finder, or dropped on the app, is handed to.
@protocol BPBrewfileImporting <NSObject>
- (void)importBrewfileAtURL:(NSURL *)url;
@end

@interface BPAppDelegate : NSObject <NSApplicationDelegate>

@property (assign) IBOutlet NSWindow *window;

/// Who the Dock menu's actions are sent to. Set by BPHomebrewViewController
/// when it comes up; weak, so a closed window leaves the menu inert rather
/// than firing into a dead controller.
@property (weak) id<BPDockMenuTarget> dockActionTarget;

/// Who handles a Brewfile arriving from outside the app. Weak for the same
/// reason as dockActionTarget: no window, nothing to import into. nonatomic
/// because setting it drains any pending file, through a custom setter.
@property (weak, nonatomic) id<BPBrewfileImporting> brewfileImportTarget;

@property (getter=isRunningBackgroundTask) BOOL runningBackgroundTask;

+ (NSURL*)urlForApplicationSupportFolder;
+ (NSURL*)urlForApplicationCachesFolder;

/**
 *  Whether an operation must not start because a brew run is already in
 *  flight. Homebrew takes its own lock, so a second run fails with a raw error
 *  in the log — this stops it before the user is asked to confirm anything.
 *
 *  Pure so it is testable without a window; the caller pairs it with
 *  -displayBackgroundWarning.
 */
+ (BOOL)shouldBlockOperationWhileRunningBackgroundTask:(BOOL)isRunningBackgroundTask;

- (IBAction)openWebsite:(id)sender;

/// Opens the online documentation. The Help menu item used to send showHelp:,
/// but the app ships no help book, so it only ever produced the system
/// "Help isn't available" alert.
- (IBAction)openDocumentation:(id)sender;
- (IBAction)openPreferences:(id)sender;

- (void)displayBackgroundWarning;
- (void)requestUserAttentionWithMessageTitle:(NSString*)title andDescription:(NSString*)desc;

@end
