import XCTest
import Foundation

final class BPFormulaOptionTests: XCTestCase, @unchecked Sendable {

    func testSupportsSecureCoding() {
        XCTAssertTrue(BPFormulaOption.supportsSecureCoding)
    }

    func testCopyPreservesNameAndExplanation() {
        let option = BPFormulaOption()
        option.name = "--with-foo"
        option.explanation = "Build with foo support"

        let copy = option.copy() as? BPFormulaOption

        XCTAssertNotNil(copy)
        XCTAssertFalse(copy === option, "copy should be a distinct instance")
        XCTAssertEqual(copy?.name, "--with-foo")
        XCTAssertEqual(copy?.explanation, "Build with foo support")
    }

    func testSecureCodingRoundTrip() throws {
        let option = BPFormulaOption()
        option.name = "--HEAD"
        option.explanation = "Install HEAD version"

        let data = try NSKeyedArchiver.archivedData(withRootObject: option, requiringSecureCoding: true)
        XCTAssertNotNil(data)

        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: BPFormulaOption.self, from: data)
        XCTAssertEqual(decoded?.name, "--HEAD")
        XCTAssertEqual(decoded?.explanation, "Install HEAD version")
    }

    func testSecureCodingPreservesNilFields() throws {
        // A bare option (no name/explanation) must round-trip without error.
        let option = BPFormulaOption()

        let data = try NSKeyedArchiver.archivedData(withRootObject: option, requiringSecureCoding: true)

        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: BPFormulaOption.self, from: data)
        XCTAssertNil(decoded?.name)
        XCTAssertNil(decoded?.explanation)
    }
}
