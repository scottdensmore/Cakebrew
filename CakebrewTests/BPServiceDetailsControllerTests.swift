//
//  BPServiceDetailsControllerTests.swift
//  CakebrewTests
//

import AppKit
import XCTest

@MainActor
final class BPServiceDetailsControllerTests: XCTestCase, @unchecked Sendable {

    private func invokeDetailsCompletion(
        _ rawBlock: Any?,
        with details: BPServiceDetails?
    ) {
        guard let obj = rawBlock as AnyObject? else {
            XCTFail("Missing details completion block")
            return
        }
        let block = unsafeBitCast(obj, to: (@convention(block) (BPServiceDetails?) -> Void).self)
        block(details)
    }

    func testRefreshReloadsDetailsWhenTheSelectedRowDoesNotChange() {
        let controller = makeController()
        select(0, controller: controller)
        controller.refreshServices()
        controller.listCompletion?(controller.services)
        XCTAssertEqual(controller.completions?.count, 2)
    }

    func testFailurePreservesListAndCompleteRawDiagnostic() {
        let controller = makeController()
        let services = controller.services
        select(0, controller: controller)
        let raw = ("Error: diagnostic\n" as NSString).padding(toLength: 4000, withPad: "full transcript\n", startingAt: 0)
        invokeDetailsCompletion(
            controller.completions?.lastObject,
            with: BPServiceDetails.details(forName: "a", output: raw, succeeded: false)
        )
        XCTAssertEqual(controller.services, services)
        XCTAssertEqual(controller.tableView?.numberOfRows, 2)
        XCTAssertEqual(controller.detailsText?.string.contains(raw), true)
        let visibleFailure = "\(NSLocalizedString("Services_Details_Failed", comment: ""))\n\(raw)"
        XCTAssertEqual(
            controller.detailsText?.string.hasPrefix(visibleFailure),
            true,
            "Failure and raw diagnostic must lead the initial viewport, before metadata placeholders."
        )
        XCTAssertEqual(controller.outputCopyButton?.isEnabled, true)
        XCTAssertEqual(controller.logsButton?.isEnabled, false)
        XCTAssertEqual(controller.revealButton?.isEnabled, false)
    }

    func testRefreshAndLeavingRejectBothOldDetailsAndOldListReplies() {
        let controller = makeController()
        let services = controller.services
        select(0, controller: controller)
        let detailsReply = controller.completions?.lastObject
        controller.refreshServices()
        invokeDetailsCompletion(detailsReply, with: makeDetails("a"))
        XCTAssertNil(controller.details)
        controller.invalidateServiceDetails()
        controller.listCompletion?([])
        XCTAssertEqual(controller.services, services)
    }

    func testFileActionsDeduplicateAndRevalidateAtClickTime() throws {
        let directory = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        let files = FileManager.default
        try files.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
        let path = (directory as NSString).appendingPathComponent("fixture.log")
        try "fixture".write(toFile: path, atomically: true, encoding: .utf8)
        let controller = makeController()
        select(0, controller: controller)
        let completion = controller.completions?.lastObject
        let data = try JSONSerialization.data(
            withJSONObject: [[
                "name": "a",
                "file": "/missing/file",
                "loaded_file": path,
                "log_path": path,
                "error_log_path": path
            ]],
            options: []
        )
        let output = String(data: data, encoding: .utf8)
        invokeDetailsCompletion(completion, with: BPServiceDetails.details(forName: "a", output: output, succeeded: true))
        XCTAssertEqual(controller.logsButton?.isEnabled, true)
        XCTAssertEqual(controller.revealButton?.isEnabled, true)
        controller.openServiceLogs(nil)
        controller.revealServiceFile(nil)
        XCTAssertEqual(controller.openedURLs?.count, 1)
        XCTAssertEqual(controller.revealedURL?.path, (path as NSString).resolvingSymlinksInPath)
        controller.openedURLs = nil
        controller.revealedURL = nil
        try files.removeItem(atPath: path)
        controller.openServiceLogs(nil)
        controller.revealServiceFile(nil)
        XCTAssertNil(controller.openedURLs)
        XCTAssertNil(controller.revealedURL)
        XCTAssertEqual(controller.logsButton?.isEnabled, false)
        XCTAssertEqual(controller.revealButton?.isEnabled, false)
        try files.removeItem(atPath: directory)
    }

    private func makeController() -> BPDeferredServicesController {
        let controller = BPDeferredServicesController()
        controller.completions = NSMutableArray()
        _ = controller.view
        controller.services = BPService.services(fromJSONString: "[{\"name\":\"a\",\"status\":\"started\"},{\"name\":\"b\",\"status\":\"none\"}]")
        controller.tableView?.reloadData()
        return controller
    }

    private func select(_ row: Int, controller: BPDeferredServicesController) {
        controller.tableView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func makeDetails(_ name: String) -> BPServiceDetails {
        BPServiceDetails.details(forName: name, output: "[{\"name\":\"\(name)\"}]", succeeded: true)
    }

    func testLateAResponseCannotReplaceBOrNewASelection() {
        let controller = makeController()
        select(0, controller: controller)
        select(1, controller: controller)
        XCTAssertEqual(controller.completions?.count, 2)
        guard controller.completions?.count == 2 else { return }
        let oldA = controller.completions?[0]
        let b = controller.completions?[1]
        let bDetails = makeDetails("b")
        invokeDetailsCompletion(b, with: bDetails)
        invokeDetailsCompletion(oldA, with: makeDetails("a"))
        XCTAssertEqual(controller.details, bDetails)
        select(0, controller: controller)
        invokeDetailsCompletion(oldA, with: makeDetails("a"))
        XCTAssertNil(controller.details)
        let newA = controller.completions?.lastObject
        let aDetails = makeDetails("a")
        invokeDetailsCompletion(newA, with: aDetails)
        XCTAssertEqual(controller.details, aDetails)
    }

    func testInvalidationAndDeselectRejectPendingResultsWithoutReplacingList() {
        let controller = makeController()
        let services = controller.services
        select(0, controller: controller)
        XCTAssertEqual(controller.completions?.count, 1)
        guard (controller.completions?.count ?? 0) > 0 else { return }
        let completion = controller.completions?.lastObject
        controller.invalidateServiceDetails()
        invokeDetailsCompletion(completion, with: makeDetails("a"))
        XCTAssertNil(controller.details)
        controller.tableView?.deselectAll(nil)
        invokeDetailsCompletion(completion, with: makeDetails("a"))
        XCTAssertNil(controller.details)
        XCTAssertEqual(controller.services, services)
    }
}
