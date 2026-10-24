//
//  BPTaskCancelTests.swift
//  CakebrewTests
//
//  Once an operation started there was no way out: the operation sheet's only
//  button was a disabled OK, re-enabled after the task returned, and the sheet
//  is attached to the main window — so for the whole duration of a large cask
//  download or a source build the user could not dismiss it, use the app, or
//  abort a mistaken operation. BPTask had no cancel API at all.
//
//  Killing the NSTask alone is not enough: the task is a login shell running
//  brew, and brew spawns its own children (curl, git, compilers). Terminating
//  only the shell orphans them, so a "cancelled" download keeps running.
//

import Darwin
import XCTest

final class BPTaskCancelTests: XCTestCase, @unchecked Sendable {

    func testCancelledProgressPreventsLaunchBeforeAsynchronousHandlerDelivery() {
        let task = BPTask(path: "/bin/sh", arguments: ["-c", "echo DELAYED_HANDLER_LAUNCH"])
        let progress = Progress(totalUnitCount: 1)
        task.cancellationProgress = progress
        // Deliberately no handler calls -cancel: the task must inspect the token.
        progress.cancel()
        XCTAssertFalse(task.wasCancelled)
        XCTAssertNotEqual(task.execute(), 0)
        XCTAssertTrue(task.wasCancelled)
        XCTAssertFalse(task.output.contains("DELAYED_HANDLER_LAUNCH"))
    }

    func testCancelledBeforeExecuteNeverLaunchesAndCannotReportSuccess() {
        let task = BPTask(path: "/bin/sh", arguments: ["-c", "echo SHOULD_NOT_EXECUTE"])
        task.cancel()
        XCTAssertNotEqual(task.execute(), 0)
        XCTAssertFalse(task.output.contains("SHOULD_NOT_EXECUTE"))
    }

    /// Runs `task` off the main thread; returns the exit status via `status`.
    @discardableResult
    private func run(_ task: BPTask, timeout: TimeInterval, status: inout Int32) -> Bool {
        let finished = expectation(description: "finished")
        nonisolated(unsafe) var result: Int32 = 0
        DispatchQueue.global(qos: .userInitiated).async {
            result = task.execute()
            finished.fulfill()
        }
        let waited = XCTWaiter.wait(for: [finished], timeout: timeout)
        status = result
        return waited == .completed
    }

    func testCancellingEndsATaskThatWouldOtherwiseRunOn() {
        let task = BPTask(path: "/bin/sh", arguments: ["-c", "echo started; sleep 120"])

        let started = expectation(description: "started")
        nonisolated(unsafe) var signalled = false
        task.updateBlock = { chunk in
            if !signalled && chunk.contains("started") {
                signalled = true
                started.fulfill()
            }
        }

        let finished = expectation(description: "finished")
        DispatchQueue.global(qos: .userInitiated).async {
            _ = task.execute()
            finished.fulfill()
        }

        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 15.0), .completed)
        task.cancel()

        // Without cancel this would sit for two minutes.
        XCTAssertEqual(
            XCTWaiter.wait(for: [finished], timeout: 15.0),
            .completed,
            "cancel should end the run promptly"
        )
    }

    func testCancellingKillsTheChildrenBrewWouldHaveSpawned() {
        // The shell outlives nothing, but its children do unless they are killed
        // too — brew's downloads and builds are all children.
        let marker = "cakebrew-cancel-\(UUID().uuidString)"
        let script = "sh -c 'exec -a \(marker) sleep 120' & echo started; wait"

        let task = BPTask(path: "/bin/sh", arguments: ["-c", script])
        let started = expectation(description: "started")
        nonisolated(unsafe) var signalled = false
        task.updateBlock = { chunk in
            if !signalled && chunk.contains("started") {
                signalled = true
                started.fulfill()
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            _ = task.execute()
        }
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 15.0), .completed)

        task.cancel()

        // Give the signals a moment, then confirm nothing of ours is left running.
        let deadline = Date(timeIntervalSinceNow: 10.0)
        var gone = false
        while !gone && deadline.timeIntervalSinceNow > 0 {
            gone = !anyProcessMatching(marker)
            if !gone {
                Thread.sleep(forTimeInterval: 0.25)
            }
        }

        if !gone {
            killProcessesMatching(marker)
        }
        XCTAssertTrue(gone, "cancelling must not leave brew's children running")
    }

    private func killProcessesMatching(_ marker: String) {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", marker]
        try? pkill.run()
        pkill.waitUntilExit()
    }

    private func anyProcessMatching(_ marker: String) -> Bool {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", marker]
        pgrep.standardOutput = Pipe()
        pgrep.standardError = Pipe()
        try? pgrep.run()
        pgrep.waitUntilExit()
        return pgrep.terminationStatus == 0
    }

    func testCancellingBeforeLaunchIsHarmless() {
        // The user can hit Cancel between presenting the sheet and the process
        // actually starting.
        let task = BPTask(path: "/bin/sh", arguments: ["-c", "true"])
        XCTAssertNoThrow(task.cancel())
    }

    func testACancelledTaskReportsFailureRatherThanSuccess() {
        // operationStatus drives the "finished" vs "failed" wording, and a
        // cancelled run is not a success.
        let task = BPTask(path: "/bin/sh", arguments: ["-c", "echo started; sleep 120"])
        let started = expectation(description: "started")
        nonisolated(unsafe) var signalled = false
        task.updateBlock = { chunk in
            if !signalled && chunk.contains("started") {
                signalled = true
                started.fulfill()
            }
        }

        nonisolated(unsafe) var status: Int32 = 0
        let finished = expectation(description: "finished")
        DispatchQueue.global(qos: .userInitiated).async {
            status = task.execute()
            finished.fulfill()
        }

        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 15.0), .completed)
        task.cancel()
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 15.0), .completed)

        XCTAssertNotEqual(status, 0, "a cancelled run must not report success")
        XCTAssertTrue(task.wasCancelled, "the caller needs to tell cancellation from a brew failure")
    }
}
