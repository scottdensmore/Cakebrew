import XCTest
import AppKit
import Foundation
import UserNotifications

private final class BPNotificationCenterDeliverySpy: NSObject, @unchecked Sendable {
    var request: UNNotificationRequest?
    var deliveryCount: UInt = 0
    var authorizationCount: UInt = 0
    var holdAuthorization: Bool = false
    var pendingAuthorization: (@Sendable (Bool, NSError?) -> Void)?

    @objc(requestAuthorizationWithOptions:completionHandler:)
    func requestAuthorization(
        withOptions options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, NSError?) -> Void
    ) {
        authorizationCount += 1
        if holdAuthorization {
            pendingAuthorization = completionHandler
        } else {
            completionHandler(true, nil)
        }
    }

    @objc(addNotificationRequest:withCompletionHandler:)
    func addNotificationRequest(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (NSError?) -> Void)?
    ) {
        self.request = request
        deliveryCount += 1
    }
}

@MainActor
final class BPBackgroundUpdaterTests: XCTestCase, @unchecked Sendable {
    private var savedBaseline: Any?
    private var savedOutdatedFormulae: [BPFormula]?
    private var savedOutdatedCasks: [BPFormula]?
    private var savedDelegate: (any BPHomebrewManagerDelegate)?
    private var observingUpdater: BPObservingBackgroundUpdater?

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            let defaults = UserDefaults.standard
            savedBaseline = defaults.object(forKey: "BPLastNotifiedOutdatedCount")
            let manager = BPHomebrewManager.sharedManager()
            savedOutdatedFormulae = manager.outdatedFormulae
            savedOutdatedCasks = manager.outdatedCasks
            savedDelegate = manager.delegate
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            drainNotificationWork()
            observingUpdater = nil
            let manager = BPHomebrewManager.sharedManager()
            manager.outdatedFormulae = savedOutdatedFormulae
            manager.outdatedCasks = savedOutdatedCasks
            manager.delegate = savedDelegate
            let defaults = UserDefaults.standard
            if let savedBaseline {
                defaults.set(savedBaseline, forKey: "BPLastNotifiedOutdatedCount")
            } else {
                defaults.removeObject(forKey: "BPLastNotifiedOutdatedCount")
            }
        }
        super.tearDown()
    }

    private func drainNotificationWork() {
        let drained = expectation(description: "scheduled notification work drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 2.0)
    }

    private func startObservingReloads(withBaseline baseline: NSNumber?) -> BPNotificationCenterDeliverySpy {
        let manager = BPHomebrewManager.sharedManager()
        manager.delegate = nil
        manager.cancelReload()
        manager.outdatedFormulae = [BPFormula.formula(withName: "old-formula")]
        manager.outdatedCasks = []
        if let baseline {
            BPBackgroundUpdater.setPersistedOutdatedCount(baseline.uintValue)
        } else {
            BPBackgroundUpdater.clearPersistedOutdatedCount()
        }
        let center = BPNotificationCenterDeliverySpy()
        let updater = BPObservingBackgroundUpdater(notificationCenter: center)
        observingUpdater = updater
        updater.start()
        return center
    }

    private func assertCoherentNotification(whenCasksFinishFirst casksFirst: Bool) {
        let center = startObservingReloads(withBaseline: 1)
        let manager = BPHomebrewManager.sharedManager()
        let generation = manager.currentReloadGeneration
        let casks = [
            BPFormula.formula(withName: "new-cask"),
            BPFormula.formula(withName: "other-cask")
        ]
        manager.publishList(
            casksFirst ? casks : [],
            forMode: casksFirst ? .outdatedCasks : .outdated,
            generation: generation
        )
        drainNotificationWork()
        XCTAssertEqual(BPBackgroundUpdater.persistedOutdatedCount(), 1, "one list must not poison the coherent baseline")
        XCTAssertEqual(center.authorizationCount, 0, "an incomplete pair must not request a notification")
        XCTAssertEqual(center.deliveryCount, 0)
        XCTAssertEqual(
            observingUpdater?.badgeLabel,
            casksFirst ? "3" : nil,
            "the Dock badge should still reflect incremental list publications"
        )

        manager.publishList(
            casksFirst ? [] : casks,
            forMode: casksFirst ? .outdated : .outdatedCasks,
            generation: generation
        )
        drainNotificationWork()
        XCTAssertEqual(BPBackgroundUpdater.persistedOutdatedCount(), 2)
        XCTAssertEqual(observingUpdater?.badgeLabel, "2")
        XCTAssertEqual(center.deliveryCount, 1)
        XCTAssertEqual(
            center.request?.content.userInfo as? [String: String],
            [BPBackgroundUpdater.outdatedNotificationTargetKey: BPBackgroundUpdater.outdatedNotificationTargetCasks],
            "the delivered request must not include a stale formula-only destination"
        )
    }

    func testCasksFinishingFirstWaitsForCoherentOutdatedNotification() {
        assertCoherentNotification(whenCasksFinishFirst: true)
    }

    func testFormulaeFinishingFirstWaitsForCoherentOutdatedNotification() {
        assertCoherentNotification(whenCasksFinishFirst: false)
    }

    func testInitialCompletePairSeedsBaselineWithoutNotifying() {
        let center = startObservingReloads(withBaseline: nil)
        let manager = BPHomebrewManager.sharedManager()
        let generation = manager.currentReloadGeneration
        manager.publishList([BPFormula.formula(withName: "new-cask")], forMode: .outdatedCasks, generation: generation)
        drainNotificationWork()
        XCTAssertFalse(BPBackgroundUpdater.hasPersistedOutdatedCount())
        manager.publishList([], forMode: .outdated, generation: generation)
        drainNotificationWork()
        XCTAssertEqual(BPBackgroundUpdater.persistedOutdatedCount(), 1)
        XCTAssertTrue(BPBackgroundUpdater.hasPersistedOutdatedCount())
        XCTAssertEqual(center.authorizationCount, 0)
    }

    func testFailedAndCanceledPairsDoNotChangeTheBaselineOrNotify() {
        let center = startObservingReloads(withBaseline: 1)
        let manager = BPHomebrewManager.sharedManager()
        let generation = manager.currentReloadGeneration
        manager.publishList([], forMode: .outdated, generation: generation)
        manager.publishList(nil, forMode: .outdatedCasks, generation: generation)
        drainNotificationWork()
        XCTAssertEqual(BPBackgroundUpdater.persistedOutdatedCount(), 1)
        manager.cancelReload()
        manager.publishList([BPFormula.formula(withName: "stale")], forMode: .outdatedCasks, generation: generation)
        manager.publishList([], forMode: .outdatedCasks, generation: manager.currentReloadGeneration)
        drainNotificationWork()
        XCTAssertEqual(BPBackgroundUpdater.persistedOutdatedCount(), 1)
        XCTAssertEqual(center.authorizationCount, 0)
        XCTAssertEqual(center.deliveryCount, 0)
    }

    func testDuplicateListPublicationDoesNotRenotifyTheSameGeneration() {
        let center = startObservingReloads(withBaseline: 0)
        let manager = BPHomebrewManager.sharedManager()
        let generation = manager.currentReloadGeneration
        manager.publishList([BPFormula.formula(withName: "first")], forMode: .outdated, generation: generation)
        manager.publishList([], forMode: .outdatedCasks, generation: generation)
        drainNotificationWork()
        XCTAssertEqual(center.deliveryCount, 1)
        manager.publishList([BPFormula.formula(withName: "duplicate")], forMode: .outdatedCasks, generation: generation)
        drainNotificationWork()
        XCTAssertEqual(center.deliveryCount, 1)
        XCTAssertEqual(BPBackgroundUpdater.persistedOutdatedCount(), 1)
    }

    func testDeferredAuthorizationDeliversCapturedCountsAfterANewerSnapshot() {
        let center = startObservingReloads(withBaseline: 0)
        center.holdAuthorization = true
        let manager = BPHomebrewManager.sharedManager()
        var generation = manager.currentReloadGeneration
        manager.publishList([], forMode: .outdated, generation: generation)
        manager.publishList(
            [BPFormula.formula(withName: "cask-a"), BPFormula.formula(withName: "cask-b")],
            forMode: .outdatedCasks,
            generation: generation
        )
        drainNotificationWork()
        XCTAssertEqual(center.authorizationCount, 1)
        XCTAssertNotNil(center.pendingAuthorization)
        manager.cancelReload()
        generation = manager.currentReloadGeneration
        manager.publishList([BPFormula.formula(withName: "later-formula")], forMode: .outdated, generation: generation)
        manager.publishList([], forMode: .outdatedCasks, generation: generation)
        drainNotificationWork()
        XCTAssertEqual(BPBackgroundUpdater.persistedOutdatedCount(), 1)
        XCTAssertEqual(center.authorizationCount, 1)
        let authorization = center.pendingAuthorization
        center.pendingAuthorization = nil
        authorization?(true, nil)
        drainNotificationWork()
        XCTAssertEqual(center.deliveryCount, 1)
        XCTAssertEqual(
            center.request?.content.userInfo as? [String: String],
            [BPBackgroundUpdater.outdatedNotificationTargetKey: BPBackgroundUpdater.outdatedNotificationTargetCasks]
        )
    }

    func testForeignOrSupersededSnapshotsDoNotChangeTheBaseline() {
        let center = startObservingReloads(withBaseline: 1)
        let manager = BPHomebrewManager.sharedManager()
        let snapshot: [String: Any] = [
            "formulae-count": 3,
            "cask-count": 2,
            "generation": manager.currentReloadGeneration
        ]
        NotificationCenter.default.post(
            name: Notification.Name("BPHomebrewManagerDidPublishOutdatedSnapshotNotification"),
            object: NSObject(),
            userInfo: snapshot
        )
        manager.cancelReload()
        NotificationCenter.default.post(
            name: Notification.Name("BPHomebrewManagerDidPublishOutdatedSnapshotNotification"),
            object: manager,
            userInfo: snapshot
        )
        drainNotificationWork()
        XCTAssertEqual(BPBackgroundUpdater.persistedOutdatedCount(), 1)
        XCTAssertEqual(center.authorizationCount, 0)
    }

    // MARK: - badge label

    func testBadgeLabelIsNilWhenNothingOutdated() {
        XCTAssertNil(BPBackgroundUpdater.badgeLabel(forOutdatedCount: 0), "no badge when everything is up to date")
    }

    func testBadgeLabelShowsTheCount() {
        XCTAssertEqual(BPBackgroundUpdater.badgeLabel(forOutdatedCount: 1), "1")
        XCTAssertEqual(BPBackgroundUpdater.badgeLabel(forOutdatedCount: 42), "42")
    }

    // MARK: - notification decision

    func testProductionNotificationDeliveryAttachesSemanticPayloadToRequestContent() {
        let center = BPNotificationCenterDeliverySpy()
        let updater = BPBackgroundUpdater(notificationCenter: center)

        updater.deliverOutdatedNotification(withFormulaeCount: 0, caskCount: 3)

        XCTAssertEqual(center.deliveryCount, 1)
        XCTAssertEqual(
            center.request?.content.userInfo as? [String: String],
            [BPBackgroundUpdater.outdatedNotificationTargetKey: BPBackgroundUpdater.outdatedNotificationTargetCasks]
        )
    }

    func testProductionMixedNotificationDeliveryPreservesBothPackageKinds() {
        let center = BPNotificationCenterDeliverySpy()
        let updater = BPBackgroundUpdater(notificationCenter: center)

        updater.deliverOutdatedNotification(withFormulaeCount: 2, caskCount: 3)

        XCTAssertEqual(center.deliveryCount, 1)
        XCTAssertEqual(
            center.request?.content.userInfo as? [String: String],
            [BPBackgroundUpdater.outdatedNotificationTargetKey: "mixed"]
        )
    }

    func testFormulaeNotificationPayloadIsSemanticAndStable() {
        let payload = BPBackgroundUpdater.notificationUserInfo(forOutdatedFormulaeCount: 2, caskCount: 0)
        XCTAssertEqual(payload, [BPBackgroundUpdater.outdatedNotificationTargetKey: BPBackgroundUpdater.outdatedNotificationTargetFormulae])
    }

    func testCaskOnlyNotificationPayloadTargetsCasks() {
        let payload = BPBackgroundUpdater.notificationUserInfo(forOutdatedFormulaeCount: 0, caskCount: 3)
        XCTAssertEqual(payload, [BPBackgroundUpdater.outdatedNotificationTargetKey: BPBackgroundUpdater.outdatedNotificationTargetCasks])
    }

    func testMixedNotificationPayloadIsDistinctFromFormulaeOnly() {
        let payload = BPBackgroundUpdater.notificationUserInfo(forOutdatedFormulaeCount: 2, caskCount: 3)
        XCTAssertEqual(payload, [BPBackgroundUpdater.outdatedNotificationTargetKey: "mixed"])
        XCTAssertEqual(BPBackgroundUpdater.outdatedNotificationTargetMixed, "mixed")
        XCTAssertNotEqual(payload, BPBackgroundUpdater.notificationUserInfo(forOutdatedFormulaeCount: 2, caskCount: 0))
    }

    func testEmptyOutdatedSetHasNoNotificationPayload() {
        XCTAssertNil(BPBackgroundUpdater.notificationUserInfo(forOutdatedFormulaeCount: 0, caskCount: 0))
    }

    func testNotifiesWhenOutdatedCountRises() {
        XCTAssertTrue(BPBackgroundUpdater.shouldNotify(forCount: 3, previousCount: 0))
        XCTAssertTrue(BPBackgroundUpdater.shouldNotify(forCount: 5, previousCount: 3))
    }

    func testDoesNotNotifyWhenNothingIsOutdated() {
        XCTAssertFalse(BPBackgroundUpdater.shouldNotify(forCount: 0, previousCount: 0))
        XCTAssertFalse(BPBackgroundUpdater.shouldNotify(forCount: 0, previousCount: 4), "upgrading everything should not notify")
    }

    func testDoesNotNotifyWhenCountIsUnchangedOrFalls() {
        XCTAssertFalse(BPBackgroundUpdater.shouldNotify(forCount: 3, previousCount: 3), "repeat checks with the same result stay quiet")
        XCTAssertFalse(BPBackgroundUpdater.shouldNotify(forCount: 2, previousCount: 3), "partially upgrading should not notify")
    }

    // MARK: - the first observation is a baseline, not news

    func testTheFirstObservationSeedsTheBaselineAndDoesNotNotify() {
        XCTAssertFalse(
            BPBackgroundUpdater.shouldNotify(forCount: 7, previousCount: 0, hasBaseline: false),
            "the first observation of a launch is what is already on disk, not an increase"
        )
    }

    func testAnIncreaseAfterTheBaselineNotifies() {
        XCTAssertTrue(BPBackgroundUpdater.shouldNotify(forCount: 8, previousCount: 7, hasBaseline: true))
    }

    func testNoIncreaseAfterTheBaselineDoesNotNotify() {
        XCTAssertFalse(BPBackgroundUpdater.shouldNotify(forCount: 7, previousCount: 7, hasBaseline: true))
        XCTAssertFalse(BPBackgroundUpdater.shouldNotify(forCount: 3, previousCount: 7, hasBaseline: true))
    }

    func testAZeroCountNeverNotifiesEvenSeeded() {
        XCTAssertFalse(BPBackgroundUpdater.shouldNotify(forCount: 0, previousCount: 0, hasBaseline: true))
    }

    func testTheBaselineSurvivesRelaunch() {
        BPBackgroundUpdater.setPersistedOutdatedCount(5)
        XCTAssertEqual(BPBackgroundUpdater.persistedOutdatedCount(), 5)
        XCTAssertTrue(BPBackgroundUpdater.hasPersistedOutdatedCount())

        XCTAssertFalse(
            BPBackgroundUpdater.shouldNotify(
                forCount: 5,
                previousCount: BPBackgroundUpdater.persistedOutdatedCount(),
                hasBaseline: BPBackgroundUpdater.hasPersistedOutdatedCount()
            )
        )
    }

    func testClearingTheBaselineRestoresTheUnseededState() {
        BPBackgroundUpdater.setPersistedOutdatedCount(5)
        BPBackgroundUpdater.clearPersistedOutdatedCount()
        XCTAssertFalse(BPBackgroundUpdater.hasPersistedOutdatedCount())
    }
}
