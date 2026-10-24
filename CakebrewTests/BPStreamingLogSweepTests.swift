//
//  BPStreamingLogSweepTests.swift
//  CakebrewTests
//
//  #69 replaced the per-chunk `setString:` rebuild in three streaming log
//  views, but missed a fourth: BPBundleWindowController lives in Cakebrew/
//  rather than Cakebrew/Controllers/, so the sweep that found the others
//  skipped it and it kept blocking the producer thread on the main thread for
//  every chunk of `brew bundle` output.
//
//  A sweep over the whole target is the guard that would have caught it, so
//  that is what this is: no streaming path may rebuild its document.
//

import XCTest

final class BPStreamingLogSweepTests: XCTestCase, @unchecked Sendable {

    private var sourceRoot: String {
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return repoRoot.appendingPathComponent("Cakebrew").path
    }

    /// Every "file:line  text" in the app sources matching `pattern`.
    private func occurrences(of pattern: String) -> [String] {
        let root = sourceRoot
        let walker = FileManager.default.enumerator(atPath: root)
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        var hits: [String] = []
        var scanned: UInt = 0

        while let relative = walker?.nextObject() as? String {
            let ext = (relative as NSString).pathExtension
            if ext != "m" && ext != "swift" {
                continue
            }
            scanned += 1
            let path = (root as NSString).appendingPathComponent(relative)
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
                continue
            }
            var lineNumber: UInt = 0
            (contents as NSString).enumerateLines { line, _ in
                lineNumber += 1
                let nsLine = line as NSString
                if (regex?.numberOfMatches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) ?? 0) > 0 {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    hits.append("\(relative):\(lineNumber)  \(trimmed)")
                }
            }
        }

        XCTAssertGreaterThan(scanned, 20, "the sweep should reach the whole target, not a subdirectory")
        return hits
    }

    func testNoStreamingPathRebuildsItsDocumentOnTheMainThread() {
        // The exact shape of the defect: hand the whole accumulated transcript back
        // to the view, synchronously, from the thread producing it.
        let hits = occurrences(of: "performSelectorOnMainThread:@selector\\(setString:\\)")

        XCTAssertEqual(
            hits.count,
            0,
            "a streaming view is rebuilding its document per chunk:\n\(hits.joined(separator: "\n"))\nUse -[BPAutoScrollTextView appendOutput:] instead."
        )
    }

    func testNoStreamingPathAppendsToItsOwnStringValue() {
        // The other form the defect took: read the view's whole string, append, set
        // it back — quadratic, and it resets VoiceOver's cursor to the top.
        let hits = occurrences(of: "setString:\\[.*\\.string stringByAppendingString:")

        XCTAssertEqual(
            hits.count,
            0,
            "a streaming view is rebuilding its document per chunk:\n\(hits.joined(separator: "\n"))"
        )
    }
}
