#import <Foundation/Foundation.h>
#import "BPFormulaInformation-Swift.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const BPErrorDomain;
extern NSString *const BPBrewErrorExitStatusKey;

typedef NS_ENUM(NSInteger, BPBrewErrorCode) {
	BPBrewErrorLaunchFailed = 1,
	BPBrewErrorNonZeroExit = 2,
	BPBrewErrorMalformedOutput = 3,
};

NS_ASSUME_NONNULL_END
