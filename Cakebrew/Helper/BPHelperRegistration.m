//
//  BPHelperRegistration.m
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

#import <AppKit/AppKit.h>
#import "BPHelperRegistration.h"
#import "BPHelperSecurity.h"

@implementation BPHelperRegistration

+ (instancetype)sharedRegistration
{
	static BPHelperRegistration *registration;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ registration = [[BPHelperRegistration alloc] init]; });
	return registration;
}

+ (NSString *)agentPlistName
{
	return [BPHelperIdentifier stringByAppendingPathExtension:@"plist"];
}

+ (SMAppService *)service
{
	return [SMAppService agentServiceWithPlistName:[self agentPlistName]];
}

- (BPHelperState)currentState
{
	BPBrewTransport transport = [[BPHomebrewInterface sharedInterface] brewTransport];
	return [BPHelperRegistration stateForTransport:transport
									 serviceStatus:[[BPHelperRegistration service] status]];
}

- (BOOL)registerReturningError:(NSError * _Nullable __autoreleasing * _Nullable)error
{
	return [[BPHelperRegistration service] registerAndReturnError:error];
}

+ (void)openLoginItemsSettings
{
	[SMAppService openSystemSettingsLoginItems];
}

#pragma mark - Pure mapping

+ (BPHelperState)stateForTransport:(BPBrewTransport)transport serviceStatus:(SMAppServiceStatus)status
{
	if (transport != kBPBrewTransportHelper)
	{
		return kBPHelperStateNotRequired;
	}

	switch (status)
	{
		case SMAppServiceStatusEnabled:          return kBPHelperStateReady;
		case SMAppServiceStatusRequiresApproval: return kBPHelperStateNeedsApproval;
		case SMAppServiceStatusNotRegistered:    return kBPHelperStateNotRegistered;
		case SMAppServiceStatusNotFound:         return kBPHelperStateUnavailable;
	}
	// Fail closed: an unrecognised status must never read as usable.
	return kBPHelperStateUnavailable;
}

+ (BOOL)stateAllowsBrewOperations:(BPHelperState)state
{
	return state == kBPHelperStateNotRequired || state == kBPHelperStateReady;
}

+ (BOOL)stateOffersLoginItemsShortcut:(BPHelperState)state
{
	// Only meaningful once something exists for the user to approve.
	return state == kBPHelperStateNeedsApproval;
}

+ (NSString *)localizedDescriptionForState:(BPHelperState)state
{
	switch (state)
	{
		case kBPHelperStateNotRequired:   return NSLocalizedString(@"Helper_State_Not_Required", nil);
		case kBPHelperStateReady:         return NSLocalizedString(@"Helper_State_Ready", nil);
		case kBPHelperStateNeedsApproval: return NSLocalizedString(@"Helper_State_Needs_Approval", nil);
		case kBPHelperStateNotRegistered: return NSLocalizedString(@"Helper_State_Not_Registered", nil);
		case kBPHelperStateUnavailable:   return NSLocalizedString(@"Helper_State_Unavailable", nil);
	}
	return NSLocalizedString(@"Helper_State_Unavailable", nil);
}

@end
