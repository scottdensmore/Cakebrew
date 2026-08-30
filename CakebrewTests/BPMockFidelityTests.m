//
//  BPMockFidelityTests.m
//  CakebrewTests
//
//  AGENTS.md states the invariant: every interface method gets a mock override
//  so UI tests never shell out to real brew. It was quietly false for most
//  formula-side mutating operations, which inherited the real implementations
//  and would have executed brew for real.
//
//  Nothing tripped it only because every mutating journey pressed Cancel at the
//  confirmation sheet. A maintainer doing the step-3 visual review who clicked
//  Tap in the mock build really tapped a repository.
//
//  So the rule enforces itself here: a mutating selector without its own mock
//  implementation fails, including one added tomorrow.
//

#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "BPHomebrewInterface.h"

@interface BPMockFidelityTests : XCTestCase
@end

@implementation BPMockFidelityTests

/// Selectors that run brew in a way that changes the machine's state. Anything
/// added to BPHomebrewInterface that mutates belongs here.
- (NSArray<NSString *> *)mutatingSelectorNames
{
	return @[ @"updateWithReturnBlock:",
			  @"upgradeFormulae:withReturnBlock:",
			  @"upgradeCasks:withReturnBlock:",
			  @"installFormula:withOptions:andReturnBlock:",
			  @"installCask:withReturnBlock:",
			  @"uninstallFormula:withReturnBlock:",
			  @"uninstallCask:withReturnBlock:",
			  @"uninstallCask:zap:withReturnBlock:",
			  @"tapRepository:withReturnsBlock:",
			  @"untapRepository:withReturnsBlock:",
			  @"pinFormula:withReturnBlock:",
			  @"unpinFormula:withReturnBlock:",
			  @"runCleanupWithReturnBlock:",
			  @"runDoctorWithReturnBlock:",
			  @"runBrewExportToolWithPath:",
			  @"runBrewImportToolWithPath:withReturnsBlock:",
			  @"startService:withReturnBlock:",
			  @"stopService:withReturnBlock:",
			  @"restartService:withReturnBlock:" ];
}

- (Class)mockClass
{
	Class mock = NSClassFromString(@"BPMockHomebrewInterface");
	XCTAssertNotNil(mock, @"the mock must be compiled into this (Debug) build");
	return mock;
}

- (void)testEveryMutatingSelectorExistsOnTheRealInterface
{
	// Guards the list itself: a renamed selector must not silently stop being
	// checked.
	for (NSString *name in [self mutatingSelectorNames])
	{
		SEL selector = NSSelectorFromString(name);
		XCTAssertTrue([BPHomebrewInterface instancesRespondToSelector:selector],
					  @"%@ no longer exists — update the list", name);
	}
}

- (void)testTheMockOverridesEveryMutatingSelector
{
	Class mock = [self mockClass];
	NSMutableArray<NSString *> *inherited = [NSMutableArray array];

	for (NSString *name in [self mutatingSelectorNames])
	{
		SEL selector = NSSelectorFromString(name);
		// Responding is not enough — it would inherit the real implementation.
		// The mock must supply its own.
		Method mockMethod = class_getInstanceMethod(mock, selector);
		Method realMethod = class_getInstanceMethod([BPHomebrewInterface class], selector);
		if (mockMethod == realMethod)
		{
			[inherited addObject:name];
		}
	}

	XCTAssertEqual(inherited.count, 0u,
				   @"these would shell out to real brew under -BPMockBrew:\n%@",
				   [inherited componentsJoinedByString:@"\n"]);
}

@end
