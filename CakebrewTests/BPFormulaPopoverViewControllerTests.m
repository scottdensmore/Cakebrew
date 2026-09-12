#import <XCTest/XCTest.h>
#import "BPFormulaPopoverViewController.h"

@interface BPFormulaPopoverViewController (InformationRendererTests)
- (void)displayConsoleInformationForFormula;
@end

// Keep real NSTextView storage, but record the broad checking operation that
// caused the framework wait. Calling its superclass would start that service.
@interface BPInformationTextViewRecorder : NSTextView
@property NSUInteger documentChecks;
@property NSUInteger editableEnables;
@property NSUInteger scrollsToBeginning;
@end

@implementation BPInformationTextViewRecorder
- (void)checkTextInDocument:(id)sender { self.documentChecks++; }
- (void)setEditable:(BOOL)editable
{
    if (editable) self.editableEnables++;
    [super setEditable:editable];
}
- (void)scrollToBeginningOfDocument:(id)sender { self.scrollsToBeginning++; }
@end

// The actual renderer reads this retained model without starting setFormula:'s
// debounce, observers, nib loading or Homebrew information request.
@interface BPInformationRendererController : BPFormulaPopoverViewController
@property (strong) BPFormula *suppliedFormula;
@end

@implementation BPInformationRendererController
- (BPFormula *)formula { return self.suppliedFormula; }
@end

@interface BPFormulaPopoverViewControllerTests : XCTestCase
@property (strong) BPInformationRendererController *controller;
@property (strong) BPInformationTextViewRecorder *textView;
@property (strong) NSFont *font;
@property (strong) NSColor *color;
@end

@implementation BPFormulaPopoverViewControllerTests
- (void)setUp
{
    [super setUp];
    self.controller = [[BPInformationRendererController alloc] initWithNibName:nil bundle:nil];
    self.controller.suppliedFormula = [BPFormula formulaWithName:@"mockwget"];
    self.textView = [[BPInformationTextViewRecorder alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    self.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
    self.color = [NSColor colorWithCalibratedRed:0.2 green:0.3 blue:0.4 alpha:1];
    self.textView.font = self.font;
    self.textView.textColor = self.color;
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.editableEnables = 0;
    self.controller.formulaTextView = self.textView;
}

- (void)tearDown
{
    self.controller = nil;
    self.textView = nil;
    [super tearDown];
}

- (BOOL)renderInformation:(NSString *)information
{
    [self.controller.suppliedFormula setValue:information forKey:@"information"];
    [self.controller displayConsoleInformationForFormula];
    XCTAssertEqual(self.textView.documentChecks, 0u,
        @"information links must not invoke document-wide text checking");
    if (self.textView.documentChecks != 0) return NO;
    XCTAssertEqual(self.textView.editableEnables, 0u);
    XCTAssertFalse(self.textView.editable);
    XCTAssertTrue(self.textView.selectable);
    XCTAssertEqualObjects(self.textView.string, information);
    XCTAssertEqualObjects(self.textView.font, self.font);
    XCTAssertEqualObjects(self.textView.textColor, self.color);
    [self.textView.textStorage enumerateAttributesInRange:NSMakeRange(0, information.length)
        options:0 usingBlock:^(NSDictionary<NSAttributedStringKey, id> *attributes, NSRange range, BOOL *stop) {
            XCTAssertEqualObjects(attributes[NSFontAttributeName], self.font);
            XCTAssertEqualObjects(attributes[NSForegroundColorAttributeName], self.color);
        }];
    return YES;
}

- (void)assertLinks:(NSArray<NSString *> *)URLs inString:(NSString *)string
{
    NSMutableArray<NSDictionary *> *links = [NSMutableArray array];
    [self.textView.textStorage enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, string.length)
        options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
            if (value) [links addObject:@{@"url": value, @"range": [NSValue valueWithRange:range]}];
        }];
    XCTAssertEqual(links.count, URLs.count);
    for (NSUInteger index = 0; index < MIN(links.count, URLs.count); index++) {
        NSRange expectedRange = [string rangeOfString:URLs[index]];
        NSRange actualRange = [links[index][@"range"] rangeValue];
        XCTAssertEqualObjects(links[index][@"url"], [NSURL URLWithString:URLs[index]]);
        XCTAssertTrue(NSEqualRanges(actualRange, expectedRange), @"link must cover the exact UTF-16 URL range");
        XCTAssertEqualObjects([string substringWithRange:actualRange], URLs[index]);
    }
}

- (void)testFormulaLinksPreserveUnicodeTextAndUTF16Ranges
{
    NSString *information = @"🍰 mockwget 1.0\nhttps://example.com/formula/mockwget\nDetails: https://example.org/docs?q=brew\nPlain package description.";
    if (![self renderInformation:information]) return;
    [self assertLinks:@[@"https://example.com/formula/mockwget", @"https://example.org/docs?q=brew"] inString:information];
    XCTAssertNil([self.textView.textStorage attribute:NSLinkAttributeName atIndex:0 effectiveRange:NULL]);
    XCTAssertEqual(self.textView.scrollsToBeginning, 1u);
}

- (void)testCaskLinksPreservePresentationAndScrolling
{
    self.controller.suppliedFormula.cask = YES;
    NSString *information = @"🧰 mockchrome 120.0\nhttps://example.com/casks/mockchrome\nA browser.";
    if (![self renderInformation:information]) return;
    [self assertLinks:@[@"https://example.com/casks/mockchrome"] inString:information];
    XCTAssertEqual(self.textView.scrollsToBeginning, 1u);
}

- (void)testRenderingNewInformationRemovesPreviousLinkAttributes
{
    NSString *first = @"https://example.com/old";
    if (![self renderInformation:first]) return;
    [self assertLinks:@[first] inString:first];

    NSString *plain = @"Ordinary package information with no links.";
    if (![self renderInformation:plain]) return;
    [self assertLinks:@[] inString:plain];

    NSString *replacement = @"New homepage: https://example.org/new";
    if (![self renderInformation:replacement]) return;
    [self assertLinks:@[@"https://example.org/new"] inString:replacement];
    XCTAssertNil([self.textView.textStorage attribute:NSLinkAttributeName atIndex:0 effectiveRange:NULL]);
    XCTAssertEqual(self.textView.scrollsToBeginning, 3u);
}
@end
