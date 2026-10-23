//
//	DCOAboutWindowController.m
//	Tapetrap
//
//	Created by Boy van Amstel on 20-01-14.
//	Copyright (c) 2014 Danger Cove. All rights reserved.
//

#import "DCOAboutWindowController.h"
#import "BPFormulaInformation-Swift.h"

@interface DCOAboutWindowController()

/** The window nib to load. */
+ (NSString *)nibName;

/** The info view. */
@property (strong) IBOutlet NSView *infoView;

/** The credits text view. */
@property (strong, nonatomic, readwrite) IBOutlet NSTextView *creditsTextView;

/** The button that opens the app's website. */
@property (strong) IBOutlet NSButton *visitWebsiteButton;

/** The button that opens the acknowledgements. */
@property (strong) IBOutlet NSButton *acknowledgementsButton;

@property (strong, nonatomic, readwrite) BPAboutWindowHost *aboutHost;
@property (copy, nonatomic) NSAttributedString *appAcknowledgements;

@end

@implementation DCOAboutWindowController

#pragma mark - Class Methods

+ (NSString *)nibName {
    return @"DCOAboutWindow";
}

#pragma mark - Overrides

- (id)init {
    return [super initWithWindowNibName:[[self class] nibName]];
}

- (void)loadWindow {
    if ([NSBundle.mainBundle pathForResource:[[self class] nibName] ofType:@"nib"]) {
        [super loadWindow];
    } else {
        self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 360)
                                                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    }
}

- (void)windowDidLoad {
    [super windowDidLoad];

    // Load variables
    NSDictionary *bundleDict = [[NSBundle mainBundle] infoDictionary];
    NSBundle *resourceBundle = [NSBundle bundleForClass:[self class]];
    
    // Set app name
    if(!self.appName) {
        self.appName = [bundleDict objectForKey:@"CFBundleName"] ?: @"Cakebrew";
    }

    // Set app version
    if(!self.appVersion) {
        NSString *version = [bundleDict objectForKey:@"CFBundleVersion"] ?: @"1";
        NSString *shortVersion = [bundleDict objectForKey:@"CFBundleShortVersionString"] ?: @"1.0";
        self.appVersion = [NSString stringWithFormat:NSLocalizedString(@"Version %@ (Build %@)", nil), shortVersion, version];
    }
    
    // Set copyright
    if(!self.appCopyright) {
        self.appCopyright = [bundleDict objectForKey:@"NSHumanReadableCopyright"] ?: @"";
    }

    // Set "visit website" caption
    if (self.visitWebsiteButton.title.length > 0 && [self.visitWebsiteButton.title containsString:@"%@"]) {
        self.visitWebsiteButton.title = [NSString stringWithFormat:self.visitWebsiteButton.title, self.appName];
    }
    
    // Set acknowledgements
    if(!self.acknowledgementsPath) {
        self.acknowledgementsPath = [[NSBundle mainBundle] pathForResource:@"Acknowledgements" ofType:@"rtf"]
            ?: [resourceBundle pathForResource:@"Acknowledgements" ofType:@"rtf"];
    }
    [self loadAppAcknowledgements];

    // Set credits
    if(!self.appCredits) {
        [self loadAppCredits];
    }

    if (!self.creditsTextView) {
        self.creditsTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 440, 180)];
    }
    [self.creditsTextView setEditable:NO];
    [self.creditsTextView setSelectable:YES];
    self.creditsTextView.textContainerInset = NSMakeSize(8, 8);
    self.creditsTextView.accessibilityIdentifier = @"about.textView";
    [self applyDisplayedAttributedText:self.appCredits];

    self.aboutHost = [[BPAboutWindowHost alloc] initWithCreditsTextView:self.creditsTextView];
    [self.aboutHost configureWithAppName:self.appName ?: @"Cakebrew"
                              appVersion:self.appVersion ?: @""
                            appCopyright:self.appCopyright ?: @""
                     hasAcknowledgements:(self.acknowledgementsPath.length > 0 || self.appAcknowledgements.length > 0)];

    __weak typeof(self) weakSelf = self;
    self.aboutHost.onVisitWebsite = ^{
        [weakSelf visitWebsite:nil];
    };
    self.aboutHost.onSelectTab = ^(NSInteger tabIndex) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSAttributedString *targetText = (tabIndex == 1 && strongSelf.appAcknowledgements.length > 0)
            ? strongSelf.appAcknowledgements
            : strongSelf.appCredits;
        [strongSelf applyDisplayedAttributedText:targetText];
    };

    NSView *contentView = self.window.contentView;
    for (NSView *subview in [contentView.subviews copy]) {
        [subview removeFromSuperview];
    }
    NSView *hostView = self.aboutHost.viewController.view;
    hostView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:hostView];
    [NSLayoutConstraint activateConstraints:@[
        [hostView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [hostView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [hostView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [hostView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
    ]];
    [self.window setContentSize:NSMakeSize(500, 380)];
}

- (void)applyDisplayedAttributedText:(NSAttributedString *)attributedText
{
    if (!self.creditsTextView.textStorage) return;
    if (attributedText) {
        [self.creditsTextView.textStorage setAttributedString:attributedText];
    } else {
        [self.creditsTextView setString:@""];
    }
}

- (NSAttributedString *)normalizedAttributedStringFromRTFURL:(NSURL *)url
{
    if (!url) return nil;
    NSError *error = nil;
    NSAttributedString *attributed = [[NSAttributedString alloc] initWithURL:url
                                                                     options:@{}
                                                          documentAttributes:nil
                                                                       error:&error];
    if (!attributed) return nil;

    NSMutableAttributedString *mutableText = [attributed mutableCopy];
    [attributed enumerateAttribute:NSForegroundColorAttributeName
                           inRange:NSMakeRange(0, [attributed length])
                           options:0
                        usingBlock:^(id _Nullable value, NSRange range, BOOL * _Nonnull stop) {
        if (value == nil && range.length > 0) {
            [mutableText addAttribute:NSForegroundColorAttributeName value:[NSColor textColor] range:range];
        }
    }];
    return mutableText;
}

- (void)loadAppCredits
{
    NSURL *creditsURL = [[NSBundle mainBundle] URLForResource:@"Credits" withExtension:@"rtf"]
        ?: [[NSBundle bundleForClass:[self class]] URLForResource:@"Credits" withExtension:@"rtf"];
    NSAttributedString *credits = [self normalizedAttributedStringFromRTFURL:creditsURL];
    if (credits) {
        self.appCredits = credits;
    }
}

- (void)loadAppAcknowledgements
{
    NSURL *ackURL = self.acknowledgementsPath.length > 0
        ? [NSURL fileURLWithPath:self.acknowledgementsPath]
        : ([[NSBundle mainBundle] URLForResource:@"Acknowledgements" withExtension:@"rtf"]
           ?: [[NSBundle bundleForClass:[self class]] URLForResource:@"Acknowledgements" withExtension:@"rtf"]);
    NSAttributedString *ack = [self normalizedAttributedStringFromRTFURL:ackURL];
    if (ack) {
        self.appAcknowledgements = ack;
    }
}

#pragma mark - Getters/Setters

- (void)setAcknowledgementsPath:(NSString *)acknowledgementsPath {
    _acknowledgementsPath = [acknowledgementsPath copy];
    [self loadAppAcknowledgements];
    if(!acknowledgementsPath) {
        [self.acknowledgementsButton removeFromSuperview];
    }
    if (self.aboutHost) {
        [self.aboutHost configureWithAppName:self.appName ?: @"Cakebrew"
                                  appVersion:self.appVersion ?: @""
                                appCopyright:self.appCopyright ?: @""
                         hasAcknowledgements:(acknowledgementsPath.length > 0 || self.appAcknowledgements.length > 0)];
    }
}

#pragma mark - Interface Methods

- (IBAction)visitWebsite:(id)sender {
    if(self.appWebsiteURL) {
        [[NSWorkspace sharedWorkspace] openURL:self.appWebsiteURL];
    } else {
        NSLog(@"Error: please set the appWebsiteURL property on the about window");
    }
}

- (IBAction)showAcknowledgements:(id)sender {
    if (self.aboutHost && self.appAcknowledgements.length > 0) {
        [self.aboutHost selectTabAtIndex:1];
        return;
    }
    if(self.acknowledgementsPath) {
        NSURL *acknowledgementsURL = [NSURL fileURLWithPath:self.acknowledgementsPath];
        [[NSWorkspace sharedWorkspace] openURL:acknowledgementsURL];
    } else {
        NSLog(@"Error: couldn't load the acknowledgements file");
    }
}

@end
