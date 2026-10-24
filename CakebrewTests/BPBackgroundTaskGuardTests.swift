import XCTest
import AppKit
import Foundation
import ObjectiveC.runtime
import UserNotifications

private final class BPNotificationResponseStub: NSObject, @unchecked Sendable {
    @objc var userInfo: NSDictionary?

    @objc func notification() -> AnyObject { self }
    @objc func request() -> AnyObject { self }
    @objc func content() -> AnyObject { self }
}

private final class BPNotificationPresentationSpy: NSObject, BPNotificationPresenting, @unchecked Sendable {
    var cleanupCount: UInt = 0
    var activationCount: UInt = 0
    var windowCount: UInt = 0
    var calledOnMainThread: Bool = true

    func cleanupNotificationAlerts() {
        cleanupCount += 1
        calledOnMainThread = calledOnMainThread && Thread.isMainThread
    }

    func activateCakebrewIgnoringOtherApps() {
        activationCount += 1
        calledOnMainThread = calledOnMainThread && Thread.isMainThread
    }

    func showMainWindow() {
        windowCount += 1
        calledOnMainThread = calledOnMainThread && Thread.isMainThread
    }
}

private final class BPNotificationNavigationTargetSpy: NSObject, BPNotificationNavigation, @unchecked Sendable {
    var formulaeNavigationCount: UInt = 0
    var caskNavigationCount: UInt = 0
    var unifiedUpdatesNavigationCount: UInt = 0
    var calledOnMainThread: Bool = false

    func showOutdatedFormulae(_ sender: Any?) {
        formulaeNavigationCount += 1
        calledOnMainThread = Thread.isMainThread
    }

    func showOutdatedCasks(_ sender: Any?) {
        caskNavigationCount += 1
        calledOnMainThread = Thread.isMainThread
    }

    func showUnifiedUpdates(_ sender: Any?) {
        unifiedUpdatesNavigationCount += 1
        calledOnMainThread = Thread.isMainThread
    }
}

@MainActor
final class BPBackgroundTaskGuardTests: XCTestCase, @unchecked Sendable {

    func testAnOperationIsBlockedWhileABackgroundTaskRuns() {
        XCTAssertTrue(
            BPAppDelegate.shouldBlockOperation(whileRunningBackgroundTask: true),
            "starting a second brew run is what Homebrew's lock rejects"
        )
    }

    func testAnOperationProceedsWhenNothingIsRunning() {
        XCTAssertFalse(BPAppDelegate.shouldBlockOperation(whileRunningBackgroundTask: false))
    }

    // MARK: - Notification navigation

    func testNotificationPayloadMapsToNavigationWithoutAppKitState() {
        XCTAssertEqual(
            BPAppDelegate.notificationNavigationAction(forUserInfo: [
                BPBackgroundUpdater.outdatedNotificationTargetKey: BPBackgroundUpdater.outdatedNotificationTargetFormulae
            ]),
            .outdatedFormulae
        )
        XCTAssertEqual(
            BPAppDelegate.notificationNavigationAction(forUserInfo: [
                BPBackgroundUpdater.outdatedNotificationTargetKey: BPBackgroundUpdater.outdatedNotificationTargetCasks
            ]),
            .outdatedCasks
        )
    }

    func testMixedNotificationPayloadNavigatesToFormulaeUntilACombinedViewExists() {
        XCTAssertEqual(
            BPAppDelegate.notificationNavigationAction(forUserInfo: [
                BPBackgroundUpdater.outdatedNotificationTargetKey: "mixed"
            ]),
            .unifiedUpdates
        )
    }

    func testMissingMalformedAndFutureNotificationPayloadsMapToNoNavigation() {
        XCTAssertEqual(BPAppDelegate.notificationNavigationAction(forUserInfo: nil), .none)
        XCTAssertEqual(BPAppDelegate.notificationNavigationAction(forUserInfo: [:]), .none)
        XCTAssertEqual(
            BPAppDelegate.notificationNavigationAction(forUserInfo: [
                BPBackgroundUpdater.outdatedNotificationTargetKey: 42
            ]),
            .none
        )
        XCTAssertEqual(
            BPAppDelegate.notificationNavigationAction(forUserInfo: [
                BPBackgroundUpdater.outdatedNotificationTargetKey: "future-target"
            ]),
            .none
        )
    }

    private func assertInvalidNotificationResponse(withUserInfo userInfo: NSDictionary?) {
        let delegate = BPAppDelegate()
        let presentation = BPNotificationPresentationSpy()
        let target = BPNotificationNavigationTargetSpy()
        delegate.notificationPresenter = presentation
        delegate.notificationNavigationTarget = target

        nonisolated(unsafe) var completionCount: UInt = 0
        let response = BPNotificationResponseStub()
        response.userInfo = userInfo
        delegate.handleNotificationCenter(
            nil,
            didReceiveNotificationResponse: response,
            withCompletionHandler: { completionCount += 1 }
        )

        XCTAssertEqual(presentation.cleanupCount, 1)
        XCTAssertEqual(presentation.activationCount, 1)
        XCTAssertEqual(presentation.windowCount, 1)
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(target.formulaeNavigationCount, 0)
        XCTAssertEqual(target.caskNavigationCount, 0)
        XCTAssertEqual(target.unifiedUpdatesNavigationCount, 0)
    }

    func testMissingNotificationPayloadPresentsWithoutNavigatingAndCompletesOnce() {
        assertInvalidNotificationResponse(withUserInfo: nil)
    }

    func testEmptyNotificationPayloadPresentsWithoutNavigatingAndCompletesOnce() {
        assertInvalidNotificationResponse(withUserInfo: [:])
    }

    func testMalformedNotificationPayloadPresentsWithoutNavigatingAndCompletesOnce() {
        assertInvalidNotificationResponse(withUserInfo: [
            BPBackgroundUpdater.outdatedNotificationTargetKey: 42
        ] as NSDictionary)
    }

    func testFutureNotificationPayloadPresentsWithoutNavigatingAndCompletesOnce() {
        assertInvalidNotificationResponse(withUserInfo: [
            BPBackgroundUpdater.outdatedNotificationTargetKey: "future-target"
        ] as NSDictionary)
    }

    func testValidNotificationResponsesRouteFormulaeAndCasks() {
        let delegate = BPAppDelegate()
        let presentation = BPNotificationPresentationSpy()
        let target = BPNotificationNavigationTargetSpy()
        delegate.notificationPresenter = presentation
        delegate.notificationNavigationTarget = target

        let destinations = [
            BPBackgroundUpdater.outdatedNotificationTargetFormulae,
            BPBackgroundUpdater.outdatedNotificationTargetCasks,
            BPBackgroundUpdater.outdatedNotificationTargetMixed
        ]
        for destination in destinations {
            let response = BPNotificationResponseStub()
            response.userInfo = [BPBackgroundUpdater.outdatedNotificationTargetKey: destination] as NSDictionary
            delegate.handleNotificationCenter(
                nil,
                didReceiveNotificationResponse: response,
                withCompletionHandler: {}
            )
        }

        XCTAssertEqual(target.formulaeNavigationCount, 1)
        XCTAssertEqual(target.caskNavigationCount, 1)
        XCTAssertEqual(target.unifiedUpdatesNavigationCount, 1)
        XCTAssertEqual(presentation.windowCount, 3)
    }

    func testLaunchPendingNotificationActionIsConsumedExactlyOnce() {
        let delegate = BPAppDelegate()
        let presentation = BPNotificationPresentationSpy()
        delegate.notificationPresenter = presentation
        let response = BPNotificationResponseStub()
        response.userInfo = [
            BPBackgroundUpdater.outdatedNotificationTargetKey: BPBackgroundUpdater.outdatedNotificationTargetCasks
        ] as NSDictionary
        delegate.handleNotificationCenter(
            nil,
            didReceiveNotificationResponse: response,
            withCompletionHandler: {}
        )

        let firstTarget = BPNotificationNavigationTargetSpy()
        delegate.notificationNavigationTarget = firstTarget
        XCTAssertEqual(firstTarget.caskNavigationCount, 1)

        let laterTarget = BPNotificationNavigationTargetSpy()
        delegate.notificationNavigationTarget = laterTarget
        XCTAssertEqual(laterTarget.caskNavigationCount, 0, "the pending action must be consumed, not replayed")
        XCTAssertEqual(presentation.windowCount, 1, "draining navigation must not present the response twice")
    }

    func testNotificationResponseMarshalsAllUIPresentationAndNavigationToMainThreadAndCompletesOnce() {
        let delegate = BPAppDelegate()
        let presentation = BPNotificationPresentationSpy()
        let target = BPNotificationNavigationTargetSpy()
        delegate.notificationPresenter = presentation
        delegate.notificationNavigationTarget = target
        let response = BPNotificationResponseStub()
        response.userInfo = [
            BPBackgroundUpdater.outdatedNotificationTargetKey: BPBackgroundUpdater.outdatedNotificationTargetFormulae
        ] as NSDictionary
        let completed = expectation(description: "notification response completed")
        nonisolated(unsafe) var completionCount: UInt = 0

        DispatchQueue.global(qos: .userInitiated).async {
            delegate.handleNotificationCenter(
                nil,
                didReceiveNotificationResponse: response,
                withCompletionHandler: {
                    completionCount += 1
                    completed.fulfill()
                }
            )
        }

        wait(for: [completed], timeout: 2.0)
        XCTAssertEqual(completionCount, 1)
        XCTAssertTrue(presentation.calledOnMainThread)
        XCTAssertTrue(target.calledOnMainThread)
        XCTAssertEqual(presentation.cleanupCount, 1)
        XCTAssertEqual(presentation.activationCount, 1)
        XCTAssertEqual(presentation.windowCount, 1)
        XCTAssertEqual(target.formulaeNavigationCount, 1)
    }

    func testNotificationNavigationContractIncludesBothDestinations() {
        guard let proto = NSProtocolFromString("BPNotificationNavigation") else {
            XCTFail("BPNotificationNavigation protocol missing")
            return
        }
        let formulae = protocol_getMethodDescription(
            proto,
            #selector(BPNotificationNavigation.showOutdatedFormulae(_:)),
            true,
            true
        )
        let casks = protocol_getMethodDescription(
            proto,
            #selector(BPNotificationNavigation.showOutdatedCasks(_:)),
            true,
            true
        )
        let unified = protocol_getMethodDescription(
            proto,
            #selector(BPNotificationNavigation.showUnifiedUpdates(_:)),
            true,
            true
        )

        XCTAssertNotNil(formulae.name)
        XCTAssertNotNil(casks.name)
        XCTAssertNotNil(unified.name)
    }
}
