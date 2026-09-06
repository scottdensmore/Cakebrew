//
//  BPFormulaeTableView.h
//  Cakebrew
//
//  Created by Marek Hrusovsky on 04/09/14.
//  Copyright (c) 2014 Bruno Philipe. All rights reserved.
//

#import "BPHomebrewInterface.h"
#import <Cocoa/Cocoa.h>

extern NSString * const kColumnIdentifierVersion;
extern NSString * const kColumnIdentifierLatestVersion;
extern NSString * const kColumnIdentifierStatus;
extern NSString * const kColumnIdentifierName;

typedef NS_ENUM(NSInteger, BPFormulaeTableRequest) {
	BPFormulaeTableRequestPrimary,
	BPFormulaeTableRequestUninstall
};

@class BPFormulaeTableView;
@protocol BPFormulaeTableActionDelegate <NSObject>
- (void)formulaeTableView:(BPFormulaeTableView *)table requestAction:(BPFormulaeTableRequest)request;
@end

@interface BPFormulaeTableView : NSTableView

@property (nonatomic, assign) BPListMode mode;
@property (nonatomic, weak) id<BPFormulaeTableActionDelegate> actionDelegate;

@end
