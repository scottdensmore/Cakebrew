//
//  BPBundleWindowController.h
//  Cakebrew
//
//  Created by Bruno Philipe on 20/02/16.
//  Copyright © 2016 Bruno Philipe. All rights reserved.
//

#import <Cocoa/Cocoa.h>
@class BPBrewfilePlan;

@interface BPBundleWindowController : NSWindowController

+ (BPBundleWindowController *)runImportOperationWithPlan:(BPBrewfilePlan *)plan;
/// Reads and reviews without executing Homebrew. Completion is on main.
+ (void)reviewFile:(NSURL *)url inventories:(NSDictionary *)inventories parentWindow:(NSWindow *)window completion:(void (^)(BPBrewfilePlan *confirmedPlan))completion;
+ (BPBundleWindowController*)runExportOperationWithFile:(NSURL*)fileURL;

@end
