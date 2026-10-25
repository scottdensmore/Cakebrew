import Foundation
import XCTest

/// Prevent resource-based interfaces from returning during future feature work.
final class BPSwiftUIArchitectureTests: XCTestCase, @unchecked Sendable {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    func testApplicationContainsNoInterfaceBuilderResources() throws {
        let source = root.appendingPathComponent("Cakebrew")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil))
        let obsolete = files.compactMap { $0 as? URL }.filter { ["xib", "nib", "storyboard"].contains($0.pathExtension) }
        XCTAssertTrue(obsolete.isEmpty, "Remove Interface Builder resources: \(obsolete)")
        let data = try Data(contentsOf: source.appendingPathComponent("Cakebrew-Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertNil(plist["NSMainNibFile"])
        XCTAssertNil(plist["NSMainStoryboardFile"])
    }

    func testSwiftUISurfacesDoNotEmbedAppKitViews() throws {
        let source = root.appendingPathComponent("Cakebrew")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(text.contains(": NSViewRepresentable"), url.lastPathComponent)
            XCTAssertFalse(text.contains(": NSViewControllerRepresentable"), url.lastPathComponent)
        }
    }

    func testBuildUsesSwift6AndHasNoInterfaceBuilderBuildInputs() throws {
        let project = try String(contentsOf: root.appendingPathComponent("Cakebrew.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertTrue(project.contains("SWIFT_VERSION = 6.0"))
        XCTAssertFalse(project.contains(".xib"))
        XCTAssertFalse(project.contains(".nib"))
    }
}
