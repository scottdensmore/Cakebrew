//
//  BPSearchCoordinatorTests.swift
//  CakebrewTests
//

import XCTest

@MainActor
final class BPSearchCoordinatorTests: XCTestCase, @unchecked Sendable {

    func testSchedulingDefersQueryByTheExistingDebounceInterval() {
        var pending: (() -> Void)?
        var delay: TimeInterval = 0
        var performed: String?
        let coordinator = BPSearchCoordinator(
            schedule: { interval, work in
                delay = interval
                pending = work
            },
            performSearch: { query in
                performed = query
            },
            cancelSearch: {}
        )
        coordinator.scheduleQuery("mockvscode")
        XCTAssertEqual(delay, 0.15, accuracy: 0.0001)
        XCTAssertNil(performed)
        XCTAssertFalse(coordinator.searching)
        XCTAssertNotNil(pending)
        pending?()
        XCTAssertEqual(performed, "mockvscode")
    }

    func testResultsCaptureOnlyTheFirstSidebarRowAndEndCancelsBeforeReturningIt() {
        var cancellations: UInt = 0
        var searchingAtCancellation = true
        weak var weakCoordinator: BPSearchCoordinator?
        let coordinator = BPSearchCoordinator(
            schedule: { _, _ in },
            performSearch: { _ in },
            cancelSearch: {
                cancellations += 1
                searchingAtCancellation = weakCoordinator?.searching ?? true
            }
        )
        weakCoordinator = coordinator
        XCTAssertFalse(coordinator.searching)
        coordinator.didReceiveResults(forSidebarRow: 9)
        XCTAssertTrue(coordinator.searching)
        coordinator.didReceiveResults(forSidebarRow: 2)
        XCTAssertEqual(coordinator.originalSidebarRow, 9)
        XCTAssertEqual(coordinator.endSearchReturningSidebarRow(), 9)
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(searchingAtCancellation)
        XCTAssertFalse(coordinator.searching)
        coordinator.didReceiveResults(forSidebarRow: 4)
        XCTAssertEqual(coordinator.originalSidebarRow, 4)
        XCTAssertEqual(coordinator.endSearchReturningSidebarRow(), 4)
    }

    func testSidebarRowsRemainRawForTheControllerToValidate() {
        let coordinator = BPSearchCoordinator(
            schedule: { _, _ in },
            performSearch: { _ in },
            cancelSearch: {}
        )
        coordinator.didReceiveResults(forSidebarRow: -1)
        XCTAssertEqual(coordinator.endSearchReturningSidebarRow(), -1)
        coordinator.didReceiveResults(forSidebarRow: Int.max)
        XCTAssertEqual(coordinator.endSearchReturningSidebarRow(), Int.max)
    }

    func testNavigationInvalidatesRetainedWorkAndAllowsTheNextQuery() {
        var scheduled: [() -> Void] = []
        var performed: [String] = []
        var cancellations: UInt = 0
        let coordinator = BPSearchCoordinator(
            schedule: { _, work in
                scheduled.append(work)
            },
            performSearch: { query in
                performed.append(query)
            },
            cancelSearch: {
                cancellations += 1
            }
        )
        coordinator.didReceiveResults(forSidebarRow: 9)
        coordinator.scheduleQuery("old")
        let generation = coordinator.generation
        coordinator.cancelForNavigation()
        XCTAssertFalse(coordinator.searching)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(coordinator.generation, generation + 1)
        scheduled[0]()
        XCTAssertEqual(performed.count, 0)
        coordinator.scheduleQuery("new")
        scheduled[1]()
        XCTAssertEqual(performed, ["new"])
        coordinator.didReceiveResults(forSidebarRow: 3)
        XCTAssertEqual(coordinator.originalSidebarRow, 3)
    }

    func testClearingSearchInvalidatesRetainedCallbackWithoutResumingSearch() {
        var pending: (() -> Void)?
        var performed: UInt = 0
        var cancellations: UInt = 0
        weak var weakCoordinator: BPSearchCoordinator?
        let coordinator = BPSearchCoordinator(
            schedule: { _, work in
                pending = work
            },
            performSearch: { _ in
                performed += 1
                weakCoordinator?.didReceiveResults(forSidebarRow: 9)
            },
            cancelSearch: {
                cancellations += 1
            }
        )
        weakCoordinator = coordinator
        coordinator.scheduleQuery("mockvscode")
        coordinator.endSearchReturningSidebarRow()
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(coordinator.searching)
        XCTAssertNotNil(pending)
        guard let pending else { return }
        pending()
        XCTAssertEqual(performed, 0, "clearing must invalidate already queued search work")
        XCTAssertFalse(coordinator.searching, "old results must not reopen the cleared search")
    }

    func testNewQueryRunsAfterClearingWithoutRevivingOlderQuery() {
        var scheduled: [() -> Void] = []
        var performed: [String] = []
        let coordinator = BPSearchCoordinator(
            schedule: { _, work in
                scheduled.append(work)
            },
            performSearch: { query in
                performed.append(query)
            },
            cancelSearch: {}
        )
        coordinator.scheduleQuery("old")
        coordinator.endSearchReturningSidebarRow()
        coordinator.scheduleQuery("new")
        scheduled[0]()
        XCTAssertEqual(performed.count, 0, "a new query must not make cleared work valid again")
        scheduled[1]()
        XCTAssertEqual(performed, ["new"])
        coordinator.didReceiveResults(forSidebarRow: 4)
        XCTAssertTrue(coordinator.searching)
        XCTAssertEqual(coordinator.endSearchReturningSidebarRow(), 4)
    }

    func testRetainedScheduledWorkDoesNotKeepTheCoordinatorAlive() {
        var pending: (() -> Void)?
        var performed = false
        weak var weakCoordinator: BPSearchCoordinator?
        autoreleasepool {
            let coordinator = BPSearchCoordinator(
                schedule: { _, work in
                    pending = work
                },
                performSearch: { _ in
                    performed = true
                },
                cancelSearch: {}
            )
            weakCoordinator = coordinator
            coordinator.scheduleQuery("mock")
        }
        XCTAssertNil(weakCoordinator)
        XCTAssertNotNil(pending)
        pending?()
        XCTAssertFalse(performed)
    }

    func testProductionSchedulerCoalescesQueriesAndPerformsOnMainThread() {
        let lastQuery = expectation(description: "last debounced query")
        var performed: [String] = []
        let coordinator = BPSearchCoordinator(
            performSearch: { query in
                XCTAssertTrue(Thread.isMainThread)
                performed.append(query)
                lastQuery.fulfill()
            },
            cancelSearch: {}
        )
        coordinator.scheduleQuery("m")
        coordinator.scheduleQuery("mock")
        coordinator.scheduleQuery("mockvscode")
        XCTAssertEqual(performed.count, 0)
        wait(for: [lastQuery], timeout: 2.0)
        XCTAssertEqual(performed, ["mockvscode"])
    }
}
