#import <Foundation/Foundation.h>

/// A deliberately non-executing subset of the Ruby Brewfile DSL.
@interface BPBrewfileEntry : NSObject
@property (copy, readonly) NSString *kind;
@property (copy, readonly) NSString *name;
@property (copy, readonly) NSString *status;
@end

@interface BPBrewfilePlan : NSObject
@property (copy, readonly) NSArray<BPBrewfileEntry *> *entries;
@property (copy, readonly) NSArray<NSString *> *diagnostics;
@property (copy, readonly) NSString *canonicalContents;
@property (readonly) BOOL canInstall;
@property (copy, readonly) NSString *reviewText;
/// Reads at most 1 MiB from a local regular UTF-8 file; does not evaluate Ruby.
+ (instancetype)planWithURL:(NSURL *)url inventories:(NSDictionary *)inventories error:(NSError *__autoreleasing *)error;
/// Inventories map brew/cask/tap to exact names. An absent inventory is unknown.
+ (instancetype)planWithString:(NSString *)contents inventories:(NSDictionary<NSString *, NSArray<NSString *> *> *)inventories;
- (NSURL *)createSnapshotWithError:(NSError *__autoreleasing *)error;
+ (void)removeSnapshot:(NSURL *)snapshot;
@end
