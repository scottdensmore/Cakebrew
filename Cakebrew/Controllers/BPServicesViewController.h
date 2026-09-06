//
//  BPServicesViewController.h
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

/**
 *  The Services tool view: lists `brew services` with their status and
 *  offers start / stop / restart. The view is built programmatically
 *  (no xib) and refreshes its own list after operations.
 */
@interface BPServicesViewController : NSViewController

/** Reloads the service list from brew on a background queue. */
- (void)refreshServices;

/// Invalidates outstanding details/list replies when leaving the tool.
- (void)invalidateServiceDetails;

@end
