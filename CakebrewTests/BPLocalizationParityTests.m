//
//  BPLocalizationParityTests.m
//  CakebrewTests
//
//  A key present in en.lproj and missing elsewhere does not fall back to
//  English — NSLocalizedString returns the key itself, so a German user sees
//  "Formula_All_Dependents_Title" on screen. Four keys were in exactly that
//  state before #75.
//
//  Nothing mechanical caught it, so this does: every locale must carry every
//  English key, and the check is verified against synthetic data so a broken
//  check cannot pass vacuously.
//

#import <XCTest/XCTest.h>

@interface BPLocalizationParityTests : XCTestCase
@end

@implementation BPLocalizationParityTests

- (NSString *)localizationsDirectory
{
	NSString *repoRoot = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	return [repoRoot stringByAppendingPathComponent:@"Cakebrew"];
}

/// key -> value for one .strings file, parsed from source rather than the
/// built bundle so a missing key is caught before it ships.
+ (NSDictionary<NSString *, NSString *> *)stringsAtPath:(NSString *)path
{
	NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
	if (contents.length == 0)
	{
		return @{};
	}

	NSRegularExpression *entry =
		[NSRegularExpression regularExpressionWithPattern:@"^\"([^\"]+)\"\\s*=\\s*\"((?:[^\"\\\\]|\\\\.)*)\";"
												  options:NSRegularExpressionAnchorsMatchLines
													error:NULL];
	NSMutableDictionary *strings = [NSMutableDictionary dictionary];
	[entry enumerateMatchesInString:contents options:0 range:NSMakeRange(0, contents.length)
						 usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
		strings[[contents substringWithRange:[match rangeAtIndex:1]]] =
			[contents substringWithRange:[match rangeAtIndex:2]];
	}];
	return strings;
}

/// Keys in `base` that `locale` does not carry.
+ (NSArray<NSString *> *)keysMissingFromLocale:(NSDictionary *)locale comparedTo:(NSDictionary *)base
{
	NSMutableArray<NSString *> *missing = [NSMutableArray array];
	for (NSString *key in base)
	{
		if (!locale[key])
		{
			[missing addObject:key];
		}
	}
	return [missing sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<NSString *> *)localeDirectoryNames
{
	NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self localizationsDirectory] error:NULL];
	NSMutableArray *locales = [NSMutableArray array];
	for (NSString *entry in entries)
	{
		if ([entry hasSuffix:@".lproj"])
		{
			[locales addObject:entry];
		}
	}
	return locales;
}

- (void)testTheCheckItselfDetectsAMissingKey
{
	// Guards the guard: verified against synthetic data, so the real assertion
	// below cannot pass because the comparison is broken.
	NSDictionary *base = @{ @"a": @"A", @"b": @"B" };
	NSDictionary *complete = @{ @"a": @"A", @"b": @"traduit" };
	NSDictionary *incomplete = @{ @"a": @"A" };

	XCTAssertEqual([[self class] keysMissingFromLocale:complete comparedTo:base].count, 0u);
	XCTAssertEqualObjects([[self class] keysMissingFromLocale:incomplete comparedTo:base], (@[ @"b" ]));
}

- (void)testTheParserReadsRealEntries
{
	NSString *path = [[self localizationsDirectory] stringByAppendingPathComponent:@"en.lproj/Localizable.strings"];
	NSDictionary *english = [[self class] stringsAtPath:path];

	XCTAssertGreaterThan(english.count, 100u, @"the parser should read the whole English file");
	XCTAssertNotNil(english[@"Sidebar_Item_Services"], @"a known key should be present");
}

- (void)testDetailPlaceholderAndExportFailureHaveReadableEnglishDefaults
{
	NSString *root = [self localizationsDirectory];
	for (NSString *locale in @[@"en", @"de", @"fr", @"it", @"pt", @"zh-Hans"])
	{
		NSString *path = [root stringByAppendingPathComponent:
			[NSString stringWithFormat:@"%@.lproj/Localizable.strings", locale]];
		NSDictionary *strings = [[self class] stringsAtPath:path];
		XCTAssertNotNil(strings[@"Info_View_Empty_Value"], @"%@ needs the detail placeholder", locale);
		XCTAssertNotNil(strings[@"Brewfile_Export_Failed"], @"%@ needs the export failure caption", locale);
		if ([locale isEqualToString:@"en"])
		{
			XCTAssertEqualObjects(strings[@"Info_View_Empty_Value"], @"--");
			XCTAssertEqualObjects(strings[@"Brewfile_Export_Failed"], @"Export Failed");
		}
	}
}

- (void)testEveryLocaleCarriesEveryEnglishKey
{
	NSString *root = [self localizationsDirectory];
	NSDictionary *english = [[self class] stringsAtPath:
							 [root stringByAppendingPathComponent:@"en.lproj/Localizable.strings"]];
	XCTAssertGreaterThan(english.count, 0u);

	NSArray *locales = [self localeDirectoryNames];
	XCTAssertGreaterThanOrEqual(locales.count, 6u, @"all six localizations should be scanned");

	NSMutableArray<NSString *> *problems = [NSMutableArray array];
	for (NSString *locale in locales)
	{
		if ([locale isEqualToString:@"en.lproj"] || [locale isEqualToString:@"Base.lproj"])
		{
			continue;
		}

		NSString *path = [root stringByAppendingPathComponent:
						  [locale stringByAppendingPathComponent:@"Localizable.strings"]];
		NSArray *missing = [[self class] keysMissingFromLocale:[[self class] stringsAtPath:path]
													comparedTo:english];
		if (missing.count > 0)
		{
			[problems addObject:[NSString stringWithFormat:@"%@ is missing: %@",
								 locale, [missing componentsJoinedByString:@", "]]];
		}
	}

	XCTAssertEqual(problems.count, 0u,
				   @"a missing key renders as the raw key name on screen, not as English:\n%@",
				   [problems componentsJoinedByString:@"\n"]);
}

// Resolve the real resources through NSBundle; a source parser alone cannot
// establish the value presented by NSLocalizedString.
- (NSBundle *)bundleForLocale:(NSString *)locale
{
 return [NSBundle bundleWithPath:[[self localizationsDirectory] stringByAppendingPathComponent:[locale stringByAppendingString:@".lproj"]]];
}

- (void)testGermanBrewfileResourcesAreTranslated
{
 NSBundle *german = [self bundleForLocale:@"de"];
 NSBundle *english = [self bundleForLocale:@"en"];
 XCTAssertNotNil(german);
 XCTAssertNotNil(english);
 NSString *missing = @"__CAKEBREW_MISSING_TRANSLATION__";
 XCTAssertEqualObjects([german localizedStringForKey:@"__unknown_brewfile_key__" value:missing table:@"Localizable"], missing);
 NSArray *keys = @[
 @"Line %lu: unsupported syntax or invalid package name. Nothing will be installed.",
 @"Choose a readable UTF-8 Brewfile smaller than 1 MiB. Nothing was installed.",
 @"%lu installed • %lu missing • %lu not checked", @"Installed", @"Missing", @"Not checked",
 @"No supported package entries. Nothing will be installed.",
 @"Reviewed import requires the standard, non-sandboxed Cakebrew app. Helper transport is not supported.",
 @"Review Brewfile",
 @"Direct entries only, not a dependency or upgrade plan. Installed means present in the current inventory, not up to date. Homebrew may upgrade packages, install dependencies and required tools, and run package installation scripts. Only the reviewed literal entries will be submitted.",
 @"Install Reviewed Entries", @"Cancel", @"Close", @"Import Brewfile",
 @"Import cancelled. Some changes may already have been made.", @"Import finished.",
 @"Import failed. Review the output for details.", @"Cancelling… Waiting for Homebrew to exit.",
 @"Brewfile_Export_Failed", @"Homebrew could not export the Brewfile. Check the destination and try again."
 ];
 for (NSString *key in keys) {
  NSString *translated = [german localizedStringForKey:key value:missing table:@"Localizable"];
  NSString *original = [english localizedStringForKey:key value:missing table:@"Localizable"];
  XCTAssertNotEqualObjects(translated, missing, @"%@", key);
  XCTAssertNotEqualObjects(original, missing, @"%@", key);
  XCTAssertGreaterThan([translated stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length, 0u, @"%@", key);
  XCTAssertNotEqualObjects(translated, original, @"German Brewfile text still uses English: %@", key);
 }
}

- (void)testGermanBrewfileFormatsPreserveUnsignedArguments
{
 NSBundle *german = [self bundleForLocale:@"de"];
 NSBundle *english = [self bundleForLocale:@"en"];
 NSArray *keys = @[@"Line %lu: unsupported syntax or invalid package name. Nothing will be installed.",
                   @"%lu installed • %lu missing • %lu not checked"];
 for (NSString *key in keys) {
  NSString *format = [german localizedStringForKey:key value:@"MISSING" table:@"Localizable"];
  NSString *original = [english localizedStringForKey:key value:@"MISSING" table:@"Localizable"];
  // Removing the only supported conversion also catches stray or changed % tokens.
  NSArray *parts = [format componentsSeparatedByString:@"%lu"];
  NSArray *originalParts = [original componentsSeparatedByString:@"%lu"];
  XCTAssertEqual(parts.count, originalParts.count);
  XCTAssertFalse([[parts componentsJoinedByString:@""] containsString:@"%"]);
  if (parts.count != originalParts.count || [[parts componentsJoinedByString:@""] containsString:@"%"]) continue;
  NSString *rendered = parts.count == 2 ? [NSString stringWithFormat:format, (unsigned long)23] :
      [NSString stringWithFormat:format, (unsigned long)2, (unsigned long)3, (unsigned long)5];
  XCTAssertFalse([rendered containsString:@"%"]);
  NSRegularExpression *numbers = [NSRegularExpression regularExpressionWithPattern:@"[0-9]+" options:0 error:NULL];
  NSMutableArray *values = [NSMutableArray array];
  for (NSTextCheckingResult *match in [numbers matchesInString:rendered options:0 range:NSMakeRange(0, rendered.length)]) {
   [values addObject:[rendered substringWithRange:match.range]];
  }
  XCTAssertEqualObjects(values, parts.count == 2 ? (@[@"23"]) : (@[@"2", @"3", @"5"]));
 }
}

@end
