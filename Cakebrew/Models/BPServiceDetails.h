#import <Foundation/Foundation.h>
@class BPService;

/// A read-only info response. Failure keeps the complete diagnostic transcript.
@interface BPServiceDetails : NSObject
@property (readonly) BOOL available;
@property (strong, readonly) BPService *service;
@property (copy, readonly) NSString *rawOutput;
@property (copy, readonly) NSString *serviceFile;
@property (copy, readonly) NSString *loadedFile;
@property (copy, readonly) NSString *logPath;
@property (copy, readonly) NSString *errorLogPath;
@property (strong, readonly) NSNumber *exitCode;
+ (instancetype)detailsForName:(NSString *)name output:(NSString *)output succeeded:(BOOL)succeeded;
/// Revalidate immediately before a file action; never open a URL or device.
+ (NSURL *)readableFileURLForPath:(NSString *)path;
@end
