//
//  BPHelperRegistration.h
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

#import <Foundation/Foundation.h>
#import <ServiceManagement/ServiceManagement.h>
#import "BPHomebrewInterface.h"

/// What the app should tell the user, and whether brew can run.
typedef NS_ENUM(NSInteger, BPHelperState) {
	/// Running unsandboxed: brew runs in-process and no helper is involved.
	kBPHelperStateNotRequired,
	/// Registered and approved.
	kBPHelperStateReady,
	/// Registered, but the user must enable it in Login Items.
	kBPHelperStateNeedsApproval,
	/// Not registered yet; the app should call -registerReturningError:.
	kBPHelperStateNotRegistered,
	/// Missing or unusable (e.g. the app isn't installed in /Applications).
	kBPHelperStateUnavailable,
};

NS_ASSUME_NONNULL_BEGIN

/**
 *  Registration and status of CakebrewHelper as a per-user launchd agent
 *  (SMAppService, macOS 13+).
 */
@interface BPHelperRegistration : NSObject

+ (instancetype)sharedRegistration;

/// File name of the LaunchAgent plist embedded in the app bundle.
+ (NSString *)agentPlistName;

/// Current state, combining the active transport with the service status.
- (BPHelperState)currentState;

/// Registers the agent. Returns NO and fills `error` on failure.
- (BOOL)registerReturningError:(NSError * _Nullable __autoreleasing * _Nullable)error;

/// Opens System Settings > General > Login Items.
+ (void)openLoginItemsSettings;

#pragma mark - Pure mapping (unit-tested)

+ (BPHelperState)stateForTransport:(BPBrewTransport)transport serviceStatus:(SMAppServiceStatus)status;
+ (BOOL)stateAllowsBrewOperations:(BPHelperState)state;
+ (BOOL)stateOffersLoginItemsShortcut:(BPHelperState)state;
+ (NSString *)localizedDescriptionForState:(BPHelperState)state;

@end

NS_ASSUME_NONNULL_END
