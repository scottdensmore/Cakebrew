#import <Cocoa/Cocoa.h>
@class BPHomebrewInterface, BPHomebrewManager;
@interface BPAutoremoveWindowController : NSWindowController
+ (instancetype)presentForWindow:(NSWindow *)parent interface:(BPHomebrewInterface *)interface manager:(BPHomebrewManager *)manager;
@end
