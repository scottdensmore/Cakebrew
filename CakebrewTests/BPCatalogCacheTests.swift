//
//  BPCatalogCacheTests.swift
//  CakebrewTests
//

import Foundation
import XCTest

final class BPCatalogCacheTests: XCTestCase, @unchecked Sendable {
    private var manager: BPHomebrewManager!

    private var cacheFile: URL {
        BPAppDelegate.urlForApplicationCachesFolder()!.appendingPathComponent("allFormulae.cache.bin")
    }

    override func setUp() {
        super.setUp()
        manager = BPHomebrewManager.sharedManager()
        manager.discardCatalogCache()
        manager.allFormulae = []
        manager.allCasks = []
    }

    override func tearDown() {
        manager.discardCatalogCache()
        manager.allFormulae = []
        manager.allCasks = []
        manager = nil
        super.tearDown()
    }

    func testAFreshlyStoredCacheLoadsBack() {
        manager.allFormulae = [BPFormula.formula(withName: "wget")]
        manager.allCasks = [BPFormula.formula(withName: "mockchrome")]
        manager.storeAllFormulaeCaches()

        manager.allFormulae = []
        manager.allCasks = []

        XCTAssertTrue(manager.loadAllFormulaeCaches())
        XCTAssertEqual(manager.allFormulae?.count, 1)
        XCTAssertEqual(manager.allCasks?.count, 1)
    }

    func testNoCacheFileMeansNoCacheEvenWithArraysPopulated() {
        manager.allFormulae = [BPFormula.formula(withName: "wget")]
        manager.discardCatalogCache()

        XCTAssertFalse(
            manager.loadAllFormulaeCaches(),
            "a deleted cache is not a valid one, whatever is in memory"
        )
    }

    func testAnExpiredCacheIsNotReportedAsValid() throws {
        manager.allFormulae = [BPFormula.formula(withName: "wget")]
        manager.storeAllFormulaeCaches()

        let data = try Data(contentsOf: cacheFile)
        let classes: [AnyClass] = [
            NSDictionary.self, NSArray.self, NSMutableArray.self,
            BPFormula.self, NSString.self, NSURL.self,
            NSNumber.self, NSDate.self
        ]
        guard let unarchived = try NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data) as? NSDictionary else {
            XCTFail("failed to unarchive cache")
            return
        }
        let dict = NSMutableDictionary(dictionary: unarchived)
        dict["BPCacheStoredDateKey"] = Date(timeIntervalSinceNow: -(3600 * 25))
        let stale = try NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: true)
        try stale.write(to: cacheFile, options: .atomic)

        XCTAssertFalse(manager.loadAllFormulaeCaches(), "25 hours old is stale")
    }

    func testAVersionMismatchRebuildsRatherThanDecodingIntoTheWrongFields() throws {
        manager.allFormulae = [BPFormula.formula(withName: "wget")]
        manager.storeAllFormulaeCaches()

        let data = try Data(contentsOf: cacheFile)
        let classes: [AnyClass] = [
            NSDictionary.self, NSArray.self, NSMutableArray.self,
            BPFormula.self, NSString.self, NSURL.self,
            NSNumber.self, NSDate.self
        ]
        guard let unarchived = try NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data) as? NSDictionary else {
            XCTFail("failed to unarchive cache")
            return
        }
        let dict = NSMutableDictionary(dictionary: unarchived)
        dict["BPCacheVersionKey"] = NSNumber(value: 999)
        let wrongVersion = try NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: true)
        try wrongVersion.write(to: cacheFile, options: .atomic)

        XCTAssertFalse(manager.loadAllFormulaeCaches())
    }

    func testATruncatedArchiveIsDiscardedRatherThanCrashing() throws {
        try Data("garbage".utf8).write(to: cacheFile, options: .atomic)

        XCTAssertFalse(manager.loadAllFormulaeCaches())
    }

    func testARebuildIsStampedWithTheCurrentTime() {
        manager.allFormulae = [BPFormula.formula(withName: "wget")]
        manager.storeAllFormulaeCaches()

        let firstStamp = UserDefaults.standard.integer(forKey: kBPCacheLastUpdateKey)
        XCTAssertGreaterThan(firstStamp, 0)

        UserDefaults.standard.set(Int(Date().timeIntervalSince1970 - 3600 * 30), forKey: kBPCacheLastUpdateKey)
        manager.storeAllFormulaeCaches()

        let age = Date().timeIntervalSince1970 - TimeInterval(UserDefaults.standard.integer(forKey: kBPCacheLastUpdateKey))
        XCTAssertLessThan(age, 60.0, "a rebuild must be stamped now, not with the previous date")

        XCTAssertTrue(manager.loadAllFormulaeCaches(), "and must therefore still be valid")
    }
}
