//
//  BPEmptyState.h
//  Cakebrew
//
//	This program is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 *  What to say when a list has no rows.
 *
 *  Pure and keyed rather than localized here, so the mapping can be tested
 *  without a bundle — the test target carries no Localizable.strings.
 */
@interface BPEmptyState : NSObject

@property (readonly) NSString *symbolName;
@property (readonly) NSString *titleKey;
@property (readonly) NSString *messageKey;

/// The state for a sidebar row. A search in progress wins: a no-result search
/// should explain the search, not the list underneath it.
+ (instancetype)stateForSidebarRow:(NSInteger)row searching:(BOOL)searching;

/// Empty is not the same as loading — saying "No Results" during the first
/// reload would be a lie.
+ (BOOL)shouldShowForRowCount:(NSInteger)rowCount loading:(BOOL)loading;

@end

NS_ASSUME_NONNULL_END
