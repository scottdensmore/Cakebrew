//
//  BPMockFidelityTests.swift
//  CakebrewTests
//
//  The testing invariant: every interface method gets a mock override
//  so UI tests never shell out to real brew. It was quietly false for most
//  formula-side mutating operations, which inherited the real implementations
//  and would have executed brew for real.
//
//  Nothing tripped it only because every mutating journey pressed Cancel at the
//  confirmation sheet. A maintainer doing the step-3 visual review who clicked
//  Tap in the mock build really tapped a repository.
//
//  So the rule enforces itself here: a mutating selector without its own mock
//  implementation fails, including one added tomorrow.
//

import ObjectiveC
import XCTest

#if DEBUG
// The fixture implementation is intentionally absent from Release binaries.
private final class CBCatalogCompletionObserver: NSObject, BPHomebrewManagerDelegate, @unchecked Sendable {
    @objc dynamic var finishes: UInt = 0
    var finished: XCTestExpectation?

    func homebrewManager(_ manager: BPHomebrewManager, didUpdateSearchResults results: [Any]?) {}

    func homebrewManager(_ manager: BPHomebrewManager, shouldDisplayNoBrewMessage show: Bool) {
        XCTAssertFalse(show)
    }

    func homebrewManagerFinishedUpdating(_ manager: BPHomebrewManager) {
        XCTAssertTrue(Thread.isMainThread)
        finishes += 1
        finished?.fulfill()
    }
}
#endif

final class BPMockFidelityTests: XCTestCase, @unchecked Sendable {

    /// Selectors that run brew in a way that changes the machine's state. Anything
    /// added to BPHomebrewInterface that mutates belongs here.
    private var mutatingSelectorNames: [String] {
        [
            "updateWithReturnBlock:",
            "previewAutoremoveWithProgress:",
            "listModeForRemovalRefresh:",
            "listServicesForRemovalRefresh",
            "removeUnusedFormulae:progress:output:",
            "upgradeFormulae:withReturnBlock:",
            "upgradeSelectedFormulae:progress:withReturnBlock:",
            "upgradeSelectionReporting:progress:withReturnBlock:",
            "listPinnedCasks",
            "upgradeCasks:withReturnBlock:",
            "installFormula:withOptions:andReturnBlock:",
            "installCask:withReturnBlock:",
            "uninstallFormula:withReturnBlock:",
            "uninstallCask:withReturnBlock:",
            "uninstallCask:zap:withReturnBlock:",
            "tapRepository:withReturnsBlock:",
            "untapRepository:withReturnsBlock:",
            "pinFormula:withReturnBlock:",
            "unpinFormula:withReturnBlock:",
            "runCleanupWithReturnBlock:",
            "runDoctorWithReturnBlock:",
            "runBrewExportToolWithPath:",
            "runBrewImportToolWithPath:withReturnsBlock:",
            "runBrewImportToolWithPath:progress:withReturnsBlock:",
            "startService:withReturnBlock:",
            "stopService:withReturnBlock:",
            "restartService:withReturnBlock:"
        ]
    }

    private func mockClass() -> AnyClass? {
        let mock: AnyClass? = NSClassFromString("BPMockHomebrewInterface")
        XCTAssertNotNil(mock, "the mock must be compiled into this (Debug) build")
        return mock
    }

    func testEveryMutatingSelectorExistsOnTheRealInterface() {
        // Guards the list itself: a renamed selector must not silently stop being
        // checked.
        for name in mutatingSelectorNames {
            let selector = NSSelectorFromString(name)
            XCTAssertTrue(
                BPHomebrewInterface.instancesRespond(to: selector),
                "\(name) no longer exists — update the list"
            )
        }
    }

    func testTheMockOverridesEveryMutatingSelector() {
        guard let mock = mockClass() else { return }
        var inherited: [String] = []

        for name in mutatingSelectorNames {
            let selector = NSSelectorFromString(name)
            // Responding is not enough — it would inherit the real implementation.
            // The mock must supply its own.
            let mockMethod = class_getInstanceMethod(mock, selector)
            let realMethod = class_getInstanceMethod(BPHomebrewInterface.self, selector)
            if mockMethod == realMethod {
                inherited.append(name)
            }
        }

        XCTAssertEqual(
            inherited.count,
            0,
            "these would shell out to real brew under -BPMockBrew:\n\(inherited.joined(separator: "\n"))"
        )
    }

    #if DEBUG
    private func importFixture(withArguments arguments: [String]) -> CBHeldImportInterface {
        let mock = CBHeldImportInterface(uniqueInstance: ())
        mock.arguments = NSSet(array: arguments)
        mock.pauseCondition = NSCondition()
        return mock
    }

    private func assertHeldImport(_ mock: CBHeldImportInterface, nilOutput: Bool) {
        let progress = Progress(totalUnitCount: 1)
        nonisolated(unsafe) let output = NSMutableString()
        nonisolated(unsafe) var success = true
        let finished = XCTestExpectation(description: "import worker drained")
        mock.returned = false
        mock.pauseCount = 0
        mock.pauseReleased = false
        DispatchQueue.global(qos: .userInitiated).async {
            let receive: (@Sendable (String) -> Void)?
            if nilOutput {
                receive = nil
            } else {
                receive = { text in
                    output.append(text)
                }
            }
            success = mock.runBrewImportTool(
                withPath: "/fixture/Brewfile",
                progress: progress,
                withReturnsBlock: receive
            )
            mock.returned = true
            finished.fulfill()
        }
        do {
            defer {
                progress.cancel()
                mock.releasePause() // Durable even when cancellation precedes worker arrival.
                XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 2), .completed)
            }
            let observed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "pauseCount > 0 OR returned == YES"),
                object: mock
            )
            XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 2), .completed)
            XCTAssertEqual(mock.pauseCount, 1, "held import must ignore an expired slow deadline and reach its poll")
            XCTAssertFalse(mock.returned, "held import cannot succeed before its own progress is cancelled")
        }
        XCTAssertTrue(progress.isCancelled)
        XCTAssertFalse(success)
        if !nilOutput {
            XCTAssertEqual(output as String, "MOCK_IMPORT_STARTED\nMOCK_IMPORT_CANCELLED\n")
        }
    }

    func testHeldBrewfileImportIgnoresExpiredDeadlineAndUsesEachOperationsProgress() {
        let mock = importFixture(withArguments: ["-BPMockHoldBrewfileImportUntilCancelled", "-BPMockSlowBrewfileImport"])
        assertHeldImport(mock, nilOutput: false)
        // A cancelled operation must not release or cancel a subsequent operation.
        assertHeldImport(mock, nilOutput: false)
    }

    func testHeldBrewfileImportAcceptsNilOutput() {
        let mock = importFixture(withArguments: ["-BPMockHoldBrewfileImportUntilCancelled"])
        assertHeldImport(mock, nilOutput: true)
    }

    func testBrewfileImportHonorsCancellationBeforeStartAndFromStartOutput() {
        for beforeStart in [true, false] {
            let mock = importFixture(withArguments: ["-BPMockHoldBrewfileImportUntilCancelled"])
            let progress = Progress(totalUnitCount: 1)
            nonisolated(unsafe) let output = NSMutableString()
            if beforeStart {
                progress.cancel()
            }
            let success = mock.runBrewImportTool(
                withPath: "/fixture/Brewfile",
                progress: progress
            ) { text in
                output.append(text)
                progress.cancel()
            }
            XCTAssertFalse(success)
            XCTAssertEqual(mock.pauseCount, 0)
            XCTAssertEqual(output as String, beforeStart ? "" : "MOCK_IMPORT_STARTED\nMOCK_IMPORT_CANCELLED\n")
        }
    }

    func testBrewfileImportPreservesSuccessFailureAndExpiredSlowCompletion() {
        let allArgumentSets: [[String]] = [
            [],
            ["-BPMockBrewfileImportFails"],
            ["-BPMockSlowBrewfileImport"]
        ]
        for arguments in allArgumentSets {
            let mock = importFixture(withArguments: arguments)
            let progress = Progress(totalUnitCount: 1)
            nonisolated(unsafe) let output = NSMutableString()
            let success = mock.runBrewImportTool(
                withPath: "/fixture/Brewfile",
                progress: progress
            ) { text in
                output.append(text)
            }
            let failure = arguments.contains("-BPMockBrewfileImportFails")
            XCTAssertEqual(success, !failure)
            XCTAssertEqual(mock.pauseCount, 0)
            XCTAssertFalse(progress.isCancelled)
            XCTAssertEqual(
                output as String,
                failure ? "MOCK_IMPORT_STARTED\nMOCK_IMPORT_FAILED\n" : "MOCK_IMPORT_STARTED\nMOCK_IMPORT_OK\n"
            )
        }
    }

    private func startCatalog(_ mode: BPListMode, interface mock: CBHeldCatalogInterface, group: DispatchGroup) {
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            let list = mock.listMode(mode) ?? []
            XCTAssertGreaterThan(list.count, 0)
        }
    }

    @discardableResult
    private func observeWaitingCatalogs(_ count: UInt, interface mock: CBHeldCatalogInterface) -> Bool {
        let arrived = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "observedArrivalCount >= %@", NSNumber(value: count)),
            object: mock.observedCondition
        )
        let result = XCTWaiter.wait(for: [arrived], timeout: 2.0 * Double(count))
        XCTAssertEqual(result, .completed, "catalog workers must reach the condition wait")
        return result == .completed
    }

    private func waitForCatalogGroup(_ group: DispatchGroup) -> Bool {
        let finished = XCTestExpectation(description: "catalog workers finished")
        group.notify(queue: .main) {
            finished.fulfill()
        }
        return XCTWaiter.wait(for: [finished], timeout: 2.0) == .completed
    }

    private func cancelAndDrain(_ mock: CBHeldCatalogInterface, group: DispatchGroup) {
        mock.cancelAllRunningTasks()
        XCTAssertTrue(
            waitForCatalogGroup(group),
            "every worker must finish after cancellation, including failure cleanup"
        )
    }

    func testBothCatalogWorkersStayHeldUntilCancellation() {
        let mock = CBHeldCatalogInterface(uniqueInstance: ())
        let group = DispatchGroup()
        defer {
            cancelAndDrain(mock, group: group)
        }
        startCatalog(.all, interface: mock, group: group)
        startCatalog(.allCasks, interface: mock, group: group)
        // Arrivals can precede observation; the helper must retain both.
        let alreadyArrived = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "observedArrivalCount == 2"),
            object: mock.observedCondition
        )
        XCTAssertEqual(XCTWaiter.wait(for: [alreadyArrived], timeout: 4.0), .completed)
        if observeWaitingCatalogs(2, interface: mock) {
            mock.observedCondition?.lock()
            XCTAssertNotEqual(
                group.wait(timeout: .now()),
                .success,
                "catalogs cannot finish before Stop Reloading"
            )
            mock.observedCondition?.unlock()
        }
    }

    func testCancellationBeforeEitherCatalogArrivesIsRemembered() {
        let mock = CBHeldCatalogInterface(uniqueInstance: ())
        let group = DispatchGroup()
        defer {
            cancelAndDrain(mock, group: group)
        }
        mock.cancelAllRunningTasks()
        startCatalog(.all, interface: mock, group: group)
        startCatalog(.allCasks, interface: mock, group: group)
        XCTAssertTrue(waitForCatalogGroup(group))
    }

    func testCancellationReleasesEarlyCatalogAndDoesNotHoldLateCatalog() {
        let mock = CBHeldCatalogInterface(uniqueInstance: ())
        let group = DispatchGroup()
        defer {
            cancelAndDrain(mock, group: group)
        }
        startCatalog(.all, interface: mock, group: group)
        observeWaitingCatalogs(1, interface: mock)
        mock.cancelAllRunningTasks()
        startCatalog(.allCasks, interface: mock, group: group)
        XCTAssertTrue(waitForCatalogGroup(group))
    }

    func testRepeatedCancellationAndLaterReloadsNeverRearmTheHold() {
        let mock = CBHeldCatalogInterface(uniqueInstance: ())
        // The explicit cancellation fixture must take precedence over the timed one.
        mock.slowCatalogEnabled = true
        let group = DispatchGroup()
        defer {
            cancelAndDrain(mock, group: group)
        }
        mock.cancelAllRunningTasks()
        mock.cancelAllRunningTasks()
        for _ in 0..<2 {
            startCatalog(.all, interface: mock, group: group)
            startCatalog(.allCasks, interface: mock, group: group)
            XCTAssertTrue(waitForCatalogGroup(group))
        }
    }

    func testNonCatalogListsRemainAvailableWhileCatalogIsHeld() {
        let mock = CBHeldCatalogInterface(uniqueInstance: ())
        let catalogs = DispatchGroup()
        let otherLists = DispatchGroup()
        defer {
            cancelAndDrain(mock, group: catalogs)
            cancelAndDrain(mock, group: otherLists)
        }
        startCatalog(.all, interface: mock, group: catalogs)
        observeWaitingCatalogs(1, interface: mock)
        let nonCatalogModes: [BPListMode] = [
            .installed,
            .outdated,
            .leaves,
            .pinned,
            .repositories,
            .installedCasks,
            .outdatedCasks
        ]
        for mode in nonCatalogModes {
            startCatalog(mode, interface: mock, group: otherLists)
        }
        XCTAssertTrue(waitForCatalogGroup(otherLists))
    }

    func testExplicitReleaseFinishesBothCatalogsWithoutCancellation() {
        let mock = CBHeldCatalogInterface(uniqueInstance: ())
        mock.normalReleaseEnabled = true
        let group = DispatchGroup()
        nonisolated(unsafe) var formulae: [BPFormula]?
        nonisolated(unsafe) var casks: [BPFormula]?
        defer {
            cancelAndDrain(mock, group: group)
        }
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            formulae = mock.listMode(.all)
        }
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            casks = mock.listMode(.allCasks)
        }
        guard observeWaitingCatalogs(2, interface: mock) else { return }
        mock.observedCondition?.lock()
        XCTAssertNotEqual(group.wait(timeout: .now()), .success)
        mock.observedCondition?.unlock()
        mock.releaseHeldCatalogs(nil)
        XCTAssertTrue(waitForCatalogGroup(group))
        XCTAssertEqual(formulae?.compactMap(\.name), ["mockwget", "mockgit", "mockcurl", "mockhtop"])
        XCTAssertEqual(casks?.compactMap(\.name), ["mockchrome", "mockvscode", "mockfirefox"])
        XCTAssertEqual(casks?.first?.cask, true)
        XCTAssertEqual(mock.cancellations, 0)
    }

    func testExplicitReleaseBeforeArrivalAndRepeatedReleaseNeverRearmTheHold() {
        let mock = CBHeldCatalogInterface(uniqueInstance: ())
        mock.normalReleaseEnabled = true
        mock.slowCatalogEnabled = true
        let group = DispatchGroup()
        defer {
            cancelAndDrain(mock, group: group)
        }
        mock.releaseHeldCatalogs(nil)
        mock.releaseHeldCatalogs(nil)
        for _ in 0..<2 {
            startCatalog(.all, interface: mock, group: group)
            startCatalog(.allCasks, interface: mock, group: group)
            XCTAssertTrue(waitForCatalogGroup(group))
        }
        XCTAssertEqual(mock.cancellations, 0)
    }

    func testExplicitReleaseFinishesEarlyAndLateCatalogWorkers() {
        let mock = CBHeldCatalogInterface(uniqueInstance: ())
        mock.normalReleaseEnabled = true
        let group = DispatchGroup()
        defer {
            cancelAndDrain(mock, group: group)
        }
        startCatalog(.all, interface: mock, group: group)
        guard observeWaitingCatalogs(1, interface: mock) else { return }
        mock.releaseHeldCatalogs(nil)
        startCatalog(.allCasks, interface: mock, group: group)
        XCTAssertTrue(waitForCatalogGroup(group))
        XCTAssertEqual(mock.cancellations, 0)
    }

    func testExplicitReleasePublishesNormalManagerCompletionWithoutChangingGeneration() {
        let mock = CBHeldCatalogInterface(uniqueInstance: ())
        mock.normalReleaseEnabled = true
        let manager = CBCatalogCompletionManager(uniqueInstance: ())
        manager.fixture = mock
        let observer = CBCatalogCompletionObserver()
        let finishedExpectation = XCTestExpectation(description: "normal manager completion")
        finishedExpectation.assertForOverFulfill = true
        observer.finished = finishedExpectation
        manager.delegate = observer
        manager.reloadFromInterface(rebuildingCache: true)
        let generation = manager.currentReloadGeneration
        defer {
            // Release on every failure path, then drain the real completion callback.
            mock.cancelAllRunningTasks()
            if observer.finishes == 0 {
                let drained = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "finishes > 0"),
                    object: observer
                )
                XCTAssertEqual(XCTWaiter.wait(for: [drained], timeout: 5), .completed)
            }
        }
        guard observeWaitingCatalogs(2, interface: mock) else { return }
        XCTAssertEqual(observer.finishes, 0)
        mock.releaseHeldCatalogs(nil)
        XCTAssertEqual(XCTWaiter.wait(for: [finishedExpectation], timeout: 5), .completed)
        XCTAssertEqual(observer.finishes, 1)
        XCTAssertEqual(manager.currentReloadGeneration, generation)
        XCTAssertEqual(mock.cancellations, 0)
        XCTAssertEqual(manager.allFormulae?.compactMap(\.name), ["mockwget", "mockgit", "mockcurl", "mockhtop"])
        XCTAssertEqual(manager.allCasks?.compactMap(\.name), ["mockchrome", "mockvscode", "mockfirefox"])
        XCTAssertEqual(manager.allCasks?.first?.cask, true)
    }
    #endif
}
