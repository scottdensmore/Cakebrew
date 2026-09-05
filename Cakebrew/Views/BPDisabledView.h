//
//  BPDisabledView.h
//  
//
//  Created by Marek Hrusovsky on 26/08/15.
//
//

#import <Cocoa/Cocoa.h>
#import "BPHomebrewInterface.h"

@interface BPDisabledView : NSView

@property (copy) void (^retryHandler)(void);
- (void)showDiscoveryResult:(BPHomebrewDiscoveryResult)result checking:(BOOL)checking;

@end
