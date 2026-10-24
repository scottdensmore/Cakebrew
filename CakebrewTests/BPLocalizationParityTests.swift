//
//  BPLocalizationParityTests.swift
//  CakebrewTests
//

import Foundation
import XCTest

final class BPLocalizationParityTests: XCTestCase, @unchecked Sendable {

    private var localizationsDirectory: String {
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return repoRoot.appendingPathComponent("Cakebrew").path
    }

    static func strings(atPath path: String) -> [String: String] {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8),
              !contents.isEmpty else {
            return [:]
        }

        guard let entry = try? NSRegularExpression(
            pattern: "^\"([^\"]+)\"\\s*=\\s*\"((?:[^\"\\\\]|\\\\.)*)\";",
            options: [.anchorsMatchLines]
        ) else {
            return [:]
        }

        let nsContents = contents as NSString
        var strings: [String: String] = [:]
        entry.enumerateMatches(in: contents, options: [], range: NSRange(location: 0, length: nsContents.length)) { match, _, _ in
            guard let match else { return }
            let key = nsContents.substring(with: match.range(at: 1))
            let val = nsContents.substring(with: match.range(at: 2))
            strings[key] = val
        }
        return strings
    }

    static func keysMissing(fromLocale locale: [String: String], comparedTo base: [String: String]) -> [String] {
        var missing: [String] = []
        for key in base.keys {
            if locale[key] == nil {
                missing.append(key)
            }
        }
        return missing.sorted()
    }

    private func localeDirectoryNames() -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: localizationsDirectory)) ?? []
        return entries.filter { $0.hasSuffix(".lproj") }
    }

    func testTheCheckItselfDetectsAMissingKey() {
        let base = ["a": "A", "b": "B"]
        let complete = ["a": "A", "b": "traduit"]
        let incomplete = ["a": "A"]

        XCTAssertEqual(Self.keysMissing(fromLocale: complete, comparedTo: base).count, 0)
        XCTAssertEqual(Self.keysMissing(fromLocale: incomplete, comparedTo: base), ["b"])
    }

    func testTheParserReadsRealEntries() {
        let path = (localizationsDirectory as NSString).appendingPathComponent("en.lproj/Localizable.strings")
        let english = Self.strings(atPath: path)

        XCTAssertGreaterThan(english.count, 100, "the parser should read the whole English file")
        XCTAssertNotNil(english["Sidebar_Item_Services"], "a known key should be present")
    }

    func testDetailPlaceholderAndExportFailureHaveReadableEnglishDefaults() {
        let root = localizationsDirectory as NSString
        for locale in ["en", "de", "fr", "it", "pt", "zh-Hans"] {
            let path = root.appendingPathComponent("\(locale).lproj/Localizable.strings")
            let strings = Self.strings(atPath: path)
            XCTAssertNotNil(strings["Info_View_Empty_Value"], "\(locale) needs the detail placeholder")
            XCTAssertNotNil(strings["Brewfile_Export_Failed"], "\(locale) needs the export failure caption")
            if locale == "en" {
                XCTAssertEqual(strings["Info_View_Empty_Value"], "--")
                XCTAssertEqual(strings["Brewfile_Export_Failed"], "Export Failed")
            }
        }
    }

    func testEveryLocaleCarriesEveryEnglishKey() {
        let root = localizationsDirectory as NSString
        let english = Self.strings(atPath: root.appendingPathComponent("en.lproj/Localizable.strings"))
        XCTAssertGreaterThan(english.count, 0)

        let locales = localeDirectoryNames()
        XCTAssertGreaterThanOrEqual(locales.count, 6, "all six localizations should be scanned")

        var problems: [String] = []
        for locale in locales {
            if locale == "en.lproj" || locale == "Base.lproj" {
                continue
            }
            let path = root.appendingPathComponent((locale as NSString).appendingPathComponent("Localizable.strings"))
            let missing = Self.keysMissing(fromLocale: Self.strings(atPath: path), comparedTo: english)
            if !missing.isEmpty {
                problems.append("\(locale) is missing: \(missing.joined(separator: ", "))")
            }
        }

        XCTAssertEqual(
            problems.count,
            0,
            "a missing key renders as the raw key name on screen, not as English:\n\(problems.joined(separator: "\n"))"
        )
    }

    private func bundle(forLocale locale: String) -> Bundle? {
        Bundle(path: (localizationsDirectory as NSString).appendingPathComponent("\(locale).lproj"))
    }

    func testGermanBrewfileResourcesAreTranslated() {
        let german = bundle(forLocale: "de")
        let english = bundle(forLocale: "en")
        XCTAssertNotNil(german)
        XCTAssertNotNil(english)
        let missing = "__CAKEBREW_MISSING_TRANSLATION__"
        XCTAssertEqual(german?.localizedString(forKey: "__unknown_brewfile_key__", value: missing, table: "Localizable"), missing)
        let keys = [
            "Line %lu: unsupported syntax or invalid package name. Nothing will be installed.",
            "Choose a readable UTF-8 Brewfile smaller than 1 MiB. Nothing was installed.",
            "%lu installed • %lu missing • %lu not checked",
            "Installed",
            "Missing",
            "Not checked",
            "No supported package entries. Nothing will be installed.",
            "Reviewed import requires the standard, non-sandboxed Cakebrew app. Helper transport is not supported.",
            "Review Brewfile",
            "Direct entries only, not a dependency or upgrade plan. Installed means present in the current inventory, not up to date. Homebrew may upgrade packages, install dependencies and required tools, and run package installation scripts. Only the reviewed literal entries will be submitted.",
            "Install Reviewed Entries",
            "Cancel",
            "Close",
            "Import Brewfile",
            "Import cancelled. Some changes may already have been made.",
            "Import finished.",
            "Import failed. Review the output for details.",
            "Cancelling… Waiting for Homebrew to exit.",
            "Brewfile_Export_Failed",
            "Homebrew could not export the Brewfile. Check the destination and try again."
        ]
        for key in keys {
            let translated = german?.localizedString(forKey: key, value: missing, table: "Localizable") ?? missing
            let original = english?.localizedString(forKey: key, value: missing, table: "Localizable") ?? missing
            XCTAssertNotEqual(translated, missing, key)
            XCTAssertNotEqual(original, missing, key)
            XCTAssertGreaterThan(translated.trimmingCharacters(in: .whitespacesAndNewlines).count, 0, key)
            XCTAssertNotEqual(translated, original, "German Brewfile text still uses English: \(key)")
        }
    }

    func testGermanBrewfileFormatsPreserveUnsignedArguments() {
        let german = bundle(forLocale: "de")
        let english = bundle(forLocale: "en")
        let keys = [
            "Line %lu: unsupported syntax or invalid package name. Nothing will be installed.",
            "%lu installed • %lu missing • %lu not checked"
        ]
        for key in keys {
            let format = german?.localizedString(forKey: key, value: "MISSING", table: "Localizable") ?? "MISSING"
            let original = english?.localizedString(forKey: key, value: "MISSING", table: "Localizable") ?? "MISSING"
            let parts = format.components(separatedBy: "%lu")
            let originalParts = original.components(separatedBy: "%lu")
            XCTAssertEqual(parts.count, originalParts.count)
            XCTAssertFalse(parts.joined().contains("%"))
            if parts.count != originalParts.count || parts.joined().contains("%") { continue }
            let rendered = parts.count == 2
                ? String(format: format, UInt(23))
                : String(format: format, UInt(2), UInt(3), UInt(5))
            XCTAssertFalse(rendered.contains("%"))
            let numbers = try? NSRegularExpression(pattern: "[0-9]+", options: [])
            let nsRendered = rendered as NSString
            let matches = numbers?.matches(in: rendered, options: [], range: NSRange(location: 0, length: nsRendered.length)) ?? []
            let values = matches.map { nsRendered.substring(with: $0.range) }
            XCTAssertEqual(values, parts.count == 2 ? ["23"] : ["2", "3", "5"])
        }
    }

    func testAllNonEnglishLocalesTranslateCoreBacklogWorkflows() {
        let english = bundle(forLocale: "en")
        XCTAssertNotNil(english)
        let missing = "__CAKEBREW_MISSING_TRANSLATION__"
        let keys = [
            "Empty_Search_Title",
            "Empty_Search_Message",
            "Empty_Outdated_Title",
            "Empty_Outdated_Message",
            "Empty_Pinned_Title",
            "Empty_Services_Title",
            "Empty_Casks_Title",
            "Empty_Leaves_Title",
            "Cleanup_Nothing_Title",
            "Confirmation_Cleanup",
            "Dock_Check_For_Updates",
            "Dock_Upgrade_All_Outdated",
            "Loading_Status_Default",
            "Loading_Status_AllCasks",
            "Toolbar_Cancel_Reload",
            "Try Again",
            "Homebrew wasn’t found",
            "Review Brewfile",
            "Install Reviewed Entries",
            "Services_Details_Title",
            "Services_Reveal_File",
            "Remove Unused Dependencies",
            "Checking unused dependencies…",
            "Remove Reviewed Dependencies",
            "Updates_Confirm_Title",
            "Updates_Confirm_Action",
            "Information_Title",
            "Information_Unavailable"
        ]

        for locale in ["de", "fr", "it", "pt", "zh-Hans"] {
            let bundle = bundle(forLocale: locale)
            XCTAssertNotNil(bundle, "Missing bundle for \(locale)")
            for key in keys {
                let translated = bundle?.localizedString(forKey: key, value: missing, table: "Localizable") ?? missing
                let original = english?.localizedString(forKey: key, value: missing, table: "Localizable") ?? missing
                XCTAssertNotEqual(translated, missing, "\(locale) missing \(key)")
                XCTAssertNotEqual(translated, original, "\(locale) still uses English placeholder for \(key)")
            }
        }
    }
}
