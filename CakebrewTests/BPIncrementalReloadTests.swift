//
//  BPIncrementalReloadTests.swift
//  CakebrewTests
//
//  The reload was all-or-nothing: ten brew calls fanned out, then every
//  property was set in one main-queue block. The fastest and most-used list —
//  `brew list --versions`, under a second — was hidden behind the slowest call
//  in the batch, a cold cask catalog that can take 80 seconds.
//
//  Publishing each list as it lands is what fixes that, and it introduces the
//  hazard the old design did not have: a superseded reload's lists arriving
//  after a newer one has already published. The generation guard is the whole
//  correctness argument, so it is what these tests pin.
//

import XCTest

private final class BPIncrementalReloadRecorder: NSObject, BPHomebrewManagerDelegate, @unchecked Sendable {
    var publishedModes: [BPListMode] = []
    var announcedSteps: [BPListMode] = []
    var finishedCount: UInt = 0
    var onPublication: ((BPHomebrewManager, BPListMode) -> Void)?

    func homebrewManager(_ manager: BPHomebrewManager, didPublishListForMode mode: BPListMode) {
        publishedModes.append(mode)
        onPublication?(manager, mode)
    }

    func homebrewManager(_ manager: BPHomebrewManager, didBeginStepForMode mode: BPListMode) {
        announcedSteps.append(mode)
    }

    func homebrewManagerFinishedUpdating(_ manager: BPHomebrewManager) {
        finishedCount += 1
    }

    func homebrewManager(_ manager: BPHomebrewManager, didUpdateSearchResults results: [Any]?) {}
    func homebrewManager(_ manager: BPHomebrewManager, shouldDisplayNoBrewMessage yesOrNo: Bool) {}
}

// MARK: -

@MainActor
final class BPIncrementalReloadTests: XCTestCase, @unchecked Sendable {
    private var manager: BPHomebrewManager!
    private var recorder: BPIncrementalReloadRecorder!
    private var outdatedSnapshots: NSMutableArray!
    private var snapshotObserver: NSObjectProtocol?

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
        // BPHomebrewManager is a singleton; reset what these tests touch.
        manager = BPHomebrewManager.sharedManager()
        recorder = BPIncrementalReloadRecorder()
        manager.delegate = recorder
        manager.installedFormulae = []
        manager.outdatedFormulae = []
        manager.installedCasks = []
        manager.outdatedCasks = []
        manager.cancelReload()
        outdatedSnapshots = NSMutableArray()
        nonisolated(unsafe) let snapshots = outdatedSnapshots!
        snapshotObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("BPHomebrewManagerDidPublishOutdatedSnapshotNotification"),
            object: manager,
            queue: nil
        ) { notification in
            XCTAssertTrue(Thread.isMainThread)
            if let userInfo = notification.userInfo {
                snapshots.add(userInfo as NSDictionary)
        }
            }
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
        if let snapshotObserver {
            NotificationCenter.default.removeObserver(snapshotObserver)
            self.snapshotObserver = nil
        }
        manager.delegate = nil
        }
        super.tearDown()
    }

    private func oneFormula(named name: String) -> [BPFormula] {
        [BPFormula.formula(withName: name, andVersion: "1.0.0")]
    }

    // MARK: - Coherent outdated snapshots

    private func assertSnapshotWaitsForBothLists(casksFirst: Bool) {
        let generation = manager.currentReloadGeneration
        let formulae = oneFormula(named: "formula")
        let casks = [BPFormula.formula(withName: "cask-a"), BPFormula.formula(withName: "cask-b")]
        manager.publishList(
            casksFirst ? casks : formulae,
            forMode: casksFirst ? .outdatedCasks : .outdated,
            generation: generation
        )
        XCTAssertEqual(outdatedSnapshots.count, 0)
        manager.publishList(
            casksFirst ? formulae : casks,
            forMode: casksFirst ? .outdated : .outdatedCasks,
            generation: generation
        )
        let expected: NSDictionary = [
            "formulae-count": 1,
            "cask-count": 2,
            "generation": NSNumber(value: generation)
        ]
        XCTAssertEqual(outdatedSnapshots as? [NSDictionary], [expected])
        XCTAssertEqual(recorder.finishedCount, 0, "the pair must not wait for the slow catalog or final reload callback")
    }

    func testOutdatedSnapshotWaitsForFormulaeWhenCasksFinishFirst() {
        assertSnapshotWaitsForBothLists(casksFirst: true)
    }

    func testOutdatedSnapshotWaitsForCasksWhenFormulaeFinishFirst() {
        assertSnapshotWaitsForBothLists(casksFirst: false)
    }

    func testEmptyOutdatedListsPublishAValidZeroSnapshot() {
        let generation = manager.currentReloadGeneration
        manager.publishList([], forMode: .outdated, generation: generation)
        manager.publishList([], forMode: .outdatedCasks, generation: generation)
        let expected: NSDictionary = [
            "formulae-count": 0,
            "cask-count": 0,
            "generation": NSNumber(value: generation)
        ]
        XCTAssertEqual(outdatedSnapshots as? [NSDictionary], [expected])
    }

    func testNilOutdatedListCannotCompleteTheSnapshot() {
        let generation = manager.currentReloadGeneration
        manager.publishList(nil, forMode: .outdated, generation: generation)
        manager.publishList([], forMode: .outdatedCasks, generation: generation)
        XCTAssertEqual(outdatedSnapshots.count, 0, "nil is a missing result, not a successful empty list")
    }

    func testCanceledPartialPairCannotCompleteOrLeakIntoTheNextGeneration() {
        let oldGeneration = manager.currentReloadGeneration
        manager.publishList(oneFormula(named: "old"), forMode: .outdated, generation: oldGeneration)
        manager.cancelReload()
        manager.publishList([], forMode: .outdatedCasks, generation: oldGeneration)
        XCTAssertEqual(outdatedSnapshots.count, 0)
        let generation = manager.currentReloadGeneration
        manager.publishList([], forMode: .outdatedCasks, generation: generation)
        XCTAssertEqual(outdatedSnapshots.count, 0, "the new generation cannot borrow the old formula count")
        manager.publishList([], forMode: .outdated, generation: generation)
        let expected: NSDictionary = [
            "formulae-count": 0,
            "cask-count": 0,
            "generation": NSNumber(value: generation)
        ]
        XCTAssertEqual(outdatedSnapshots as? [NSDictionary], [expected])
    }

    func testEveryGenerationRequiresItsOwnOutdatedPair() {
        var generation = manager.currentReloadGeneration
        manager.publishList([], forMode: .outdated, generation: generation)
        manager.publishList([], forMode: .outdatedCasks, generation: generation)
        manager.cancelReload()
        generation = manager.currentReloadGeneration
        manager.publishList(oneFormula(named: "new"), forMode: .outdated, generation: generation)
        XCTAssertEqual(outdatedSnapshots.count, 1)
        manager.publishList([], forMode: .outdatedCasks, generation: generation)
        XCTAssertEqual(outdatedSnapshots.count, 2)
        let expected: NSDictionary = [
            "formulae-count": 1,
            "cask-count": 0,
            "generation": NSNumber(value: generation)
        ]
        XCTAssertEqual(outdatedSnapshots.lastObject as? NSDictionary, expected)
    }

    func testOutdatedSnapshotIsImmutableAndEmittedBeforeReentrantPublication() {
        let generation = manager.currentReloadGeneration
        nonisolated(unsafe) var emissions: UInt = 0
        let capturedManager = manager!
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("BPHomebrewManagerDidPublishOutdatedSnapshotNotification"),
            object: capturedManager,
            queue: nil
        ) { _ in
            emissions += 1
            if emissions == 1 {
                capturedManager.publishList([], forMode: .outdated, generation: generation)
                capturedManager.publishList([], forMode: .outdatedCasks, generation: generation)
            }
        }
        manager.publishList(oneFormula(named: "formula"), forMode: .outdated, generation: generation)
        manager.publishList(oneFormula(named: "cask"), forMode: .outdatedCasks, generation: generation)
        NotificationCenter.default.removeObserver(observer)
        XCTAssertEqual(emissions, 1, "mark the snapshot emitted before notifying reentrant observers")
        let expected: NSDictionary = [
            "formulae-count": 1,
            "cask-count": 1,
            "generation": NSNumber(value: generation)
        ]
        XCTAssertEqual(outdatedSnapshots as? [NSDictionary], [expected])
    }

    func testReentrantCancellationDiscardsAnIncompleteOutdatedSnapshot() {
        let generation = manager.currentReloadGeneration
        recorder.onPublication = { manager, mode in
            if mode == .outdated {
                manager.cancelReload()
            }
        }
        manager.publishList([], forMode: .outdated, generation: generation)
        manager.publishList([], forMode: .outdatedCasks, generation: generation)
        XCTAssertEqual(outdatedSnapshots.count, 0)
    }

    // MARK: - Publishing a list

    func testPublishingAListSetsItsPropertyAndTellsTheDelegate() {
        let installed = oneFormula(named: "wget")

        manager.publishList(
            installed,
            forMode: .installed,
            generation: manager.currentReloadGeneration
        )

        XCTAssertEqual(manager.installedFormulae, installed)
        XCTAssertEqual(recorder.publishedModes, [.installed])
    }

    /// Each mode has to land in its own property. Getting this mapping wrong shows
    /// casks in the formulae list, which is exactly the kind of thing a switch
    /// statement with a missing case does silently.
    func testEachModeLandsInItsOwnProperty() {
        let generation = manager.currentReloadGeneration

        let formulae = oneFormula(named: "wget")
        let casks = oneFormula(named: "chrome")

        manager.publishList(formulae, forMode: .installed, generation: generation)
        manager.publishList(casks, forMode: .installedCasks, generation: generation)

        XCTAssertEqual(manager.installedFormulae, formulae)
        XCTAssertEqual(manager.installedCasks, casks)
        XCTAssertNotEqual(manager.installedFormulae, manager.installedCasks)
    }

    func testPublishingIsAnnouncedOncePerList() {
        let generation = manager.currentReloadGeneration

        manager.publishList([], forMode: .installed, generation: generation)
        manager.publishList([], forMode: .outdated, generation: generation)
        manager.publishList([], forMode: .installedCasks, generation: generation)

        XCTAssertEqual(
            recorder.publishedModes,
            [.installed, .outdated, .installedCasks],
            "one callback per list, in the order they land"
        )
    }

    // MARK: - The generation guard

    /// The reason the old design was safe: nothing published until the end, where
    /// one generation check covered everything. Publishing incrementally means a
    /// superseded reload can still have calls in flight, and its stale lists must
    /// not overwrite the newer ones.
    func testAStaleGenerationPublishesNothing() {
        let fresh = oneFormula(named: "current")
        let generation = manager.currentReloadGeneration

        manager.publishList(fresh, forMode: .installed, generation: generation)
        recorder.publishedModes.removeAll()

        manager.publishList(
            oneFormula(named: "stale"),
            forMode: .installed,
            generation: generation &- 1
        )

        XCTAssertEqual(manager.installedFormulae, fresh, "a stale list must not overwrite")
        XCTAssertEqual(recorder.publishedModes.count, 0, "and must not be announced")
    }

    /// An empty list is a real result — nothing outdated — not a missing one.
    func testAnEmptyListStillPublishes() {
        manager.outdatedFormulae = oneFormula(named: "stale")

        manager.publishList(
            [],
            forMode: .outdated,
            generation: manager.currentReloadGeneration
        )

        XCTAssertEqual(manager.outdatedFormulae?.count, 0)
        XCTAssertEqual(recorder.publishedModes, [.outdated])
    }

    /// The callback is optional, so a delegate that does not implement it — or no
    /// delegate at all — must not crash the reload.
    func testPublishingWithoutADelegateIsHarmless() {
        manager.delegate = nil

        XCTAssertNoThrow(
            manager.publishList(
                [],
                forMode: .installed,
                generation: manager.currentReloadGeneration
            )
        )
    }

    // MARK: - Announcing a step

    // A reload after an operation — a pin, an install, the hourly timer — used to
    // be completely silent: the loading overlay is built once at setup and torn
    // down on the first published list, so nothing marked any reload after the
    // first. Announcing a step is what the footer shows.

    func testAnnouncingAStepTellsTheDelegate() {
        manager.announceStep(forMode: .allCasks, generation: manager.currentReloadGeneration)

        XCTAssertEqual(recorder.announcedSteps, [.allCasks])
    }

    /// Same hazard as publishing: a superseded reload still has calls in flight,
    /// and its steps must not talk over the newer reload's.
    func testAStaleGenerationAnnouncesNothing() {
        manager.announceStep(
            forMode: .installed,
            generation: manager.currentReloadGeneration &- 1
        )

        XCTAssertEqual(recorder.announcedSteps.count, 0)
    }

    func testAnnouncingWithoutADelegateIsHarmless() {
        manager.delegate = nil

        XCTAssertNoThrow(
            manager.announceStep(
                forMode: .installed,
                generation: manager.currentReloadGeneration
            )
        )
    }

    // MARK: - Which sidebar row a list belongs to

    // Publishing per list means refreshing one badge per list. The first attempt
    // called reloadData on the whole outline, which clears an NSOutlineView's
    // selection — so the app silently lost the row the user had reopened on, and
    // then persisted Installed over it. Redrawing a single row avoids that, and
    // this pins the mode -> row mapping it depends on.

    func testEveryReloadedListMapsToItsOwnSidebarRow() {
        let sidebar = BPSideBarController()

        let modes: [BPListMode] = [
            .installed,
            .outdated,
            .all,
            .leaves,
            .pinned,
            .repositories,
            .installedCasks,
            .outdatedCasks,
            .allCasks
        ]

        var seen = Set<ObjectIdentifier>()

        for mode in modes {
            let item = sidebar.item(forListMode: mode.rawValue)

            XCTAssertNotNil(item, "mode \(mode.rawValue) has no sidebar row")
            if let item {
                let id = ObjectIdentifier(item)
                XCTAssertFalse(
                    seen.contains(id),
                    "mode \(mode.rawValue) shares a row with an earlier mode"
                )
                seen.insert(id)
            }
        }
    }

    /// Search results are shown in place and have no row of their own; asking for
    /// one must yield nil rather than some other list's row.
    func testSearchHasNoSidebarRow() {
        let sidebar = BPSideBarController()

        XCTAssertNil(sidebar.item(forListMode: BPListMode.search.rawValue))
    }
}
