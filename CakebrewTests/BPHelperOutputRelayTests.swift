//
//  BPHelperOutputRelayTests.swift
//  CakebrewTests
//

import Foundation
import XCTest

private final class BPChunkRecorder: @unchecked Sendable {
    var chunks: [String] = []
    var calls: UInt = 0
}

final class BPHelperOutputRelayTests: XCTestCase, @unchecked Sendable {

    private func D(_ string: String) -> Data {
        Data(string.utf8)
    }

    // MARK: - accumulation

    func testAccumulatesChunksInOrder() {
        let relay = BPHelperOutputRelay(sink: nil)
        relay.appendData(D("==> Downloading\n"))
        relay.appendData(D("==> Pouring\n"))

        XCTAssertEqual(relay.accumulatedOutput, "==> Downloading\n==> Pouring\n")
    }

    func testAccumulatedOutputIsEmptyWhenNothingArrived() {
        let relay = BPHelperOutputRelay(sink: nil)
        XCTAssertEqual(relay.accumulatedOutput, "")
    }

    // MARK: - forwarding

    func testForwardsEachChunkToTheSink() {
        let recorder = BPChunkRecorder()
        let relay = BPHelperOutputRelay { chunk in
            recorder.chunks.append(chunk)
        }

        relay.appendData(D("first"))
        relay.appendData(D("second"))

        XCTAssertEqual(recorder.chunks, ["first", "second"], "chunks stream as they arrive rather than only at the end")
    }

    func testNilSinkIsSafe() {
        let relay = BPHelperOutputRelay(sink: nil)
        relay.appendData(D("no sink attached"))
        XCTAssertEqual(relay.accumulatedOutput, "no sink attached", "accumulation still happens without a sink")
    }

    func testEmptyDataIsNotForwarded() {
        let recorder = BPChunkRecorder()
        let relay = BPHelperOutputRelay { _ in
            recorder.calls += 1
        }

        relay.appendData(Data())
        relay.appendData(nil)

        XCTAssertEqual(recorder.calls, 0, "empty reads must not generate XPC traffic")
        XCTAssertEqual(relay.accumulatedOutput, "")
    }

    // MARK: - robustness

    func testSplitMultiByteCharacterDoesNotCorruptOutput() {
        let full = D("✔")
        let relay = BPHelperOutputRelay(sink: nil)
        relay.appendData(full.subdata(in: 0..<1))
        relay.appendData(full.subdata(in: 1..<full.count))

        XCTAssertEqual(relay.accumulatedOutput, "✔", "a character split across reads must be reassembled")
    }

    func testConcurrentAppendsDoNotLoseOutput() {
        let relay = BPHelperOutputRelay(sink: nil)
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            relay.appendData(Data("x".utf8))
        }

        XCTAssertEqual(relay.accumulatedOutput.count, 200, "no writes lost under concurrency")
    }
}
