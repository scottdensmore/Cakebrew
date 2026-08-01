//
//  BPHelperSecurity.m
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

#import "BPHelperSecurity.h"

NSString *const BPHelperMachServiceName = @"com.scottdensmore.Cakebrew.Helper";
NSString *const BPHelperIdentifier = @"com.scottdensmore.Cakebrew.Helper";

static NSString *const kBPAppIdentifier = @"com.scottdensmore.Cakebrew";
static NSString *const kBPTeamIdentifier = @"27ZDER873F";

@implementation BPHelperSecurity

+ (NSString *)requirementForIdentifier:(NSString *)identifier
{
	// "anchor apple generic" + the leaf's OU pins the chain to a Developer ID
	// certificate issued to this team. Without it an ad-hoc or self-signed
	// build claiming the same identifier is accepted — measured, not assumed.
	return [NSString stringWithFormat:
			@"identifier \"%@\" and anchor apple generic and certificate leaf[subject.OU] = \"%@\"",
			identifier, kBPTeamIdentifier];
}

+ (NSString *)clientCodeSigningRequirement
{
	return [self requirementForIdentifier:kBPAppIdentifier];
}

+ (NSString *)helperCodeSigningRequirement
{
	return [self requirementForIdentifier:BPHelperIdentifier];
}

@end
