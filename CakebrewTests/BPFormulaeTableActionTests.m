#import <XCTest/XCTest.h>
#import "BPFormulaeTableView.h"
#import "BPFormulaeTableAction.h"

@interface BPFormulaeTableView (ActionTesting)
- (void)performDoubleClickAction:(id)sender;
@end

@interface BPTableActionRecorder : NSObject <BPFormulaeTableActionDelegate>
@property NSInteger count;
@property BPFormulaeTableRequest request;
@end
@implementation BPTableActionRecorder
- (void)formulaeTableView:(BPFormulaeTableView *)table requestAction:(BPFormulaeTableRequest)request
{ self.count++; self.request = request; }
@end

@interface BPTableActionWindowStub : NSObject
@property (weak) NSResponder *firstResponder;
@end
@implementation BPTableActionWindowStub
@end

@interface BPActionTestTable : BPFormulaeTableView
@property (strong) BPTableActionWindowStub *testWindow;
@property NSInteger testSelectedRow;
@property NSInteger spaceCount;
@property NSInteger testClickedRow;
@end
@implementation BPActionTestTable
- (NSWindow *)window { return (NSWindow *)self.testWindow; }
- (NSInteger)selectedRow { return self.testSelectedRow; }
- (NSInteger)clickedRow { return self.testClickedRow; }
- (NSInteger)numberOfRows { return 2; }
- (NSIndexSet *)selectedRowIndexes { return self.testSelectedRow < 0 ? [NSIndexSet indexSet] : [NSIndexSet indexSetWithIndex:(NSUInteger)self.testSelectedRow]; }
- (void)spaceBarPressed { self.spaceCount++; }
@end

@interface BPFormulaeTableActionTests : XCTestCase
@property (strong) BPActionTestTable *table;
@property (strong) BPTableActionRecorder *recorder;
@end
@implementation BPFormulaeTableActionTests
- (void)testNativeDoubleActionOnlyRequestsPrimaryForASelectedExistingRow
{
    XCTAssertNotEqual(self.table.doubleAction, NULL, @"Native table doubleAction must be wired");
    if (!self.table.doubleAction) return;
    XCTAssertEqual(self.table.target, self.table);
    XCTAssertEqual(self.table.doubleAction, @selector(performDoubleClickAction:));
    [self.table performDoubleClickAction:self.table];
    XCTAssertEqual(self.recorder.count, 1);
    XCTAssertEqual(self.recorder.request, BPFormulaeTableRequestPrimary);
    for (NSNumber *row in @[@-1, @1, @2, @99]) {
        self.table.testClickedRow = row.integerValue;
        [self.table performDoubleClickAction:self.table];
        XCTAssertEqual(self.recorder.count, 1, @"Empty space, header, stale and unselected rows cannot act");
        XCTAssertEqual(self.table.testSelectedRow, 0, @"Guarding the action must not change selection");
    }
}
- (void)setUp
{
    [super setUp];
    self.table = [[BPActionTestTable alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
    [self.table awakeFromNib];
    self.table.testWindow = [BPTableActionWindowStub new];
    self.table.testWindow.firstResponder = self.table;
    self.table.testSelectedRow = 0;
    self.recorder = [BPTableActionRecorder new];
    self.table.actionDelegate = self.recorder;
}
- (void)tearDown
{
    self.table.testWindow = nil;
    self.table = nil;
    self.recorder = nil;
    [super tearDown];
}
- (NSEvent *)key:(unichar)key flags:(NSEventModifierFlags)flags repeat:(BOOL)repeat type:(NSEventType)type
{
    NSString *characters = [NSString stringWithCharacters:&key length:1];
    return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0 context:nil characters:characters charactersIgnoringModifiers:characters isARepeat:repeat keyCode:0];
}
- (void)testPlainReturnKeypadEnterAndBothDeletesDispatchTypedRequests
{
    for (NSNumber *key in @[@0x0d, @0x03, @0x7f, @0xf728]) {
        self.recorder.count = 0;
        XCTAssertTrue([self.table performKeyEquivalent:[self key:key.unsignedShortValue flags:0 repeat:NO type:NSEventTypeKeyDown]]);
        XCTAssertEqual(self.recorder.count, 1);
        XCTAssertEqual(self.recorder.request, key.unsignedShortValue < 0x7f ? BPFormulaeTableRequestPrimary : BPFormulaeTableRequestUninstall);
    }
}
- (void)testShortcutModifiersAndRepeatsNeverDispatchNewActions
{
    for (NSNumber *key in @[@0x0d, @0x03, @0x7f, @0xf728]) {
        for (NSNumber *flag in @[@(NSEventModifierFlagCommand), @(NSEventModifierFlagOption), @(NSEventModifierFlagControl), @(NSEventModifierFlagShift)]) {
            XCTAssertFalse([self.table performKeyEquivalent:[self key:key.unsignedShortValue flags:flag.unsignedIntegerValue repeat:NO type:NSEventTypeKeyDown]]);
        }
        XCTAssertFalse([self.table performKeyEquivalent:[self key:key.unsignedShortValue flags:0 repeat:YES type:NSEventTypeKeyDown]]);
    }
    XCTAssertEqual(self.recorder.count, 0);
}
- (void)testCapsLockFunctionAndNumericPadDoNotBlockRowActions
{
    for (NSNumber *flag in @[@(NSEventModifierFlagCapsLock), @(NSEventModifierFlagFunction), @(NSEventModifierFlagNumericPad)]) {
        XCTAssertTrue([self.table performKeyEquivalent:[self key:0x03 flags:flag.unsignedIntegerValue repeat:NO type:NSEventTypeKeyDown]]);
    }
    XCTAssertEqual(self.recorder.count, 3);
}
- (void)testKeyUpOtherKeysNoSelectionAndOtherFocusDoNotDispatch
{
    XCTAssertFalse([self.table performKeyEquivalent:[self key:0x0d flags:0 repeat:NO type:NSEventTypeKeyUp]]);
    XCTAssertFalse([self.table performKeyEquivalent:[self key:'a' flags:0 repeat:NO type:NSEventTypeKeyDown]]);
    self.table.testSelectedRow = -1;
    XCTAssertFalse([self.table performKeyEquivalent:[self key:0x0d flags:0 repeat:NO type:NSEventTypeKeyDown]]);
    self.table.testSelectedRow = 0;
    self.table.testWindow = nil;
    XCTAssertFalse([self.table performKeyEquivalent:[self key:0x0d flags:0 repeat:NO type:NSEventTypeKeyDown]]);
    XCTAssertEqual(self.recorder.count, 0);
}
- (void)testSpacePreservesExistingModifiedAndRepeatingBehavior
{
    XCTAssertTrue([self.table performKeyEquivalent:[self key:' ' flags:NSEventModifierFlagCommand repeat:YES type:NSEventTypeKeyDown]]);
    XCTAssertEqual(self.table.spaceCount, 1);
    XCTAssertEqual(self.recorder.count, 0);
}
- (BPFormula *)formula:(BOOL)cask
{
    BPFormula *formula = [BPFormula formulaWithName:@"fixture"];
    formula.cask = cask;
    return formula;
}
- (void)testSingleSelectionMappingForEveryListNamespaceAndStatus
{
    for (NSInteger mode = kBPListAll; mode <= kBPListAllCasks; mode++) {
        for (NSNumber *cask in @[@NO, @YES]) {
            for (NSInteger status = kBPFormulaNotInstalled; status <= kBPFormulaOutdated; status++) {
                BOOL namespaceMatches = mode == kBPListSearch ||
                    (cask.boolValue == (mode == kBPListAllCasks || mode == kBPListInstalledCasks || mode == kBPListOutdatedCasks));
                BOOL valid = namespaceMatches && mode != kBPListRepositories;
                BPFormulaeTableAction primary = BPFormulaeTableActionNone;
                if (valid && (mode == kBPListAll || mode == kBPListAllCasks) && status == kBPFormulaNotInstalled) primary = BPFormulaeTableActionInstall;
                if (valid && (mode == kBPListInstalled || mode == kBPListInstalledCasks) && status != kBPFormulaNotInstalled) primary = BPFormulaeTableActionInfo;
                if (valid && (mode == kBPListOutdated || mode == kBPListOutdatedCasks) && status == kBPFormulaOutdated) primary = BPFormulaeTableActionUpgrade;
                // An installed/outdated list with a contradictory status is stale.
                BOOL stale = ((mode == kBPListInstalled || mode == kBPListInstalledCasks || mode == kBPListLeaves || mode == kBPListPinned) && status == kBPFormulaNotInstalled)
                    || ((mode == kBPListOutdated || mode == kBPListOutdatedCasks) && status != kBPFormulaOutdated);
                BPFormulaeTableAction deletion = valid && !stale && status != kBPFormulaNotInstalled ? BPFormulaeTableActionUninstall : BPFormulaeTableActionNone;
                NSArray *formulae = @[[self formula:cask.boolValue]];
                XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestPrimary mode:mode formulae:formulae statuses:@[@(status)]]), primary, @"mode=%ld cask=%@ status=%ld", (long)mode, cask, (long)status);
                XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestUninstall mode:mode formulae:formulae statuses:@[@(status)]]), deletion, @"mode=%ld cask=%@ status=%ld", (long)mode, cask, (long)status);
            }
        }
    }
}
- (void)testOnlyHomogeneousOutdatedMultiSelectionCanUpgrade
{
    for (NSInteger mode = kBPListAll; mode <= kBPListAllCasks; mode++) {
        BOOL casks = mode == kBPListOutdatedCasks;
        NSArray *formulae = @[[self formula:casks], [self formula:casks]];
        BPFormulaeTableAction expected = mode == kBPListOutdated || mode == kBPListOutdatedCasks ? BPFormulaeTableActionUpgrade : BPFormulaeTableActionNone;
        XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestPrimary mode:mode formulae:formulae statuses:@[@2, @2]]), expected);
        XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestUninstall mode:mode formulae:formulae statuses:@[@2, @2]]), BPFormulaeTableActionNone);
    }
    XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestPrimary mode:kBPListOutdated formulae:@[[self formula:NO], [self formula:YES]] statuses:@[@2, @2]]), BPFormulaeTableActionNone);
    XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestPrimary mode:kBPListOutdated formulae:@[[self formula:NO], [self formula:NO]] statuses:@[@2, @1]]), BPFormulaeTableActionNone);
}
- (void)testMissingMalformedUnknownAndStaleSelectionsFailClosed
{
    NSArray *invalidFormulae = @[@[], @[@"not a model"], @[[BPFormula formulaWithName:@""]]];
    for (NSArray *formulae in invalidFormulae) {
        XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestPrimary mode:kBPListAll formulae:formulae statuses:@[@0]]), BPFormulaeTableActionNone);
    }
    NSArray *one = @[[self formula:NO]];
    for (NSArray *statuses in @[@[], @[@99], @[@-1], @[@"bad"], @[@0, @0]]) {
        XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestPrimary mode:kBPListAll formulae:one statuses:statuses]), BPFormulaeTableActionNone);
    }
    XCTAssertEqual(([BPFormulaeTableActions actionForRequest:99 mode:kBPListAll formulae:one statuses:@[@0]]), BPFormulaeTableActionNone);
    XCTAssertEqual(([BPFormulaeTableActions actionForRequest:BPFormulaeTableRequestPrimary mode:99 formulae:one statuses:@[@0]]), BPFormulaeTableActionNone);
}
- (void)testReturnIsHandledByTheFocusedSelectedTable
{
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
    XCTAssertTrue([self.table performKeyEquivalent:event], @"Return should be handled locally by the focused selected formula table");
}
@end
