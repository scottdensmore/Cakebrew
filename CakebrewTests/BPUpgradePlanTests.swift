//
//  BPUpgradePlanTests.swift
//  CakebrewTests
//

import ObjectiveC
import XCTest

final class BPUpgradePlanTests: XCTestCase, @unchecked Sendable {

    private func formula(_ name: String, cask: Bool) -> BPFormula {
        let formula = BPFormula.formula(withName: name)
        formula.cask = cask
        return formula
    }

    private func mixedSelection() -> [BPFormula] {
        [
            formula("shared", cask: true),
            formula("shared", cask: false),
            formula("tap/repo/other", cask: false),
            formula("browser", cask: true)
        ]
    }

    private func commands(forSelection selection: [BPFormula]) -> [[String]] {
        var commands: [[String]] = []
        let plan = BPUpgradePlan(selection: selection)
        plan.execute(withProgress: Progress(totalUnitCount: 1)) { arguments in
            commands.append(arguments)
            return true
        }
        return commands
    }

    func testFormulaSelectionUsesExplicitNamespaceAndPreservesNamesAndOrder() {
        XCTAssertEqual(
            commands(forSelection: [
                formula("wget", cask: false),
                formula("tap/repo/git", cask: false)
            ]),
            [["upgrade", "--formula", "wget", "tap/repo/git"]]
        )
    }

    func testCaskSelectionUsesExplicitNamespace() {
        XCTAssertEqual(
            commands(forSelection: [formula("browser", cask: true)]),
            [["upgrade", "--cask", "browser"]]
        )
    }

    func testMixedSelectionKeepsSameNameInBothNamespacesAndRunsSeparateBatches() {
        XCTAssertEqual(
            commands(forSelection: mixedSelection()),
            [
                ["upgrade", "--formula", "shared", "tap/repo/other"],
                ["upgrade", "--cask", "shared", "browser"]
            ]
        )
    }

    func testEmptySelectionDoesNotRunUpgradeAllOrReportWorkSucceeded() {
        let plan = BPUpgradePlan(selection: [])
        XCTAssertFalse(
            plan.execute(withProgress: Progress(totalUnitCount: 1)) { _ in
                XCTFail("An empty selection must never become bare brew upgrade")
                return true
            }
        )
    }

    func testInvalidNameRejectsEntireSelectionBeforeAnyBatchCanUpgradeAll() {
        for name in ["", " \n\t"] {
            XCTAssertEqual(
                commands(forSelection: [
                    formula("wget", cask: false),
                    formula(name, cask: true)
                ]).count,
                0
            )
        }
    }

    func testPlanSnapshotsSelectionAndNamespaceBeforeExecution() {
        let item = formula("wget", cask: false)
        let selection = NSMutableArray(object: item)
        let plan = BPUpgradePlan(selection: selection as? [Any])
        item.cask = true
        selection.removeAllObjects()
        var calls: UInt = 0
        XCTAssertTrue(
            plan.execute(withProgress: Progress(totalUnitCount: 1)) { arguments in
                calls += 1
                XCTAssertEqual(arguments, ["upgrade", "--formula", "wget"])
                return true
            }
        )
        XCTAssertEqual(calls, 1)
    }

    func testBothSuccessfulBatchesReportSuccess() {
        let plan = BPUpgradePlan(selection: mixedSelection())
        var calls: UInt = 0
        XCTAssertTrue(
            plan.execute(withProgress: Progress(totalUnitCount: 1)) { _ in
                calls += 1
                return true
            }
        )
        XCTAssertEqual(calls, 2)
    }

    func testFirstFailureStopsBeforeLaterBatchAndCannotBecomeSuccess() {
        let plan = BPUpgradePlan(selection: mixedSelection())
        var calls: UInt = 0
        XCTAssertFalse(
            plan.execute(withProgress: Progress(totalUnitCount: 1)) { _ in
                calls += 1
                return calls > 1
            }
        )
        XCTAssertEqual(calls, 1)
    }

    func testLaterFailureMakesAggregateFail() {
        let plan = BPUpgradePlan(selection: mixedSelection())
        var calls: UInt = 0
        XCTAssertFalse(
            plan.execute(withProgress: Progress(totalUnitCount: 1)) { _ in
                calls += 1
                return calls == 1
            }
        )
        XCTAssertEqual(calls, 2)
    }

    func testCancellationBeforeExecutionRunsNothing() {
        let progress = Progress(totalUnitCount: 1)
        progress.cancel()
        let plan = BPUpgradePlan(selection: mixedSelection())
        XCTAssertFalse(
            plan.execute(withProgress: progress) { _ in
                XCTFail("Cancelled plan must not start a batch")
                return true
            }
        )
    }

    func testCancellationBetweenBatchesIsStickyEvenIfCommandReturnsSuccess() {
        let progress = Progress(totalUnitCount: 1)
        let plan = BPUpgradePlan(selection: mixedSelection())
        var calls: UInt = 0
        XCTAssertFalse(
            plan.execute(withProgress: progress) { _ in
                calls += 1
                progress.cancel()
                return true
            }
        )
        XCTAssertEqual(calls, 1)
    }

    func testCancellationDuringFinalBatchCannotReportSuccess() {
        let progress = Progress(totalUnitCount: 1)
        let plan = BPUpgradePlan(selection: mixedSelection())
        var calls: UInt = 0
        XCTAssertFalse(
            plan.execute(withProgress: progress) { _ in
                calls += 1
                if calls == 2 {
                    progress.cancel()
                }
                return true
            }
        )
        XCTAssertEqual(calls, 2)
    }

    private func makeRecorder() -> BPUpgradeInterfaceRecorder {
        let recorder = class_createInstance(BPUpgradeInterfaceRecorder.self, 0) as! BPUpgradeInterfaceRecorder
        recorder.commands = NSMutableArray()
        return recorder
    }

    func testInterfaceExecutesPlanWithSharedTokenStreamsOutputAndReloadsOnlyAfterBatches() {
        let recorder = makeRecorder()
        let progress = Progress(totalUnitCount: 1)
        nonisolated(unsafe) let output = NSMutableString()
        XCTAssertTrue(
            recorder.upgradeSelectedFormulae(mixedSelection(), progress: progress) { chunk in
                output.append(chunk)
            }
        )
        XCTAssertEqual(recorder.commands as? [[String]], commands(forSelection: mixedSelection()))
        XCTAssertEqual(recorder.seenProgress, progress)
        XCTAssertEqual(output as String, "batch output\nbatch output\n")
        XCTAssertEqual(recorder.reloads, 1)
    }

    func testInterfaceDoesNotExecuteOrReloadAnEmptySelection() {
        let recorder = makeRecorder()
        XCTAssertFalse(recorder.upgradeSelectedFormulae([], progress: Progress(totalUnitCount: 1), withReturnBlock: nil))
        XCTAssertEqual(recorder.commands?.count, 0)
        XCTAssertEqual(recorder.reloads, 0)
    }

    func testInterfaceRefreshesPartialChangesAfterFailure() {
        let recorder = makeRecorder()
        recorder.failFirst = true
        XCTAssertFalse(recorder.upgradeSelectedFormulae(mixedSelection(), progress: Progress(totalUnitCount: 1), withReturnBlock: nil))
        XCTAssertEqual(recorder.commands?.count, 1)
        XCTAssertEqual(recorder.reloads, 1)
    }

    func testInterfaceRefreshesPartialChangesAfterCancellationWithoutStartingNextBatch() {
        let recorder = makeRecorder()
        recorder.cancelFirst = true
        XCTAssertFalse(recorder.upgradeSelectedFormulae(mixedSelection(), progress: Progress(totalUnitCount: 1), withReturnBlock: nil))
        XCTAssertEqual(recorder.commands?.count, 1)
        XCTAssertEqual(recorder.reloads, 1)
    }

    func testSnapshotExcludesPinsOnlyInMatchingNamespaceAndFreezesModelScalars() {
        let f = BPFormula.formula(withName: "tap/repo/shared", version: "1", andLatestVersion: "2")
        let c = formula("shared", cask: true)
        let snapshot = BPUpdatesSnapshot(
            generation: 7,
            formulae: [f],
            casks: [c],
            pinnedFormulae: [formula("shared", cask: false)],
            pinnedCasks: []
        )
        f.cask = true
        c.cask = false
        XCTAssertEqual(snapshot?.generation, 7)
        XCTAssertEqual(snapshot?.eligibleFormulae, [])
        XCTAssertEqual(snapshot?.eligibleCasks, ["shared"])
        XCTAssertEqual(snapshot?.excludedFormulae, ["tap/repo/shared"])
        XCTAssertEqual(snapshot?.excludedCasks, [])
        XCTAssertEqual(snapshot?.formulae.first?.version, "1")
        XCTAssertEqual(snapshot?.formulae.first?.latestVersion, "2")
    }

    func testSnapshotTreatsUnavailablePinsDifferentlyFromSuccessfulEmptyAndRejectsEmptyPlan() {
        XCTAssertNil(
            BPUpdatesSnapshot(
                generation: 1,
                formulae: [],
                casks: [],
                pinnedFormulae: [],
                pinnedCasks: nil
            )
        )
        let empty = BPUpdatesSnapshot(
            generation: 1,
            formulae: [],
            casks: [],
            pinnedFormulae: [],
            pinnedCasks: []
        )
        XCTAssertNotNil(empty)
        XCTAssertEqual(empty?.hasEligibleUpdates, false)
        let pinned = BPUpdatesSnapshot(
            generation: 1,
            formulae: [formula("wget", cask: false)],
            casks: [],
            pinnedFormulae: [formula("wget", cask: false)],
            pinnedCasks: []
        )
        XCTAssertEqual(pinned?.hasEligibleUpdates, false)
    }

    func testManagerWaitsForFourSameGenerationInputsAndFreezesOnArrival() {
        let manager = class_createInstance(BPHomebrewManager.self, 0) as! BPHomebrewManager
        let f = formula("wget", cask: false)
        manager.publishList([f], forMode: .outdated, generation: 0)
        f.cask = true
        manager.publishList([], forMode: .outdatedCasks, generation: 0)
        manager.publishList([], forMode: .pinned, generation: 0)
        XCTAssertNil(manager.updatesSnapshot)
        manager.publishPinnedCasks([], generation: 0)
        XCTAssertEqual(manager.updatesSnapshot?.eligibleFormulae, ["wget"])
        manager.publishList(nil, forMode: .allCasks, generation: 0)
        XCTAssertNotNil(manager.updatesSnapshot, "Catalog failure does not invalidate four successful update inputs")
        manager.setValue(NSNumber(value: 1), forKey: "reloadGeneration")
        XCTAssertNil(manager.updatesSnapshot)
        manager.publishPinnedCasks([], generation: 0)
        manager.publishList([], forMode: .outdatedCasks, generation: 1)
        XCTAssertNil(manager.updatesSnapshot)
    }

    func testBatchResultsPreservePartialSuccessAndUnattemptedWork() {
        let plan = BPUpgradePlan(selection: mixedSelection())
        var calls: UInt = 0
        var result = plan.executeReporting(withProgress: Progress(totalUnitCount: 1)) { _ in
            calls += 1
            return calls == 1
        }
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.batches[0].status, .succeeded)
        XCTAssertEqual(result.batches[1].status, .failed)
        result = plan.executeReporting(withProgress: Progress(totalUnitCount: 1)) { _ in
            false
        }
        XCTAssertEqual(result.batches[0].status, .failed)
        XCTAssertEqual(result.batches[1].status, .unattempted)
    }

    func testBatchCancellationIsDistinctFromFailureAndDoesNotLaunchLaterWork() {
        let plan = BPUpgradePlan(selection: mixedSelection())
        let progress = Progress(totalUnitCount: 1)
        var result = plan.executeReporting(withProgress: progress) { _ in
            progress.cancel()
            return true
        }
        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.batches[0].status, .cancelled)
        XCTAssertEqual(result.batches[1].status, .unattempted)
        result = plan.executeReporting(withProgress: progress) { _ in
            XCTFail("Cancelled before dispatch")
            return true
        }
        XCTAssertEqual(result.batches[0].status, .unattempted)
        XCTAssertFalse(result.attempted)
    }

    func testConfirmedSelectionRejectsSupersededAndReplacedSnapshots() {
        let manager = class_createInstance(BPHomebrewManager.self, 0) as! BPHomebrewManager
        manager.publishList([formula("wget", cask: false)], forMode: .outdated, generation: 0)
        manager.publishList([], forMode: .outdatedCasks, generation: 0)
        manager.publishList([], forMode: .pinned, generation: 0)
        manager.publishPinnedCasks([], generation: 0)
        let reviewed = manager.updatesSnapshot
        XCTAssertEqual(manager.selection(forConfirmedUpdatesSnapshot: reviewed)?.compactMap(\.name), ["wget"])
        manager.publishList([], forMode: .outdated, generation: 0)
        XCTAssertNil(manager.selection(forConfirmedUpdatesSnapshot: reviewed))
        manager.setValue(NSNumber(value: 1), forKey: "reloadGeneration")
        XCTAssertNil(manager.selection(forConfirmedUpdatesSnapshot: manager.updatesSnapshot))
    }

    func testSuccessfulCaskPinInventoryDoesNotExcludeSameNamedFormula() {
        let snapshot = BPUpdatesSnapshot(
            generation: 1,
            formulae: [formula("shared", cask: false)],
            casks: [formula("tap/cask/shared", cask: true)],
            pinnedFormulae: [],
            pinnedCasks: [formula("shared", cask: true)]
        )
        XCTAssertEqual(snapshot?.eligibleFormulae, ["shared"])
        XCTAssertEqual(snapshot?.excludedCasks, ["tap/cask/shared"])
    }

    func testUpdateAndPinInventoryQueriesPreserveFailureEvenWithPlausibleOutput() {
        let reader = class_createInstance(BPUpdatesReadRecorder.self, 0) as! BPUpdatesReadRecorder
        for mode: BPListMode in [.outdated, .outdatedCasks, .pinned] {
            reader.readSucceeded = false
            reader.readOutput = "wget\n"
            XCTAssertNil(reader.listMode(mode))
            reader.readSucceeded = true
            reader.readOutput = ""
            XCTAssertEqual(reader.listMode(mode), [])
            let args = reader.readArguments as? [String] ?? []
            XCTAssertTrue(args.contains(mode == .outdatedCasks ? "--cask" : "--formula"))
        }
        reader.readSucceeded = false
        reader.readOutput = "browser\n"
        XCTAssertNil(reader.listPinnedCasks())
        reader.readSucceeded = true
        reader.readOutput = ""
        XCTAssertEqual(reader.listPinnedCasks(), [])
        XCTAssertEqual(reader.readArguments as? [String], ["list", "--cask", "--pinned"])
    }
}
