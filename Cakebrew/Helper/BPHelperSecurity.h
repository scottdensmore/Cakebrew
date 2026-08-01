//
//  BPHelperSecurity.h
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

/// launchd label and XPC mach service name for the privileged-adjacent helper.
extern NSString *const BPHelperMachServiceName;
/// SMAppService registration identifier (kept equal to the mach service name).
extern NSString *const BPHelperIdentifier;

/**
 *  Code-signing requirements for the app <-> helper XPC channel.
 *
 *  The helper runs OUTSIDE the app sandbox, so an unauthenticated helper is a
 *  sandbox-escape service for any process on the machine. Both ends pin the
 *  other's designated requirement.
 */
@interface BPHelperSecurity : NSObject

/// Requirement the helper enforces on connecting clients (i.e. the app).
+ (NSString *)clientCodeSigningRequirement;

/// Requirement the app enforces on the helper it connects to.
+ (NSString *)helperCodeSigningRequirement;

@end
