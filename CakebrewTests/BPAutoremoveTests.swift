import XCTest
import AppKit
import Foundation

private final class CB150Observer: NSObject {
    var observed: (() -> Void)?

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        observed?()
    }
}

@MainActor
final class BPAutoremoveTests: XCTestCase, @unchecked Sendable {

    private func refreshShellInterface() -> CB150RefreshShellInterface {
        let interface = CB150RefreshShellInterface(uniqueInstance: ())
        interface.brewTransport = .direct
        interface.setValue("/bin/sh", forKey: "path_shell")
        interface.commands = NSMutableArray()
        return interface
    }

    func testAutoremoveRealFailedRefreshPreservesListsAndReportsIncomplete() {
        let manager = CB150Manager(uniqueInstance: ())
        let interface = refreshShellInterface()
        manager.fixtureInterface = interface
        interface.outputs = [
            "leaves": "freshleaf\n",
            "outdated --formula --verbose": "partial (1) < 2\n"
        ]
        interface.statuses = [
            "list --versions": 7,
            "outdated --formula --verbose": 8,
            "services list --json": 9
        ]
        let kept = [BPFormula.formula(withName: "kept")]
        manager.installedFormulae = kept
        manager.leavesFormulae = kept
        manager.publishList(kept, forMode: .outdated, generation: manager.currentReloadGeneration)
        manager.publishList(kept, forMode: .outdatedCasks, generation: manager.currentReloadGeneration)
        let services = BPService.services(fromJSONString: "[{\"name\":\"kept-service\"}]")
        manager.services = services

        nonisolated(unsafe) var snapshots: UInt = 0
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(BPHomebrewManagerDidPublishOutdatedSnapshotNotification),
            object: manager,
            queue: nil
        ) { _ in
            snapshots += 1
        }
        let done = expectation(description: "failed transport reports incomplete refresh")
        manager.refreshFormulaStateAfterRemoval { ok in
            XCTAssertFalse(ok, "The sheet must receive NO to show its incomplete-refresh warning")
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        NotificationCenter.default.removeObserver(observer)

        XCTAssertEqual(manager.installedFormulae, kept)
        XCTAssertEqual(manager.outdatedFormulae, kept)
        XCTAssertEqual(manager.services, services)
        XCTAssertEqual(manager.leavesFormulae?.first?.name, "freshleaf")
        XCTAssertEqual(snapshots, 0, "A failed outdated query cannot publish a new zero or partial count")
        let expectedCommands: NSArray = [
            "list --versions",
            "leaves",
            "outdated --formula --verbose",
            "services list --json"
        ]
        XCTAssertEqual(interface.commands, expectedCommands)
    }

    func testAutoremoveRefreshReadsPreserveProcessFailureAndSuccessfulEmptyResults() {
        let interface = refreshShellInterface()
        let keys = ["list --versions", "leaves", "outdated --formula --verbose"]
        let modes: [BPListMode] = [.installed, .leaves, .outdated]
        let samples = ["newformula 1.2\n", "newleaf\n", "newformula (1.0) < 2.0\n"]
        for i in 0..<keys.count {
            for output in ["", samples[i], "failure text\n"] {
                interface.outputs = [keys[i]: output]
                interface.statuses = [keys[i]: 7]
                XCTAssertNil(interface.listMode(forRemovalRefresh: modes[i]))
            }
            interface.statuses = [:]
            interface.outputs = [:]
            XCTAssertEqual(interface.listMode(forRemovalRefresh: modes[i]), [])
            interface.outputs = [keys[i]: samples[i]]
            XCTAssertEqual(interface.listMode(forRemovalRefresh: modes[i])?.count, 1)
        }
        interface.outputs = ["services list --json": "[]"]
        interface.statuses = ["services list --json": 7]
        XCTAssertNil(interface.listServicesForRemovalRefresh())
        interface.statuses = [:]
        XCTAssertEqual(interface.listServicesForRemovalRefresh(), [])
        let requests = interface.commands?.count ?? 0
        XCTAssertNil(interface.listMode(forRemovalRefresh: .allCasks))
        interface.brewTransport = .helper
        XCTAssertNil(interface.listMode(forRemovalRefresh: .installed))
        XCTAssertNil(interface.listServicesForRemovalRefresh())
        XCTAssertEqual(interface.commands?.count ?? 0, requests, "Unsupported reads cannot dispatch or take helper ownership")
    }

    func testAutoremoveServicesRejectMalformedSuccessfulReadsWithoutClearingPriorState() {
        let invalid = [
            "", "not JSON", "{}", "[null]", "[{}]", "[{\"name\":3}]", "[{\"name\":\"\"}]",
            "[{\"name\":\"redis\",\"pid\":\"bad\"}]", "[{\"name\":\"redis\",\"user\":4}]", "[{\"name\":\"redis\",\"status\":{}}]",
            "[{\"name\":\"valid\"},{}]"
        ]
        for output in invalid {
            let manager = CB150Manager(uniqueInstance: ())
            let interface = refreshShellInterface()
            manager.fixtureInterface = interface
            interface.outputs = ["services list --json": output]
            let kept = BPService.services(fromJSONString: "[{\"name\":\"kept\"}]")
            manager.services = kept
            let done = expectation(description: "malformed services reject refresh")
            manager.refreshFormulaStateAfterRemoval { ok in
                XCTAssertFalse(ok, "\(output)")
                done.fulfill()
            }
            wait(for: [done], timeout: 5)
            XCTAssertEqual(manager.services, kept, "\(output)")
        }
    }

    func testAutoremoveSuccessfulEmptyRefreshClearsListsAndPreservesKnownCaskCount() {
        let manager = CB150Manager(uniqueInstance: ())
        let interface = refreshShellInterface()
        manager.fixtureInterface = interface
        interface.outputs = ["services list --json": "[]"]
        let kept = [BPFormula.formula(withName: "old")]
        manager.installedFormulae = kept
        manager.leavesFormulae = kept
        manager.outdatedFormulae = kept
        manager.services = BPService.services(fromJSONString: "[{\"name\":\"old\"}]")
        manager.publishList(kept, forMode: .outdatedCasks, generation: manager.currentReloadGeneration)

        nonisolated(unsafe) var snapshot: [AnyHashable: Any]?
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(BPHomebrewManagerDidPublishOutdatedSnapshotNotification),
            object: manager,
            queue: nil
        ) { note in
            snapshot = note.userInfo
        }
        let done = expectation(description: "genuine empty lists succeed")
        manager.refreshFormulaStateAfterRemoval { ok in
            XCTAssertTrue(ok)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        NotificationCenter.default.removeObserver(observer)

        XCTAssertEqual(manager.installedFormulae, [])
        XCTAssertEqual(manager.leavesFormulae, [])
        XCTAssertEqual(manager.outdatedFormulae, [])
        XCTAssertEqual(manager.services, [])
        XCTAssertEqual(snapshot?[BPOutdatedSnapshotFormulaeCountKey] as? NSNumber, 0)
        XCTAssertEqual(snapshot?[BPOutdatedSnapshotCaskCountKey] as? NSNumber, 1)

        interface.outputs = [
            "services list --json": "[{\"name\":\"redis\",\"status\":\"future\",\"pid\":null,\"user\":null,\"new_field\":{}}]"
        ]
        let services = interface.listServicesForRemovalRefresh()
        XCTAssertEqual(services?.count, 1)
        XCTAssertEqual(services?.first?.status, .unknown)
    }

    func testAutoremoveInvalidReviewAndHelperNeverReachCommands() {
        for helper in [false, true] {
            let interface = CB150Interface(uniqueInstance: ())
            if helper {
                interface.brewTransport = .helper
            }
            let preview = BPAutoremovePreview.preview(
                withOutput: helper ? "==> Would autoremove 1 unneeded formula:\nlibfoo\n" : "unexpected",
                succeeded: true
            )
            let operation = BPAutoremoveOperation(preview: preview, interface: interface)
            let done = expectation(description: "unsafe request rejected")
            operation.start(withOutput: nil) { success, cancelled, attempted, _ in
                XCTAssertFalse(success)
                XCTAssertFalse(cancelled)
                XCTAssertFalse(attempted)
                done.fulfill()
            }
            wait(for: [done], timeout: 5)
            XCTAssertEqual(interface.previewCalls, 0)
            XCTAssertEqual(interface.removalCalls, 0)
        }
    }

    func testAutoremoveDeferredRefreshCompletesWhenDiscoveryFails() {
        let manager = CB150Manager(uniqueInstance: ())
        let interface = CB150RefreshInterface(uniqueInstance: ())
        interface.modes = NSMutableArray()
        manager.fixtureInterface = interface
        interface.finishDiscovery = DispatchSemaphore(value: 0)
        let entered = expectation(description: "discovery entered")
        interface.discoveryEntered = {
            entered.fulfill()
        }
        manager.reloadFromInterface(rebuildingCache: false)
        wait(for: [entered], timeout: 5)
        let done = expectation(description: "deferred refresh reports unavailable")
        manager.refreshFormulaStateAfterRemoval { ok in
            XCTAssertFalse(ok)
            done.fulfill()
        }
        interface.finishDiscovery?.signal()
        wait(for: [done], timeout: 2)
        XCTAssertEqual(interface.modes?.count ?? 0, 0)
    }

    func testAutoremoveLateCancellationCannotContradictItsResult() {
        for _ in 0..<5 {
            let interface = CB150Interface(uniqueInstance: ())
            interface.preview = BPAutoremovePreview.preview(
                withOutput: "==> Would autoremove 1 unneeded formula:\nlibfoo\n",
                succeeded: true
            )
            interface.removalSuccess = true
            let operation = BPAutoremoveOperation(preview: interface.preview, interface: interface)
            let done = expectation(description: "late cancellation")
            operation.start(withOutput: { chunk in
                if chunk.contains("fixture stream") {
                    operation.cancel()
                }
            }, completion: { success, cancelled, attempted, message in
                XCTAssertTrue(attempted)
                if cancelled {
                    XCTAssertFalse(success)
                    XCTAssertTrue(message.contains("cancelled"))
                } else {
                    XCTAssertTrue(success)
                }
                done.fulfill()
            })
            wait(for: [done], timeout: 5)
        }
    }

    func testAutoremoveFailedRefreshRetainsListsAndNeverInventsZeroCasks() {
        let manager = CB150Manager(uniqueInstance: ())
        let interface = CB150RefreshInterface(uniqueInstance: ())
        interface.modes = NSMutableArray()
        interface.fail = true
        manager.fixtureInterface = interface
        let kept = [BPFormula.formula(withName: "kept")]
        manager.installedFormulae = kept
        manager.leavesFormulae = kept
        manager.outdatedFormulae = kept

        nonisolated(unsafe) var notifications: UInt = 0
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(BPHomebrewManagerDidPublishOutdatedSnapshotNotification),
            object: manager,
            queue: nil
        ) { _ in
            notifications += 1
        }
        let done = expectation(description: "failed refresh completes")
        manager.refreshFormulaStateAfterRemoval { succeeded in
            XCTAssertFalse(succeeded)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(manager.installedFormulae, kept)
        XCTAssertEqual(manager.leavesFormulae, kept)
        XCTAssertEqual(manager.outdatedFormulae, kept)
        XCTAssertNil(manager.outdatedCasks)
        XCTAssertEqual(notifications, 0)
        NotificationCenter.default.removeObserver(observer)
    }

    func testAutoremoveRefreshCoalescesBehindAnExistingReload() {
        let manager = CB150Manager(uniqueInstance: ())
        let interface = CB150RefreshInterface(uniqueInstance: ())
        interface.modes = NSMutableArray()
        manager.fixtureInterface = interface
        manager.setValue(true, forKey: "reloadInFlight")
        let first = expectation(description: "first deferred request")
        let second = expectation(description: "second deferred request")
        manager.refreshFormulaStateAfterRemoval { ok in
            XCTAssertTrue(ok)
            first.fulfill()
        }
        manager.refreshFormulaStateAfterRemoval { ok in
            XCTAssertTrue(ok)
            second.fulfill()
        }
        XCTAssertEqual(interface.modes?.count ?? 0, 0)
        manager.setValue(false, forKey: "reloadInFlight")
        manager.refreshFormulaStateAfterRemoval(withCompletion: nil)
        wait(for: [first, second], timeout: 5)
        XCTAssertEqual(interface.modes?.count ?? 0, 3)
        XCTAssertEqual(interface.serviceCalls, 1)
    }

    func testAutoremoveRefreshRejectsReentrantSupersededPublications() {
        let manager = CB150Manager(uniqueInstance: ())
        let interface = CB150RefreshInterface(uniqueInstance: ())
        interface.modes = NSMutableArray()
        manager.fixtureInterface = interface
        let kept = [BPFormula.formula(withName: "kept")]
        manager.leavesFormulae = kept
        let observer = CB150Observer()
        observer.observed = {
            manager.cancelReload()
        }
        manager.addObserver(observer, forKeyPath: "installedFormulae", options: [], context: nil)
        let done = expectation(description: "superseded refresh completes")
        manager.refreshFormulaStateAfterRemoval { ok in
            XCTAssertFalse(ok)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        manager.removeObserver(observer, forKeyPath: "installedFormulae")
        XCTAssertEqual(manager.leavesFormulae, kept)
        XCTAssertNil(manager.outdatedFormulae)
        XCTAssertNil(manager.services)
    }

    func testAutoremoveRefreshPreservesCasksAndPublishesCombinedOutdatedSnapshot() {
        let manager = CB150Manager(uniqueInstance: ())
        let interface = CB150RefreshInterface(uniqueInstance: ())
        interface.modes = NSMutableArray()
        manager.fixtureInterface = interface
        let casks = [BPFormula.formula(withName: "kept-cask")]
        manager.publishList(casks, forMode: .outdatedCasks, generation: manager.currentReloadGeneration)
        let generation = manager.currentReloadGeneration

        nonisolated(unsafe) var snapshot: [AnyHashable: Any]?
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(BPHomebrewManagerDidPublishOutdatedSnapshotNotification),
            object: manager,
            queue: nil
        ) { note in
            snapshot = note.userInfo
        }
        let done = expectation(description: "targeted refresh")
        manager.refreshFormulaStateAfterRemoval { succeeded in
            XCTAssertTrue(succeeded)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        NotificationCenter.default.removeObserver(observer)

        let expectedModes: NSArray = [
            NSNumber(value: BPListMode.installed.rawValue),
            NSNumber(value: BPListMode.leaves.rawValue),
            NSNumber(value: BPListMode.outdated.rawValue)
        ]
        XCTAssertEqual(interface.modes, expectedModes)
        XCTAssertEqual(interface.serviceCalls, 1)
        XCTAssertEqual(manager.outdatedCasks, casks)
        XCTAssertEqual(manager.currentReloadGeneration, generation + 1)
        XCTAssertEqual(snapshot?[BPOutdatedSnapshotFormulaeCountKey] as? NSNumber, 0)
        XCTAssertEqual(snapshot?[BPOutdatedSnapshotCaskCountKey] as? NSNumber, 1)
    }

    func testAutoremovePreservesStderrBeforeMarkerAndOwnsCancellation() {
        let interface = CB150TaskInterface(uniqueInstance: ())
        interface.setValue("/bin/sh", forKey: "path_shell")
        interface.script = "printf 'Warning: fixture warning\\n' >&2; /bin/sleep 0.1; printf '\\n+++++Cakebrew Autoremove+++++\\n'"
        let preview = interface.previewAutoremove(withProgress: Progress(totalUnitCount: 1))
        XCTAssertFalse(preview.valid)
        XCTAssertTrue(preview.rawOutput.contains("Warning: fixture warning"))

        let progress = Progress(totalUnitCount: 1)
        interface.script = "printf 'MUST_NOT_LAUNCH\\n'"
        interface.formatting = {
            objc_sync_enter(progress)
            progress.cancel()
            objc_sync_exit(progress)
        }
        nonisolated(unsafe) let output = NSMutableString()
        XCTAssertFalse(interface.removeUnusedFormulae(["libfoo"], progress: progress) { chunk in
            output.append(chunk)
        })
        XCTAssertFalse((output as String).contains("MUST_NOT_LAUNCH"))

        interface.formatting = nil
        interface.script = "printf 'OWNED_RUNNING\\n'; while :; do /bin/sleep 1; done"
        let active = Progress(totalUnitCount: 1)
        output.setString("")
        XCTAssertFalse(interface.removeUnusedFormulae(["libfoo"], progress: active) { chunk in
            output.append(chunk)
            if chunk.contains("OWNED_RUNNING") {
                objc_sync_enter(active)
                active.cancel()
                objc_sync_exit(active)
            }
        })
        XCTAssertTrue((output as String).contains("OWNED_RUNNING"))
        XCTAssertTrue(active.isCancelled)
    }

    func testAutoremoveCommandsAreExactAndPreserveFailure() {
        let interface = CB150CommandInterface(uniqueInstance: ())
        interface.fixture = "==> Would autoremove 1 unneeded formula:\nlibfoo\n"
        XCTAssertTrue(interface.previewAutoremove(withProgress: Progress(totalUnitCount: 1)).valid)
        let expectedPreviewArgs: NSArray = ["autoremove", "--dry-run"]
        XCTAssertEqual(interface.arguments, expectedPreviewArgs)

        interface.status = 7
        XCTAssertFalse(interface.previewAutoremove(withProgress: Progress(totalUnitCount: 1)).valid)
        XCTAssertFalse(interface.removeUnusedFormulae(["libfoo"], progress: Progress(totalUnitCount: 1), output: nil))
        let expectedUninstallArgs: NSArray = ["uninstall", "--formula", "libfoo"]
        XCTAssertEqual(interface.arguments, expectedUninstallArgs)

        let command = interface.formatAutoremoveArguments(["uninstall", "--formula", "libfoo"])[2] as? String
        XCTAssertTrue(command?.contains("/usr/bin/env HOMEBREW_NO_AUTOREMOVE=1 HOMEBREW_NO_AUTO_UPDATE=1 brew \"$@\"") == true)
    }

    func testAutoremoveRevalidationAndCancellationNeverBroadenReviewedNames() {
        for scenario in [0, 1, 2, 3] {
            let interface = CB150Interface(uniqueInstance: ())
            let reviewed = BPAutoremovePreview.preview(
                withOutput: "==> Would autoremove 1 unneeded formula:\nlibfoo\n",
                succeeded: true
            )
            interface.preview = scenario == 1
                ? BPAutoremovePreview.preview(withOutput: "", succeeded: true)
                : reviewed
            interface.removalSuccess = scenario != 3
            let operation = BPAutoremoveOperation(preview: reviewed, interface: interface)
            if scenario == 2 {
                operation.cancel()
            }
            let finished = expectation(description: "autoremove completes once")
            nonisolated(unsafe) var completions: UInt = 0
            operation.start(withOutput: nil) { success, cancelled, attempted, message in
                completions += 1
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(success, scenario == 0)
                XCTAssertEqual(cancelled, scenario == 2)
                XCTAssertEqual(attempted, scenario == 0 || scenario == 3)
                if scenario == 3 {
                    XCTAssertTrue(message.contains("partially"))
                }
                finished.fulfill()
            }
            operation.start(withOutput: nil, completion: nil)
            wait(for: [finished], timeout: 5)
            XCTAssertEqual(completions, 1)
            XCTAssertEqual(interface.removalCalls, (scenario == 0 || scenario == 3) ? 1 : 0)
            if interface.removalCalls > 0 {
                XCTAssertEqual(interface.removed as? [String], reviewed.names)
            }
        }
    }

    func testAutoremovePreviewRequiresExactCountAndSafeUniqueFormulaNames() {
        let preview = BPAutoremovePreview.preview(
            withOutput: "==> Would autoremove 2 unneeded formulae:\nlibfoo\nuser/tap/library@2\n",
            succeeded: true
        )
        XCTAssertTrue(preview.valid)
        XCTAssertEqual(preview.names, ["libfoo", "user/tap/library@2"])

        let invalidOutputs = [
            "==> Would autoremove 2 unneeded formulae:\nlibfoo\n",
            "unexpected",
            "Warning: failed\n",
            "==> Would autoremove 2 unneeded formulae:\nlibfoo\nlibfoo\n",
            "==> Would autoremove 1 unneeded formula:\n--force\n",
            "==> Would autoremove 1 unneeded formula:\nfoo;bar\n"
        ]
        for text in invalidOutputs {
            XCTAssertFalse(BPAutoremovePreview.preview(withOutput: text, succeeded: true).valid, "\(text)")
        }
        XCTAssertTrue(BPAutoremovePreview.preview(withOutput: "", succeeded: true).valid)
        XCTAssertFalse(BPAutoremovePreview.preview(withOutput: "", succeeded: false).valid)
    }

    func testRemovalRefreshCarriesOnlyCompleteImmutableCurrentUpdatesBaseline() {
        for complete in [0, 1, 2] {
            let manager = CB150Manager(uniqueInstance: ())
            let interface = CB150RefreshInterface(uniqueInstance: ())
            interface.modes = NSMutableArray()
            manager.fixtureInterface = interface
            let generation = manager.currentReloadGeneration
            let cask = BPFormula.formula(withName: "browser")
            manager.publishList([cask], forMode: .outdatedCasks, generation: generation)
            manager.publishList([], forMode: .outdated, generation: generation)
            manager.publishList([], forMode: .pinned, generation: generation)
            if complete != 0 {
                manager.publishPinnedCasks([], generation: generation)
            }
            if complete == 2 {
                manager.setValue(generation + 1, forKey: "reloadGeneration")
            }
            manager.outdatedCasks = [] // Live arrays must never supply the baseline.
            let done1 = expectation(description: "partial refresh")
            manager.refreshFormulaStateAfterRemoval { ok in
                XCTAssertTrue(ok)
                done1.fulfill()
            }
            XCTAssertNil(manager.updatesSnapshot)
            wait(for: [done1], timeout: 5)
            if complete == 1 {
                XCTAssertEqual(manager.updatesSnapshot?.eligibleCasks, ["browser"])
                XCTAssertEqual(manager.updatesSnapshot?.eligibleFormulae, [])
                XCTAssertEqual(manager.updatesSnapshot?.generation, generation + 1)
            } else {
                XCTAssertNil(manager.updatesSnapshot)
            }
            interface.fail = true
            let done2 = expectation(description: "failed partial refresh")
            manager.refreshFormulaStateAfterRemoval { ok in
                XCTAssertFalse(ok)
                done2.fulfill()
            }
            wait(for: [done2], timeout: 5)
            XCTAssertNil(manager.updatesSnapshot)
        }
    }
}
