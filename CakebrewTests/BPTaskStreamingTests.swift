//
//  BPTaskStreamingTests.swift
//  CakebrewTests
//
//  BPTask answered NSFileHandleDataAvailableNotification with
//  -readDataToEndOfFile, which blocks until the child closes the pipe. Nothing
//  streamed (the operation sheet stayed blank for the whole run), and because
//  the reading thread was parked in one pipe, the other was never drained —
//  brew filling the unread pipe's 64 KB buffer would block on write and never
//  exit, wedging the app.
//
//  These tests drive a real /bin/sh so they exercise the pipe plumbing rather
//  than a stub. Each one is bounded: on the pre-fix code they time out rather
//  than hang the suite.
//

import XCTest

final class BPTaskStreamingTests: XCTestCase, @unchecked Sendable {

    // MARK: - helpers

    /// Runs `task` off the main thread and waits up to `timeout` for it to finish.
    /// Returns false if it did not, after terminating it so the suite can continue.
    private func runTask(_ task: BPTask, timeout: TimeInterval, status: inout Int32) -> Bool {
        let finished = expectation(description: "task finished")
        nonisolated(unsafe) var result: Int32 = -1
        DispatchQueue.global(qos: .userInitiated).async {
            result = task.execute()
            finished.fulfill()
        }

        let waited = XCTWaiter.wait(for: [finished], timeout: timeout)
        if waited != .completed {
            task.cleanup()
            return false
        }
        status = result
        return true
    }

    private func count(of needle: String, in haystack: String?) -> UInt {
        guard let haystack, !haystack.isEmpty else {
            return 0
        }
        let nsHaystack = haystack as NSString
        var count: UInt = 0
        var search = NSRange(location: 0, length: nsHaystack.length)
        while search.length > 0 {
            let found = nsHaystack.range(of: needle, options: [], range: search)
            if found.location == NSNotFound {
                break
            }
            count += 1
            let next = NSMaxRange(found)
            search = NSRange(location: next, length: nsHaystack.length - next)
        }
        return count
    }

    // MARK: - streaming

    func testChunksAreDeliveredWhileTheProcessIsStillRunning() {
        // The script blocks until the test creates the gate file, and the test only
        // creates it from inside the update block. So the process can only exit if
        // output was delivered mid-run — the whole point of streaming.
        let gate = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        let script = "echo ready; while [ ! -f '\(gate)' ]; do sleep 0.05; done; echo finished"

        let task = BPTask(path: "/bin/sh", arguments: ["-c", script])
        nonisolated(unsafe) var opened = false
        task.updateBlock = { chunk in
            if !opened && chunk.contains("ready") {
                opened = true
                FileManager.default.createFile(atPath: gate, contents: Data(), attributes: nil)
            }
        }

        var status: Int32 = -1
        let finished = runTask(task, timeout: 15.0, status: &status)
        try? FileManager.default.removeItem(atPath: gate)

        XCTAssertTrue(finished, "the process never exited: output was not streamed while it ran")
        XCTAssertTrue(opened, "the update block never saw the first line")
        XCTAssertEqual(status, 0)
        XCTAssertTrue(task.output.contains("finished"), "the tail after the last chunk was lost")
    }

    func testBothPipesDrainConcurrentlyBeyondThePipeBuffer() {
        // ~140 KB down each pipe, well past the 64 KB buffer. If only one pipe is
        // being read, the child blocks writing to the other and never exits.
        let script =
            "i=0; while [ $i -lt 4000 ]; do "
            + "echo 'out-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; "
            + "echo 'err-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' >&2; "
            + "i=$((i+1)); done"

        let task = BPTask(path: "/bin/sh", arguments: ["-c", script])
        task.updateBlock = { _ in /* streaming enabled */ }

        var status: Int32 = -1
        XCTAssertTrue(
            runTask(task, timeout: 30.0, status: &status),
            "deadlocked: one pipe filled while the other was being read"
        )
        XCTAssertEqual(status, 0)
        XCTAssertEqual(count(of: "out-", in: task.output), 4000, "stdout lost data")
        XCTAssertEqual(count(of: "err-", in: task.error), 4000, "stderr lost data")
    }

    func testLargeOutputSurvivesWithoutAnUpdateBlock() {
        // The synchronous path (no update block) read stdout to end, then stderr —
        // same deadlock, and it is the path every list call takes.
        let script =
            "i=0; while [ $i -lt 4000 ]; do "
            + "echo 'out-cccccccccccccccccccccccccccccccccccccc'; "
            + "echo 'err-dddddddddddddddddddddddddddddddddddddd' >&2; "
            + "i=$((i+1)); done"

        let task = BPTask(path: "/bin/sh", arguments: ["-c", script])

        var status: Int32 = -1
        XCTAssertTrue(runTask(task, timeout: 30.0, status: &status), "deadlocked with no update block")
        XCTAssertEqual(status, 0)
        XCTAssertEqual(count(of: "out-", in: task.output), 4000)
        XCTAssertEqual(count(of: "err-", in: task.error), 4000)
    }

    // MARK: - decoding

    func testMultiByteCharactersSplitAcrossReadsSurvive() {
        // brew prints ✔ / ✘ / → constantly. Past 64 KB the reads certainly split a
        // multi-byte sequence; -initWithData:encoding: returns nil on a partial
        // sequence, so an unbuffered decoder silently drops the whole chunk.
        let script =
            "i=0; while [ $i -lt 3000 ]; do printf '\\342\\234\\224\\342\\234\\230\\342\\206\\222 streaming check\\n'; i=$((i+1)); done"

        let task = BPTask(path: "/bin/sh", arguments: ["-c", script])
        let lock = NSLock()
        nonisolated(unsafe) let streamed = NSMutableString()
        task.updateBlock = { chunk in
            lock.lock()
            streamed.append(chunk)
            lock.unlock()
        }

        var status: Int32 = -1
        XCTAssertTrue(runTask(task, timeout: 30.0, status: &status))
        XCTAssertEqual(status, 0)

        XCTAssertEqual(count(of: "✔", in: task.output), 3000, "accumulated output dropped split sequences")
        XCTAssertEqual(count(of: "→", in: task.output), 3000)
        lock.lock()
        let streamedSnapshot = streamed.copy() as? String
        lock.unlock()
        XCTAssertEqual(count(of: "✔", in: streamedSnapshot), 3000, "streamed chunks dropped split sequences")
    }

    // MARK: - lifecycle

    func testNonZeroExitStatusIsReported() {
        let task = BPTask(path: "/bin/sh", arguments: ["-c", "echo nope >&2; exit 3"])
        var status: Int32 = -1
        XCTAssertTrue(runTask(task, timeout: 10.0, status: &status))
        XCTAssertEqual(status, 3)
        XCTAssertTrue(task.error.contains("nope"))
    }

    func testStdinIsClosedSoChildrenDoNotBlockWaitingForInput() {
        // Nothing ever wrote to the task's stdin, but it was left attached to the
        // app's. A child that reads stdin would hang forever; it must see EOF.
        let task = BPTask(path: "/bin/sh", arguments: ["-c", "cat; echo done"])
        var status: Int32 = -1
        XCTAssertTrue(
            runTask(task, timeout: 10.0, status: &status),
            "the child blocked reading stdin"
        )
        XCTAssertEqual(status, 0)
        XCTAssertTrue(task.output.contains("done"))
    }
}
