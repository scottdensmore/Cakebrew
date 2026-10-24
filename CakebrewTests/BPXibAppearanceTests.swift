//
//  BPXibAppearanceTests.swift
//  CakebrewTests
//

import Foundation
import XCTest

final class BPXibAppearanceTests: XCTestCase, @unchecked Sendable {

    private var baseLprojPath: String {
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return repoRoot.appendingPathComponent("Cakebrew/Base.lproj").path
    }

    private func xibPaths() -> [String] {
        let dir = baseLprojPath
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        XCTAssertFalse(entries.isEmpty, "could not locate Base.lproj at \(dir)")

        var paths: [String] = []
        for entry in entries where (entry as NSString).pathExtension == "xib" {
            paths.append((dir as NSString).appendingPathComponent(entry))
        }
        XCTAssertFalse(paths.isEmpty, "no xibs found in \(dir)")
        return paths
    }

    private func offendingLinesMatching(_ pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        var offenders: [String] = []

        for path in xibPaths() {
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            var lineNumber: UInt = 0
            (contents as NSString).enumerateLines { line, _ in
                lineNumber += 1
                let nsLine = line as NSString
                if regex.numberOfMatches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) > 0 {
                    let file = (path as NSString).lastPathComponent
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    offenders.append("\(file):\(lineNumber)  \(trimmed)")
                }
            }
        }
        return offenders
    }

    func testNoOpaqueWhiteFillsRemain() {
        let offenders = offendingLinesMatching("white=\"1\" alpha=\"1\"")

        XCTAssertEqual(
            offenders.count,
            0,
            "opaque white is pinned in:\n\(offenders.joined(separator: "\n"))\nUse a semantic color such as textBackgroundColor."
        )
    }

    func testNoAbsoluteTextColorsRemain() {
        let offenders = offendingLinesMatching("key=\"textColor\".*colorSpace=\"calibratedWhite\"")

        XCTAssertEqual(
            offenders.count,
            0,
            "absolute text colors are pinned in:\n\(offenders.joined(separator: "\n"))\nUse secondaryLabelColor or labelColor."
        )
    }

    func testTheScanActuallySeesTheXibs() {
        let paths = xibPaths()
        XCTAssertGreaterThanOrEqual(paths.count, 7, "expected every Base.lproj xib to be scanned")

        let anyColour = offendingLinesMatching("<color key=")
        XCTAssertGreaterThan(anyColour.count, 0, "the scan found no colors at all, so it is not reading the xibs")
    }
}
