import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import UserNotifications

private final class BPAutoScrollBuffer: @unchecked Sendable {
    let lock = NSLock()
    let pending = NSMutableString()
    var flushScheduled = false
}

@MainActor
@objc(BPAutoScrollTextView)
public final class BPAutoScrollTextView: NSTextView {
    nonisolated private static let maxScrollback = 2 * 1024 * 1024
    nonisolated private static let trimTargetLength = Int(1.5 * 1024.0 * 1024.0)
    private let buffer = BPAutoScrollBuffer()

    @objc nonisolated public static var maximumScrollbackLength: UInt {
        return UInt(maxScrollback)
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override var string: String {
        get { super.string }
        set {
            super.string = newValue
            scrollToEndOfDocument(self)
        }
    }

    @objc(appendOutput:)
    nonisolated public func appendOutput(_ chunk: String?) {
        guard let chunk, !chunk.isEmpty else { return }
        var needsFlush = false
        buffer.lock.lock()
        buffer.pending.append(chunk)
        if !buffer.flushScheduled {
            buffer.flushScheduled = true
            needsFlush = true
        }
        buffer.lock.unlock()

        guard needsFlush else { return }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.flushPendingOutput()
            }
        } else {
            DispatchQueue.main.async {
                self.flushPendingOutput()
            }
        }
    }

    @objc public func clearOutput() {
        buffer.lock.lock()
        buffer.pending.setString("")
        buffer.lock.unlock()
        self.string = ""
    }

    @objc public func flushPendingOutput() {
        buffer.lock.lock()
        let chunk = buffer.pending.copy() as? String ?? ""
        buffer.pending.setString("")
        buffer.flushScheduled = false
        buffer.lock.unlock()

        guard !chunk.isEmpty, let storage = self.textStorage else { return }
        let chunkNS = chunk as NSString
        storage.beginEditing()
        let appendedRange = NSRange(location: storage.length, length: chunkNS.length)
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: chunk)
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: appendedRange)
        trimScrollback(in: storage)
        storage.endEditing()

        scrollRangeToVisible(NSRange(location: storage.length, length: 0))
    }

    private func trimScrollback(in storage: NSTextStorage) {
        guard storage.length > Self.maxScrollback else { return }
        var excess = storage.length - Self.trimTargetLength
        let nsString = storage.string as NSString
        let searchLength = min(4096, storage.length - excess)
        let newline = nsString.range(of: "\n", options: [], range: NSRange(location: excess, length: searchLength))
        if newline.location != NSNotFound {
            excess = NSMaxRange(newline)
        }
        storage.replaceCharacters(in: NSRange(location: 0, length: excess), with: "")
    }
}

