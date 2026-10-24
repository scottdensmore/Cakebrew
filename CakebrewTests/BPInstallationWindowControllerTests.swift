//
//  BPInstallationWindowControllerTests.swift
//  CakebrewTests
//

import AppKit
import XCTest

// These doubles record the actual controller's sheet calls without creating
// windows, loading nibs, running Homebrew, or changing persistent app state.
@objc(BPSheetWindowRecorder)
final class BPSheetWindowRecorder: NSObject, @unchecked Sendable {
    @objc weak var sheetParent: AnyObject?
    @objc var presentedSheet: AnyObject?
    @objc var sheetCompletion: ((NSApplication.ModalResponse) -> Void)?
    @objc var events: NSMutableArray?
    @objc var beginCount: UInt = 0
    @objc var endCount: UInt = 0

    @objc(beginSheet:completionHandler:)
    func beginSheet(_ sheet: AnyObject, completionHandler completion: ((NSApplication.ModalResponse) -> Void)?) {
        beginCount += 1
        presentedSheet = sheet
        (sheet as? BPSheetWindowRecorder)?.sheetParent = self
        sheetCompletion = completion
        events?.add("begin")
    }

    @objc(endSheet:)
    func endSheet(_ sheet: AnyObject) {
        endCount += 1
        guard let sheetRecorder = sheet as? BPSheetWindowRecorder,
              sheetRecorder.sheetParent === self else { return }
        sheetRecorder.sheetParent = nil
        let completion = sheetCompletion
        sheetCompletion = nil
        presentedSheet = nil
        completion?(.OK)
    }
}

@objc(BPSheetDelegateRecorder)
final class BPSheetDelegateRecorder: NSObject, NSApplicationDelegate, @unchecked Sendable {
    @objc var window: AnyObject?
    @objc var runningBackgroundTask: Bool = false {
        didSet {
            if runningBackgroundTask {
                busyStarts += 1
            } else {
                busyFinishes += 1
            }
        }
    }
    @objc var busyStarts: UInt = 0
    @objc var busyFinishes: UInt = 0

    @objc(isRunningBackgroundTask)
    func isRunningBackgroundTask() -> Bool {
        runningBackgroundTask
    }
}

@objc(BPSheetApplicationRecorder)
final class BPSheetApplicationRecorder: NSObject, @unchecked Sendable {
    @objc var delegate: BPSheetDelegateRecorder?
    @objc var mainWindow: AnyObject?
    @objc var events: NSMutableArray?
}

@objc(BPUpgradeButtonRecorder)
final class BPUpgradeButtonRecorder: NSObject, @unchecked Sendable {
    @objc var enabled: Bool = false

    @objc(isEnabled)
    func isEnabled() -> Bool {
        enabled
    }
}

private func asNSApplication(_ object: AnyObject) -> NSApplication {
    let raw = Unmanaged.passUnretained(object).toOpaque()
    return Unmanaged<NSApplication>.fromOpaque(raw).takeUnretainedValue()
}

private func asNSWindow(_ object: AnyObject?) -> NSWindow? {
    guard let object else { return nil }
    let raw = Unmanaged.passUnretained(object).toOpaque()
    return Unmanaged<NSWindow>.fromOpaque(raw).takeUnretainedValue()
}

@MainActor
final class BPInstallationWindowControllerTests: XCTestCase, @unchecked Sendable {
    var previousApplication: NSApplication?
    var application: BPSheetApplicationRecorder!
    var parent: BPSheetWindowRecorder!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
        previousApplication = NSApp
        application = BPSheetApplicationRecorder()
        let delegate = BPSheetDelegateRecorder()
        application.delegate = delegate
        application.events = NSMutableArray()
        parent = BPSheetWindowRecorder()
        parent.events = application.events
        delegate.window = parent
        // Restore this process-local global in tearDown. No method swizzling or
        // real NSApplication construction is needed for the recording app.
        NSApp = asNSApplication(application)
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
        parent.sheetCompletion = nil
        parent.presentedSheet = nil
        NSApp = previousApplication
        application = nil
        parent = nil
        }
        super.tearDown()
    }

    func testStartAttachesDelegateWindowBeforeExecutingWhenMainWindowIsNil() {
        XCTAssertNil(NSApp.mainWindow)
        XCTAssertTrue(NSApp.delegate === application.delegate)
        XCTAssertNotNil(application.delegate?.window)
        var completions: UInt = 0
        let controller = BPInertInstallationWindowController.run(
            withOperation: .upgrade,
            formulae: [],
            options: nil
        ) { success in
            XCTAssertTrue(success)
            completions += 1
        }
        XCTAssertEqual(controller.executions, 1)
        XCTAssertTrue(controller.busyAtExecution)
        XCTAssertTrue(controller.parentAtExecution === parent)
        XCTAssertEqual(controller.window?.sheetParent, asNSWindow(parent))
        XCTAssertEqual(parent.beginCount, 1)
        XCTAssertEqual(application.events as? [String], ["begin", "execute"])
        XCTAssertEqual(application.delegate?.busyStarts, 1)
        XCTAssertEqual(application.delegate?.busyFinishes, 0)
        XCTAssertEqual(completions, 0)
        controller.okAction(nil)
        XCTAssertEqual(application.delegate?.runningBackgroundTask, false)
        XCTAssertEqual(completions, 1)
    }

    func testOKDismissesOriginalParentAndCompletesOnceWhenMainWindowIsNil() {
        assertDismissalUsesOriginalParent(withMainWindow: nil)
    }

    func testOKDismissesOriginalParentAndCompletesOnceWhenMainWindowChanges() {
        assertDismissalUsesOriginalParent(withMainWindow: BPSheetWindowRecorder())
    }

    private func assertDismissalUsesOriginalParent(withMainWindow laterWindow: BPSheetWindowRecorder?) {
        application.mainWindow = parent
        var completions: UInt = 0
        let controller = BPInertInstallationWindowController.run(
            withOperation: .upgrade,
            formulae: [],
            options: nil
        ) { [weak self] success in
            XCTAssertTrue(success)
            XCTAssertEqual(self?.application.delegate?.runningBackgroundTask, false)
            completions += 1
        }
        XCTAssertEqual(controller.window?.sheetParent, asNSWindow(parent))
        application.mainWindow = laterWindow
        application.delegate?.window = laterWindow
        XCTAssertEqual(NSApp.mainWindow, asNSWindow(laterWindow))
        controller.okAction(nil)
        controller.okAction(nil)
        XCTAssertEqual(parent.endCount, 1)
        XCTAssertEqual(laterWindow?.endCount ?? 0, 0)
        XCTAssertNil(controller.window?.sheetParent)
        XCTAssertEqual(application.delegate?.runningBackgroundTask, false)
        XCTAssertEqual(application.delegate?.busyFinishes, 1)
        XCTAssertEqual(completions, 1)
    }

    func testCancelledUpgradeCannotDismissOrReleaseBusyStateBeforeWorkerFinishes() {
        let controller = BPInertInstallationWindowController.run(
            withOperation: .upgrade,
            formulae: [],
            options: nil
        )
        let progress = Progress(totalUnitCount: 1)
        controller.setValue(progress, forKey: "upgradeProgress")
        let ok = BPUpgradeButtonRecorder()
        controller.setValue(ok, forKey: "okButton")
        controller.cancelAction(nil)
        XCTAssertTrue(progress.isCancelled)
        XCTAssertFalse(ok.enabled, "Cancellation request is not worker completion")
        controller.okAction(nil)
        XCTAssertEqual(application.delegate?.runningBackgroundTask, true)
        XCTAssertEqual(parent.endCount, 0, "No second operation while the owned worker unwinds")
    }
}
