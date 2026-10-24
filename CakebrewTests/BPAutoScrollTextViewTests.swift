//
//  BPAutoScrollTextViewTests.swift
//  CakebrewTests
//
//  Appending is now the view's job, so these tests pin the behaviour the three
//  controllers depend on.
//

import AppKit
import XCTest

@MainActor
final class BPAutoScrollTextViewTests: XCTestCase, @unchecked Sendable {
    private var textView: BPAutoScrollTextView!

    override nonisolated func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            self.textView = BPAutoScrollTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        }
    }

    override nonisolated func tearDown() {
        MainActor.assumeIsolated {
            self.textView = nil
        }
        super.tearDown()
    }

    // MARK: - accumulation

    func testStreamedTextRetainsSemanticForegroundColorAfterClearAndReappend() {
        textView.textColor = .textColor
        for _ in 0..<2 {
            textView.clearOutput()
            textView.appendOutput("first ")
            textView.appendOutput("second")
            textView.flushPendingOutput()
            guard let storage = textView.textStorage else {
                XCTFail("expected textStorage")
                return
            }
            storage.enumerateAttribute(
                .foregroundColor,
                in: NSRange(location: 0, length: storage.length),
                options: []
            ) { value, _, _ in
                let color = value as? NSColor
                XCTAssertEqual(color, NSColor.textColor, "every streamed character needs an appearance-adaptive foreground")
                var light: CGFloat = 0
                var dark: CGFloat = 0
                NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                    light = color?.usingColorSpace(.genericRGB)?.redComponent ?? 0
                }
                NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
                    dark = color?.usingColorSpace(.genericRGB)?.redComponent ?? 0
                }
                XCTAssertGreaterThan(dark, light, "the stored color must adapt when appearance changes")
            }
        }
    }

    func testChunksAccumulateInOrder() {
        textView.appendOutput("one ")
        textView.appendOutput("two ")
        textView.appendOutput("three")
        textView.flushPendingOutput()

        XCTAssertEqual(textView.string, "one two three")
    }

    func testManyChunksAreAllPresentAndOrdered() {
        var expected = ""
        for i in 0..<500 {
            let chunk = "line-\(i)\n"
            expected.append(chunk)
            textView.appendOutput(chunk)
        }
        textView.flushPendingOutput()

        XCTAssertEqual(textView.string, expected, "chunks were dropped or reordered")
    }

    func testAppendingDoesNotDiscardTextAlreadyInTheView() {
        textView.string = "header\n"
        textView.appendOutput("streamed")
        textView.flushPendingOutput()

        XCTAssertEqual(textView.string, "header\nstreamed")
    }

    func testClearingResetsTheBufferToo() {
        textView.appendOutput("stale")
        textView.clearOutput()
        textView.appendOutput("fresh")
        textView.flushPendingOutput()

        XCTAssertEqual(textView.string, "fresh", "a chunk buffered before the clear must not reappear after it")
    }

    func testEmptyAndNilChunksAreIgnored() {
        textView.appendOutput("kept")
        textView.appendOutput("")
        textView.appendOutput(nil)
        textView.flushPendingOutput()

        XCTAssertEqual(textView.string, "kept")
    }

    // MARK: - coalescing

    func testBufferedChunksAreAppliedInASingleEdit() {
        var edits: UInt = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: nil
        ) { _ in
            edits += 1
        }

        for _ in 0..<50 {
            textView.appendOutput("x")
        }
        textView.flushPendingOutput()
        NotificationCenter.default.removeObserver(observer)

        XCTAssertEqual(textView.string, String(repeating: "x", count: 50))
        XCTAssertLessThanOrEqual(edits, 1, "each chunk caused its own edit instead of being coalesced")
    }

    func testFlushingWithNothingBufferedIsHarmless() {
        textView.flushPendingOutput()
        textView.flushPendingOutput()
        XCTAssertEqual(textView.string, "")
    }

    // MARK: - bounded scrollback

    func testScrollbackIsCappedSoALongRunCannotGrowUnbounded() {
        let line = String(repeating: "y", count: 99) + "\n"
        for _ in 0..<40000 {
            textView.appendOutput(line)
        }
        textView.flushPendingOutput()

        XCTAssertLessThanOrEqual(
            UInt((textView.string as NSString).length),
            BPAutoScrollTextView.maximumScrollbackLength,
            "transcript grew past the cap"
        )
        XCTAssertGreaterThan((textView.string as NSString).length, 0)
        XCTAssertTrue(textView.string.hasSuffix(line), "the tail — the part the user is watching — must survive")
    }

    // MARK: - threading

    func testAppendingFromABackgroundThreadIsSafeAndOrderPreserving() {
        let producer = DispatchQueue(label: "test.producer")
        var expected = ""
        let view = textView!
        for i in 0..<200 {
            let chunk = "\(i),"
            expected.append(chunk)
            producer.async {
                view.appendOutput(chunk)
            }
        }
        producer.sync {}
        textView.flushPendingOutput()

        XCTAssertEqual(textView.string, expected)
    }
}
